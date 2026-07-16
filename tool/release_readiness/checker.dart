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
const _placeholderVersion = '1.0.0+1';

String? _firstMatch(String content, RegExp pattern) {
  final match = pattern.firstMatch(content);
  if (match == null || match.groupCount < 1) return null;
  return match.group(1);
}

/// Runs every release-readiness check against [root] (the repository root)
/// and returns the combined report. Never throws for expected "file
/// missing"/"pattern not found" situations -- those become issues instead,
/// so a partially-set-up checkout still produces actionable output.
ReleaseReadinessReport checkReleaseReadiness(Directory root) {
  final issues = <ReleaseReadinessIssue>[
    ..._checkAndroid(root),
    ..._checkIosBundleId(root),
    ..._checkMacosBundleId(root),
    ..._checkLinuxApplicationId(root),
    ..._checkVersion(root),
  ];
  return ReleaseReadinessReport(issues);
}

File _file(Directory root, String relativePath) =>
    File('${root.path}/$relativePath');

List<ReleaseReadinessIssue> _checkAndroid(Directory root) {
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
            '실제 배포용 ID로 변경한 뒤 android/app/src/main/kotlin 아래 패키지 '
            '경로도 함께 옮겨야 합니다.',
        filePath: gradlePath,
      ),
    );
  }

  if (applicationId != null) {
    final expectedRelativeDir = applicationId.replaceAll('.', '/');
    final expectedDir = Directory(
      '${root.path}/android/app/src/main/kotlin/$expectedRelativeDir',
    );
    if (!expectedDir.existsSync()) {
      issues.add(
        ReleaseReadinessIssue(
          id: 'android_package_path_mismatch',
          category: 'android',
          message:
              'applicationId($applicationId)에 대응하는 Kotlin 패키지 경로 '
              'android/app/src/main/kotlin/$expectedRelativeDir 가 없습니다. '
              'MainActivity.kt의 실제 위치/패키지 선언과 applicationId가 '
              '일치하는지 확인하세요.',
          filePath: 'android/app/src/main/kotlin',
        ),
      );
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
  }

  return issues;
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
  if (version == _placeholderVersion) {
    return [
      ReleaseReadinessIssue(
        id: 'version_placeholder',
        category: 'version',
        message:
            '버전이 아직 flutter create 기본값($_placeholderVersion)입니다. '
            '$path 의 version을 실제 배포할 버전/빌드 번호로 올리세요 '
            '(예: 1.0.0+1 -> 1.0.0+2, 스토어에 다시 올릴 때마다 빌드 번호를 증가시켜야 합니다).',
        filePath: path,
      ),
    ];
  }
  return [];
}
