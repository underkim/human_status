// Core release-readiness audit logic, kept separate from the CLI entry
// point (tool/check_release_readiness.dart) so it can be unit-tested
// against temporary fixture directories without touching the real repo.
//
// This only reads files under the given [root]; it never writes anything.
import 'dart:io';

/// One concrete finding. [id] is a stable machine-readable key (used by the
/// JSON output and by tests); [message] is the human-facing Korean
/// explanation of what is wrong and how to fix it.
class ReleaseReadinessIssue {
  const ReleaseReadinessIssue({
    required this.id,
    required this.category,
    required this.message,
    this.filePath,
  });

  final String id;
  final String category;
  final String message;
  final String? filePath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'message': message,
    if (filePath != null) 'filePath': filePath,
  };
}

class ReleaseReadinessReport {
  const ReleaseReadinessReport(this.issues);

  final List<ReleaseReadinessIssue> issues;

  bool get isReady => issues.isEmpty;

  Map<String, dynamic> toJson() => {
    'ready': isReady,
    'issues': issues.map((i) => i.toJson()).toList(),
  };
}

const _placeholderDomain = 'com.example';

/// `MAJOR.MINOR.PATCH[-prerelease]+BUILD`, matching what `flutter build`
/// accepts as `--build-name+--build-number` (pubspec `version:` field).
/// The build number is mandatory here even though pub itself allows a bare
/// semantic version, because Android/iOS store submissions require one.
final _versionPattern = RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\+(\d+)$');

String? _firstMatch(String content, RegExp pattern) {
  final match = pattern.firstMatch(content);
  if (match == null || match.groupCount < 1) return null;
  return match.group(1);
}

/// Runs every release-readiness check against [root] (the repository root)
/// and returns the combined report. Never throws for expected "file
/// missing"/"pattern not found" situations -- those become issues instead,
/// so a partially-set-up checkout still produces actionable output.
///
/// [environment] is injectable so tests can simulate CI credential
/// environment variables without touching the real process environment; it
/// defaults to [Platform.environment].
ReleaseReadinessReport checkReleaseReadiness(
  Directory root, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final issues = <ReleaseReadinessIssue>[
    ..._checkAndroid(root, env),
    ..._checkIosBundleId(root),
    ..._checkMacosBundleId(root),
    ..._checkLinuxApplicationId(root),
    ..._checkVersion(root),
    ..._checkPrivacyPolicy(root),
  ];
  return ReleaseReadinessReport(issues);
}

File _file(Directory root, String relativePath) =>
    File('${root.path}/$relativePath');

/// CI environment variable names accepted for release signing credentials.
/// Kept as a `propertyKey -> envVar` map so the same names drive both the
/// android/key.properties lookup and the CI environment lookup, matching
/// android/app/build.gradle.kts.
const _releaseSigningEnvVars = {
  'storeFile': 'ANDROID_KEYSTORE_PATH',
  'storePassword': 'ANDROID_STORE_PASSWORD',
  'keyAlias': 'ANDROID_KEY_ALIAS',
  'keyPassword': 'ANDROID_KEY_PASSWORD',
};

/// Strips `//` line comments and `/* ... */` block comments from Kotlin
/// source text before the env-wiring checks run, so wiring that only
/// exists inside a comment (including a comment that fakes a whole
/// `System.getenv("ANDROID_...")` line/block, not just the bare name) can
/// never be mistaken for real code.
///
/// This is string-literal-aware (single-pass scan, not a regex): a `"..."`
/// double-quoted string is copied through verbatim, honoring `\"`
/// backslash-escapes, so a `//` or `/*` *inside* a string is never
/// mistaken for a comment delimiter. This matters in both directions --
/// naive regex stripping would (a) wrongly truncate a real, live line
/// after a string containing "//" (e.g. a URL), hiding real wiring code
/// that follows and misreporting it as unwired, and (b) let a string
/// containing "*/" prematurely close a block comment, resurrecting
/// commented-out fake wiring as if it were live code -- reopening the very
/// bypass this function exists to close. Kotlin triple-quoted (`"""`) raw
/// strings are not specially handled; this remains a simplified check, not
/// a full Kotlin lexer, and this repo's build.gradle.kts does not use them.
String _stripKotlinComments(String content) {
  final buffer = StringBuffer();
  final len = content.length;
  var i = 0;
  while (i < len) {
    final char = content[i];
    if (char == '"') {
      // Copy the whole string literal verbatim (escapes included) so
      // nothing inside it is mistaken for a comment delimiter.
      buffer.write(char);
      i++;
      while (i < len) {
        final c = content[i];
        if (c == '\\' && i + 1 < len) {
          buffer.write(c);
          buffer.write(content[i + 1]);
          i += 2;
          continue;
        }
        buffer.write(c);
        i++;
        if (c == '"') break;
      }
      continue;
    }
    if (char == '/' && i + 1 < len && content[i + 1] == '/') {
      while (i < len && content[i] != '\n') {
        i++;
      }
      continue;
    }
    if (char == '/' && i + 1 < len && content[i + 1] == '*') {
      i += 2;
      while (i + 1 < len && !(content[i] == '*' && content[i + 1] == '/')) {
        i++;
      }
      i = (i + 1 < len) ? i + 2 : len;
      continue;
    }
    buffer.write(char);
    i++;
  }
  return buffer.toString();
}

List<ReleaseReadinessIssue> _checkAndroid(
  Directory root,
  Map<String, String> environment,
) {
  final issues = <ReleaseReadinessIssue>[];
  const gradlePath = 'android/app/build.gradle.kts';
  final gradleFile = _file(root, gradlePath);
  if (!gradleFile.existsSync()) {
    return [
      ReleaseReadinessIssue(
        id: 'android_build_gradle_missing',
        category: 'android',
        message: '$gradlePath 파일을 찾을 수 없습니다. Android 프로젝트 구조를 확인하세요.',
        filePath: gradlePath,
      ),
    ];
  }
  final content = gradleFile.readAsStringSync();

  final namespace = _firstMatch(content, RegExp(r'namespace\s*=\s*"([^"]+)"'));
  final applicationId = _firstMatch(
    content,
    RegExp(r'applicationId\s*=\s*"([^"]+)"'),
  );

  if (namespace == null) {
    issues.add(
      ReleaseReadinessIssue(
        id: 'android_namespace_missing',
        category: 'android',
        message: '$gradlePath 에서 namespace 설정을 찾지 못했습니다.',
        filePath: gradlePath,
      ),
    );
  } else if (namespace.startsWith(_placeholderDomain)) {
    issues.add(
      ReleaseReadinessIssue(
        id: 'android_namespace_placeholder',
        category: 'android',
        message:
            'Android namespace가 아직 기본값($namespace)입니다. '
            '$gradlePath 의 namespace를 실제 소유한 도메인 기반 ID로 변경하세요 '
            '(예: com.yourcompany.human_status). 한 번 배포하면 사실상 변경할 수 없는 '
            '영구 식별자이므로 반드시 출시 전에 확정해야 합니다.',
        filePath: gradlePath,
      ),
    );
  }

  if (applicationId == null) {
    issues.add(
      ReleaseReadinessIssue(
        id: 'android_application_id_missing',
        category: 'android',
        message: '$gradlePath 에서 applicationId 설정을 찾지 못했습니다.',
        filePath: gradlePath,
      ),
    );
  } else if (applicationId.startsWith(_placeholderDomain)) {
    issues.add(
      ReleaseReadinessIssue(
        id: 'android_application_id_placeholder',
        category: 'android',
        message:
            'Android applicationId가 아직 기본값($applicationId)입니다. '
            'Play Console에 등록하면 이 값은 영구히 고정되므로, $gradlePath 에서 '
            '실제 배포용 ID로 변경하세요. applicationId는 namespace/Kotlin 패키지 '
            '경로와 달라도 되므로 소스 경로를 함께 옮길 필요는 없습니다.',
        filePath: gradlePath,
      ),
    );
  }

  if (namespace != null) {
    final expectedRelativeDir = namespace.replaceAll('.', '/');
    final expectedDirPath = 'android/app/src/main/kotlin/$expectedRelativeDir';
    final expectedDir = Directory('${root.path}/$expectedDirPath');
    final mainActivityFile = File('${expectedDir.path}/MainActivity.kt');
    if (!mainActivityFile.existsSync()) {
      issues.add(
        ReleaseReadinessIssue(
          id: 'android_package_path_mismatch',
          category: 'android',
          message:
              'namespace($namespace)에 대응하는 Kotlin 소스 '
              '$expectedDirPath/MainActivity.kt 가 없습니다. Android에서 Kotlin/Java '
              '소스 패키지 경로는 applicationId가 아니라 namespace를 따라야 하므로, '
              'MainActivity.kt를 namespace와 일치하는 디렉터리로 옮기세요.',
          filePath: expectedDirPath,
        ),
      );
    } else {
      final declaredPackage = _firstMatch(
        mainActivityFile.readAsStringSync(),
        RegExp(r'^package\s+([\w.]+)', multiLine: true),
      );
      if (declaredPackage != namespace) {
        issues.add(
          ReleaseReadinessIssue(
            id: 'android_package_declaration_mismatch',
            category: 'android',
            message:
                '$expectedDirPath/MainActivity.kt 의 package 선언'
                '(${declaredPackage ?? '없음'})이 namespace($namespace)와 '
                '일치하지 않습니다. package 선언을 namespace와 정확히 같게 '
                '맞추세요.',
            filePath: '$expectedDirPath/MainActivity.kt',
          ),
        );
      }
    }
  }

  final releaseBlockMatch = RegExp(
    r'release\s*\{([^}]*)\}',
  ).firstMatch(content);
  final releaseBlock = releaseBlockMatch?.group(1) ?? '';
  if (RegExp(
    r'signingConfig\s*=\s*signingConfigs\.getByName\(\s*"debug"\s*\)',
  ).hasMatch(releaseBlock)) {
    issues.add(
      ReleaseReadinessIssue(
        id: 'android_release_signing_debug',
        category: 'android',
        message:
            'release 빌드 타입이 여전히 debug 서명 키를 사용합니다($gradlePath). '
            'Play 스토어에는 debug 키로 서명된 APK/AAB를 올릴 수 없습니다. '
            '별도 release keystore를 생성하고, 비밀번호/키 파일은 저장소에 '
            '커밋하지 말고 CI 시크릿이나 로컬 key.properties(.gitignore 처리)로 '
            '주입하도록 signingConfig를 구성하세요.',
        filePath: gradlePath,
      ),
    );
  } else {
    final usesReleaseSigningConfig = RegExp(
      r'signingConfig\s*=\s*signingConfigs\.(?:getByName|named)\(\s*"release"\s*\)',
    ).hasMatch(releaseBlock);
    if (!usesReleaseSigningConfig) {
      issues.add(
        ReleaseReadinessIssue(
          id: 'android_release_signing_not_wired',
          category: 'android',
          message:
              '$gradlePath 의 release 빌드 타입이 signingConfigs.release를 '
              '사용하도록 연결되어 있지 않습니다. buildTypes.release.signingConfig가 '
              'signingConfigs.getByName("release")를 가리키도록 구성하세요.',
          filePath: gradlePath,
        ),
      );
    } else {
      // Require *recognizable executable* wiring, not just the env var
      // names appearing anywhere (e.g. in a comment). Each name must show
      // up as an actual Kotlin string literal ("ANDROID_..."), and the
      // file must call System.getenv( somewhere -- together those two
      // signals are what a real System.getenv("ANDROID_...") (or a
      // data-driven equivalent, e.g. System.getenv(field.envVar) alongside
      // a literal "ANDROID_..." entry) leaves behind. Comments are
      // stripped first (both `//` line and `/* */` block comments), so a
      // comment -- even one that fakes a whole `System.getenv("ANDROID_...")`
      // line/block, not just the bare name -- can never satisfy this.
      final codeOnly = _stripKotlinComments(content);
      final hasGetenvCall = RegExp(r'System\.getenv\s*\(').hasMatch(codeOnly);
      final missingEnvNames = _releaseSigningEnvVars.values
          .where(
            (envVar) =>
                !RegExp('"${RegExp.escape(envVar)}"').hasMatch(codeOnly),
          )
          .toList();
      if (!hasGetenvCall || missingEnvNames.isNotEmpty) {
        final problems = [
          if (!hasGetenvCall) 'System.getenv(...) 호출을 찾지 못함',
          if (missingEnvNames.isNotEmpty)
            '문자열 리터럴로 등장하지 않는 환경변수: ${missingEnvNames.join(', ')}',
        ];
        issues.add(
          ReleaseReadinessIssue(
            id: 'android_release_signing_env_not_wired',
            category: 'android',
            message:
                '$gradlePath 가 CI 환경변수를 통한 서명 구성을 실제로 지원하는지 '
                '확인하지 못했습니다(${problems.join('; ')}). 환경변수 이름이 주석에만 '
                '있는 것으로는 충분하지 않습니다 -- System.getenv(...)로 실제로 읽어와야 '
                '합니다. 로컬 android/key.properties 뿐 아니라 CI 환경변수로도 서명 '
                '정보를 주입할 수 있도록 구성하세요.',
            filePath: gradlePath,
          ),
        );
      } else {
        issues.addAll(_checkAndroidSigningCredentials(root, environment));
      }
    }
  }

  return issues;
}

/// Unescapes a single Java `Properties`-file value, mirroring
/// `java.util.Properties.load()` (which android/app/build.gradle.kts uses
/// via `Properties().load(...)`): "\" is an escape character, so "\\"
/// becomes a single "\" and "\" followed by any other character is that
/// character literally (the backslash itself is dropped). This matters on
/// Windows, where a real key.properties must either use forward slashes
/// (`C:/keys/release.jks`) or escaped backslashes (`C:\\keys\\release.jks`)
/// for `storeFile` -- a single, unescaped backslash would silently lose
/// path separators under real Properties parsing. `\t`/`\n`/`\r`/`\f` are
/// also recognized, matching the Properties spec; `\uXXXX` unicode escapes
/// are intentionally not supported here (not needed for these fields).
String _unescapePropertiesValue(String raw) {
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final char = raw[i];
    if (char == '\\' && i + 1 < raw.length) {
      final next = raw[i + 1];
      switch (next) {
        case 't':
          buffer.write('\t');
          break;
        case 'n':
          buffer.write('\n');
          break;
        case 'r':
          buffer.write('\r');
          break;
        case 'f':
          buffer.write('\f');
          break;
        default:
          buffer.write(next);
      }
      i++;
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

/// Checks whether Android release signing credentials are *currently
/// usable*, applying the same precedence as android/app/build.gradle.kts:
/// a non-empty CI environment value overrides android/key.properties, which
/// in turn is only consulted when the environment value is absent/blank.
///
/// This never reads or serializes secret *values* -- only whether each
/// field/channel is present, and (for the keystore) whether the file it
/// names exists on disk.
List<ReleaseReadinessIssue> _checkAndroidSigningCredentials(
  Directory root,
  Map<String, String> environment,
) {
  final keyPropertiesFile = _file(root, 'android/key.properties');
  final localProperties = <String, String>{};
  if (keyPropertiesFile.existsSync()) {
    for (final line in keyPropertiesFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;
      localProperties[trimmed.substring(0, separator).trim()] =
          _unescapePropertiesValue(trimmed.substring(separator + 1).trim());
    }
  }

  String? resolve(String propertyKey) {
    final envVar = _releaseSigningEnvVars[propertyKey]!;
    final envValue = environment[envVar];
    if (envValue != null && envValue.trim().isNotEmpty) return envValue;
    final localValue = localProperties[propertyKey];
    if (localValue != null && localValue.trim().isNotEmpty) return localValue;
    return null;
  }

  final resolved = {
    for (final propertyKey in _releaseSigningEnvVars.keys)
      propertyKey: resolve(propertyKey),
  };

  final missing = _releaseSigningEnvVars.keys
      .where((propertyKey) => resolved[propertyKey] == null)
      .map(
        (propertyKey) =>
            "$propertyKey(android/key.properties의 '$propertyKey' 또는 "
            '환경변수 \$${_releaseSigningEnvVars[propertyKey]})',
      )
      .toList();

  if (missing.isNotEmpty) {
    return [
      ReleaseReadinessIssue(
        id: 'android_release_signing_credentials_missing',
        category: 'android',
        message:
            'Android 릴리즈 서명에 필요한 값이 아직 없습니다: ${missing.join(', ')}. '
            'android/key.properties.example를 복사해 android/key.properties를 '
            '채우거나(로컬 전용, 커밋 금지), CI에서는 위 환경변수로 주입하세요. '
            '실제 비밀 값은 이 리포트에 절대 포함되지 않습니다.',
        filePath: 'android/key.properties',
      ),
    ];
  }

  final storeFilePath = resolved['storeFile']!;
  final storeFile = File(storeFilePath);
  final keystoreFile = storeFile.isAbsolute
      ? storeFile
      : _file(root, 'android/$storeFilePath');
  if (!keystoreFile.existsSync()) {
    return [
      ReleaseReadinessIssue(
        id: 'android_release_signing_keystore_missing',
        category: 'android',
        message:
            'storeFile이 가리키는 keystore 파일을 찾을 수 없습니다. '
            "android/key.properties의 'storeFile' 값 또는 환경변수 "
            r'$ANDROID_KEYSTORE_PATH가 실제로 존재하는 keystore 파일을 '
            '가리키는지 확인하세요.',
        filePath: 'android/key.properties',
      ),
    ];
  }

  return [];
}

List<ReleaseReadinessIssue> _checkIosBundleId(Directory root) {
  const path = 'ios/Runner.xcodeproj/project.pbxproj';
  final file = _file(root, path);
  if (!file.existsSync()) {
    return [
      ReleaseReadinessIssue(
        id: 'ios_project_missing',
        category: 'ios',
        message: '$path 파일을 찾을 수 없습니다. iOS 프로젝트 구조를 확인하세요.',
        filePath: path,
      ),
    ];
  }
  final content = file.readAsStringSync();
  final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^\s;]+);')
      .allMatches(content)
      .map((m) => m.group(1)!)
      .where((id) => !id.contains('RunnerTests'))
      .toSet();

  if (ids.isEmpty) {
    return [
      ReleaseReadinessIssue(
        id: 'ios_bundle_id_missing',
        category: 'ios',
        message: '$path 에서 앱(Runner) PRODUCT_BUNDLE_IDENTIFIER를 찾지 못했습니다.',
        filePath: path,
      ),
    ];
  }

  if (ids.any((id) => id.startsWith(_placeholderDomain))) {
    return [
      ReleaseReadinessIssue(
        id: 'ios_bundle_id_placeholder',
        category: 'ios',
        message:
            'iOS PRODUCT_BUNDLE_IDENTIFIER가 아직 기본값(${ids.join(', ')})입니다. '
            'App Store Connect에 앱을 만들 때 영구히 고정되는 값이므로, $path 에서 '
            '실제 배포용 Bundle ID로 변경하고 Apple Developer 계정에 등록하세요.',
        filePath: path,
      ),
    ];
  }
  return [];
}

List<ReleaseReadinessIssue> _checkMacosBundleId(Directory root) {
  const path = 'macos/Runner/Configs/AppInfo.xcconfig';
  final file = _file(root, path);
  if (!file.existsSync()) {
    return [
      ReleaseReadinessIssue(
        id: 'macos_appinfo_missing',
        category: 'macos',
        message: '$path 파일을 찾을 수 없습니다. macOS 프로젝트 구조를 확인하세요.',
        filePath: path,
      ),
    ];
  }
  final content = file.readAsStringSync();
  final bundleId = _firstMatch(
    content,
    RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)'),
  );
  if (bundleId == null) {
    return [
      ReleaseReadinessIssue(
        id: 'macos_bundle_id_missing',
        category: 'macos',
        message: '$path 에서 PRODUCT_BUNDLE_IDENTIFIER를 찾지 못했습니다.',
        filePath: path,
      ),
    ];
  }
  if (bundleId.startsWith(_placeholderDomain)) {
    return [
      ReleaseReadinessIssue(
        id: 'macos_bundle_id_placeholder',
        category: 'macos',
        message:
            'macOS PRODUCT_BUNDLE_IDENTIFIER가 아직 기본값($bundleId)입니다. '
            '$path 에서 실제 배포용 Bundle ID로 변경하세요.',
        filePath: path,
      ),
    ];
  }
  return [];
}

List<ReleaseReadinessIssue> _checkLinuxApplicationId(Directory root) {
  const path = 'linux/CMakeLists.txt';
  final file = _file(root, path);
  if (!file.existsSync()) {
    return [
      ReleaseReadinessIssue(
        id: 'linux_cmake_missing',
        category: 'linux',
        message: '$path 파일을 찾을 수 없습니다. Linux 프로젝트 구조를 확인하세요.',
        filePath: path,
      ),
    ];
  }
  final content = file.readAsStringSync();
  final applicationId = _firstMatch(
    content,
    RegExp(r'set\(APPLICATION_ID\s+"([^"]+)"\)'),
  );
  if (applicationId == null) {
    return [
      ReleaseReadinessIssue(
        id: 'linux_application_id_missing',
        category: 'linux',
        message: '$path 에서 APPLICATION_ID를 찾지 못했습니다.',
        filePath: path,
      ),
    ];
  }
  if (applicationId.startsWith(_placeholderDomain)) {
    return [
      ReleaseReadinessIssue(
        id: 'linux_application_id_placeholder',
        category: 'linux',
        message:
            'Linux APPLICATION_ID가 아직 기본값($applicationId)입니다. '
            '$path 에서 실제 배포용 ID로 변경하세요.',
        filePath: path,
      ),
    ];
  }
  return [];
}

List<ReleaseReadinessIssue> _checkVersion(Directory root) {
  const path = 'pubspec.yaml';
  final file = _file(root, path);
  if (!file.existsSync()) {
    return [
      ReleaseReadinessIssue(
        id: 'pubspec_missing',
        category: 'version',
        message: '$path 파일을 찾을 수 없습니다.',
        filePath: path,
      ),
    ];
  }
  final content = file.readAsStringSync();
  final version = _firstMatch(
    content,
    RegExp(r'^version:\s*(\S+)', multiLine: true),
  );
  if (version == null) {
    return [
      ReleaseReadinessIssue(
        id: 'version_missing',
        category: 'version',
        message: '$path 에서 version 필드를 찾지 못했습니다.',
        filePath: path,
      ),
    ];
  }
  final match = _versionPattern.firstMatch(version);
  if (match == null) {
    if (RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$').hasMatch(version)) {
      return [
        ReleaseReadinessIssue(
          id: 'version_build_number_missing',
          category: 'version',
          message:
              '$path 의 version($version)에 빌드 번호(+N)가 없습니다. Android '
              'versionCode/iOS CFBundleVersion으로 쓰이는 빌드 번호가 필요하니 '
              '"$version+1"처럼 +빌드번호를 붙이세요.',
          filePath: path,
        ),
      ];
    }
    return [
      ReleaseReadinessIssue(
        id: 'version_invalid',
        category: 'version',
        message:
            '$path 의 version($version)이 올바른 형식이 아닙니다. '
            'MAJOR.MINOR.PATCH+빌드번호 형식(예: 1.0.0+1)을 따라야 합니다.',
        filePath: path,
      ),
    ];
  }

  final buildNumber = int.parse(match.group(1)!);
  if (buildNumber <= 0) {
    return [
      ReleaseReadinessIssue(
        id: 'version_build_number_nonpositive',
        category: 'version',
        message:
            '$path 의 version($version) 빌드 번호는 1 이상의 양의 정수여야 합니다. '
            'Android/iOS 스토어 모두 0 이하의 빌드 번호를 허용하지 않습니다.',
        filePath: path,
      ),
    ];
  }

  return [];
}

/// Non-secret drift check for `docs/privacy_policy.md`: flags the
/// still-a-draft title/banner and any remaining `[TODO: ...]` placeholder,
/// matching the manual gate `phase3_production_release_plan.md` 3.6절
/// describes (`rg -n '\[TODO|초안' docs/privacy_policy.md` must report 0
/// hits before release). This never inspects Sentry/account credentials --
/// only the checked-in Markdown text -- so it's safe to run in any CI job
/// without secrets.
List<ReleaseReadinessIssue> _checkPrivacyPolicy(Directory root) {
  const path = 'docs/privacy_policy.md';
  final file = _file(root, path);
  if (!file.existsSync()) {
    return [
      ReleaseReadinessIssue(
        id: 'privacy_policy_missing',
        category: 'privacy',
        message:
            '$path 파일을 찾을 수 없습니다. 앱의 "데이터 및 개인정보" 화면이 '
            '참조하는 문서가 없으면 실제 배포에서 링크가 깨집니다.',
        filePath: path,
      ),
    ];
  }

  final content = file.readAsStringSync();
  final todoCount = RegExp(r'\[TODO[:\]]').allMatches(content).length;
  final issues = <ReleaseReadinessIssue>[];
  if (todoCount > 0) {
    issues.add(
      ReleaseReadinessIssue(
        id: 'privacy_policy_todo_remaining',
        category: 'privacy',
        message:
            '$path 에 [TODO: ...] 표시가 $todoCount개 남아 있습니다. 운영자가 '
            '승인한 실제 값(문의처, 시행일, Sentry 운영 법인/region/보관기간 등)으로 '
            '모두 채워야 배포할 수 있습니다.',
        filePath: path,
      ),
    );
  }
  if (content.contains('(초안)') || content.contains('이 문서는 초안입니다')) {
    issues.add(
      ReleaseReadinessIssue(
        id: 'privacy_policy_draft_marker',
        category: 'privacy',
        message:
            '$path 제목/안내문에 "초안" 표시가 남아 있습니다. 운영자 승인 후 '
            '이 표시를 제거해야 배포할 수 있습니다.',
        filePath: path,
      ),
    );
  }
  return issues;
}
