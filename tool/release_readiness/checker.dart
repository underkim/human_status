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
      final missingEnvNames = _releaseSigningEnvVars.values
          .where((envVar) => !content.contains(envVar))
          .toList();
      if (missingEnvNames.isNotEmpty) {
        issues.add(
          ReleaseReadinessIssue(
            id: 'android_release_signing_env_not_wired',
            category: 'android',
            message:
                '$gradlePath 가 CI 환경변수(${missingEnvNames.join(', ')})를 통한 '
                '서명 구성을 지원하지 않는 것으로 보입니다. 로컬 '
                'android/key.properties 뿐 아니라 CI 환경변수로도 서명 정보를 '
                '주입할 수 있도록 구성하세요.',
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
      localProperties[trimmed.substring(0, separator).trim()] = trimmed
          .substring(separator + 1)
          .trim();
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
