import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/release_readiness/checker.dart';

/// release readiness 검사기는 실제 저장소 파일을 건드리지 않고, 매 테스트마다
/// 임시 디렉터리에 최소한의 플랫폼 프로젝트 파일 fixture를 만들어 검증한다.
/// 실제 저장소가 아직 placeholder를 갖고 있어도(의도적으로) 이 테스트들은
/// 항상 통과해야 하므로, 절대 프로젝트 루트(Directory.current)를 검사하지 않는다.
void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('release_readiness_test_');
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  void writeFile(String relativePath, String content) {
    final file = File('${tempRoot.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// A minimal but fully-wired release signingConfig block: references
  /// signingConfigs.release (never debug) and reads all four CI env vars
  /// via real System.getenv(...) calls with quoted literal names --
  /// checker.dart requires *executable-looking* wiring (not just the names
  /// appearing in a comment) to recognize this as wired, matching the
  /// contract checked against android/app/build.gradle.kts.
  const wiredGradleSigningBlock = '''
    signingConfigs {
        create("release") {
            val envKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
            val envStorePassword = System.getenv("ANDROID_STORE_PASSWORD")
            val envKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
            val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
''';

  void writeReadyFixture() {
    writeFile('android/app/build.gradle.kts', '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
$wiredGradleSigningBlock
}
''');
    writeFile(
      'android/app/src/main/kotlin/com/acme/human_status/MainActivity.kt',
      'package com.acme.human_status\nclass MainActivity\n',
    );
    writeFile('ios/Runner.xcodeproj/project.pbxproj', '''
PRODUCT_BUNDLE_IDENTIFIER = com.acme.humanStatus;
PRODUCT_BUNDLE_IDENTIFIER = com.acme.humanStatus.RunnerTests;
''');
    writeFile('macos/Runner/Configs/AppInfo.xcconfig', '''
PRODUCT_BUNDLE_IDENTIFIER = com.acme.humanStatus
''');
    writeFile('linux/CMakeLists.txt', '''
set(APPLICATION_ID "com.acme.human_status")
''');
    writeFile('pubspec.yaml', '''
name: human_status
version: 1.2.0+3
''');
    // Fake (non-secret) keystore + credentials so the shared "ready" fixture
    // also has usable release signing credentials -- tests that are only
    // about namespace/version/etc. shouldn't incidentally fail on the new
    // credentials-missing check.
    writeFile('android/key.properties', '''
storeFile=fake-release.jks
storePassword=test-only-store-password
keyAlias=test-only-alias
keyPassword=test-only-key-password
''');
    writeFile(
      'android/fake-release.jks',
      'not a real keystore, test fixture only',
    );
  }

  /// checkReleaseReadiness with an explicit empty environment by default, so
  /// these tests never accidentally read the *actual* host/CI environment.
  ReleaseReadinessReport check(
    Directory root, {
    Map<String, String> environment = const {},
  }) => checkReleaseReadiness(root, environment: environment);

  test('모든 ID/서명/버전이 정상이면 통과한다', () {
    writeReadyFixture();
    final report = check(tempRoot);
    expect(report.isReady, isTrue);
    expect(report.issues, isEmpty);
  });

  test('JSON 직렬화가 ready=true와 빈 issues를 담는다', () {
    writeReadyFixture();
    final report = check(tempRoot);
    final json = report.toJson();
    expect(json['ready'], isTrue);
    expect(json['issues'], isEmpty);
  });

  test('Android namespace/applicationId가 com.example이면 실패한다', () {
    writeReadyFixture();
    writeFile('android/app/build.gradle.kts', '''
android {
    namespace = "com.example.human_status"
    defaultConfig {
        applicationId = "com.example.human_status"
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
''');
    writeFile(
      'android/app/src/main/kotlin/com/example/human_status/MainActivity.kt',
      'package com.example.human_status\nclass MainActivity\n',
    );
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    final ids = report.issues.map((i) => i.id).toSet();
    expect(ids, contains('android_namespace_placeholder'));
    expect(ids, contains('android_application_id_placeholder'));
  });

  test('namespace와 applicationId가 달라도 소스가 namespace와 맞으면 통과한다', () {
    // applicationId is allowed to diverge from namespace/Kotlin package path;
    // only namespace determines where the Kotlin source must live.
    writeReadyFixture();
    writeFile('android/app/build.gradle.kts', '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status.paid"
    }
$wiredGradleSigningBlock
}
''');
    final report = check(tempRoot);
    expect(report.isReady, isTrue);
    expect(report.issues, isEmpty);
  });

  test('namespace에 대응하는 Kotlin 디렉터리가 없으면 실패한다', () {
    writeReadyFixture();
    // Keep namespace/applicationId real, but leave the Kotlin source under
    // a stale (placeholder) directory that doesn't match namespace.
    Directory(
      '${tempRoot.path}/android/app/src/main/kotlin/com/acme/human_status',
    ).deleteSync(recursive: true);
    writeFile(
      'android/app/src/main/kotlin/com/example/human_status/MainActivity.kt',
      'package com.example.human_status\nclass MainActivity\n',
    );
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('android_package_path_mismatch'),
    );
  });

  test('디렉터리는 namespace와 맞지만 package 선언이 다르면 실패한다', () {
    writeReadyFixture();
    // Right directory, but the file still declares the old package.
    writeFile(
      'android/app/src/main/kotlin/com/acme/human_status/MainActivity.kt',
      'package com.example.human_status\nclass MainActivity\n',
    );
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('android_package_declaration_mismatch'),
    );
  });

  test('release 빌드가 debug 서명 키를 쓰면 실패한다', () {
    writeReadyFixture();
    writeFile('android/app/build.gradle.kts', '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
''');
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('android_release_signing_debug'),
    );
  });

  test('iOS bundle id가 com.example이면 실패한다', () {
    writeReadyFixture();
    writeFile('ios/Runner.xcodeproj/project.pbxproj', '''
PRODUCT_BUNDLE_IDENTIFIER = com.example.humanStatus;
PRODUCT_BUNDLE_IDENTIFIER = com.example.humanStatus.RunnerTests;
''');
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('ios_bundle_id_placeholder'),
    );
  });

  test('macOS bundle id가 com.example이면 실패한다', () {
    writeReadyFixture();
    writeFile('macos/Runner/Configs/AppInfo.xcconfig', '''
PRODUCT_BUNDLE_IDENTIFIER = com.example.humanStatus
''');
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('macos_bundle_id_placeholder'),
    );
  });

  test('Linux APPLICATION_ID가 com.example이면 실패한다', () {
    writeReadyFixture();
    writeFile('linux/CMakeLists.txt', '''
set(APPLICATION_ID "com.example.human_status")
''');
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('linux_application_id_placeholder'),
    );
  });

  test('버전이 1.0.0+1이어도 정당한 첫 릴리즈이므로 통과한다', () {
    // 1.0.0+1 is exactly what `flutter create` scaffolds, but it is also a
    // perfectly legitimate first-release version -- it must not be flagged
    // just for matching the template default.
    writeReadyFixture();
    writeFile('pubspec.yaml', '''
name: human_status
version: 1.0.0+1
''');
    final report = check(tempRoot);
    expect(report.isReady, isTrue);
    expect(report.issues, isEmpty);
  });

  test('빌드 번호가 없는 버전은 실패한다', () {
    writeReadyFixture();
    writeFile('pubspec.yaml', '''
name: human_status
version: 1.2.0
''');
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('version_build_number_missing'),
    );
  });

  test('빌드 번호가 0이면 실패한다', () {
    writeReadyFixture();
    writeFile('pubspec.yaml', '''
name: human_status
version: 1.2.0+0
''');
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('version_build_number_nonpositive'),
    );
  });

  test('버전 형식 자체가 유효하지 않으면 실패한다', () {
    writeReadyFixture();
    writeFile('pubspec.yaml', '''
name: human_status
version: not-a-version
''');
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    expect(report.issues.map((i) => i.id), contains('version_invalid'));
  });

  test('프리릴리즈 태그가 있는 유효한 버전은 통과한다', () {
    writeReadyFixture();
    writeFile('pubspec.yaml', '''
name: human_status
version: 2.0.0-beta.1+7
''');
    final report = check(tempRoot);
    expect(report.isReady, isTrue);
    expect(report.issues, isEmpty);
  });

  test('필수 플랫폼 파일이 없으면 누락 이슈를 보고한다', () {
    // Completely empty fixture directory: every check should degrade to a
    // "file missing" issue instead of throwing.
    expect(() => check(tempRoot), returnsNormally);
    final report = check(tempRoot);
    expect(report.isReady, isFalse);
    final ids = report.issues.map((i) => i.id).toSet();
    expect(ids, contains('android_build_gradle_missing'));
    expect(ids, contains('ios_project_missing'));
    expect(ids, contains('macos_appinfo_missing'));
    expect(ids, contains('linux_cmake_missing'));
    expect(ids, contains('pubspec_missing'));
  });
}
