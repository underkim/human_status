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

  void writeReadyFixture() {
    writeFile('android/app/build.gradle.kts', '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
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
  }

  test('모든 ID/서명/버전이 정상이면 통과한다', () {
    writeReadyFixture();
    final report = checkReleaseReadiness(tempRoot);
    expect(report.isReady, isTrue);
    expect(report.issues, isEmpty);
  });

  test('JSON 직렬화가 ready=true와 빈 issues를 담는다', () {
    writeReadyFixture();
    final report = checkReleaseReadiness(tempRoot);
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
    final report = checkReleaseReadiness(tempRoot);
    expect(report.isReady, isFalse);
    final ids = report.issues.map((i) => i.id).toSet();
    expect(ids, contains('android_namespace_placeholder'));
    expect(ids, contains('android_application_id_placeholder'));
  });

  test('applicationId와 Kotlin 패키지 경로가 어긋나면 실패한다', () {
    writeReadyFixture();
    // Keep applicationId real, but leave the Kotlin source under the old path.
    writeFile('android/app/build.gradle.kts', '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
''');
    Directory(
      '${tempRoot.path}/android/app/src/main/kotlin/com/acme/human_status',
    ).deleteSync(recursive: true);
    writeFile(
      'android/app/src/main/kotlin/com/example/human_status/MainActivity.kt',
      'package com.example.human_status\nclass MainActivity\n',
    );
    final report = checkReleaseReadiness(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('android_package_path_mismatch'),
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
    final report = checkReleaseReadiness(tempRoot);
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
    final report = checkReleaseReadiness(tempRoot);
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
    final report = checkReleaseReadiness(tempRoot);
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
    final report = checkReleaseReadiness(tempRoot);
    expect(report.isReady, isFalse);
    expect(
      report.issues.map((i) => i.id),
      contains('linux_application_id_placeholder'),
    );
  });

  test('버전이 flutter create 기본값(1.0.0+1)이면 실패한다', () {
    writeReadyFixture();
    writeFile('pubspec.yaml', '''
name: human_status
version: 1.0.0+1
''');
    final report = checkReleaseReadiness(tempRoot);
    expect(report.isReady, isFalse);
    expect(report.issues.map((i) => i.id), contains('version_placeholder'));
  });

  test('필수 플랫폼 파일이 없으면 누락 이슈를 보고한다', () {
    // Completely empty fixture directory: every check should degrade to a
    // "file missing" issue instead of throwing.
    expect(() => checkReleaseReadiness(tempRoot), returnsNormally);
    final report = checkReleaseReadiness(tempRoot);
    expect(report.isReady, isFalse);
    final ids = report.issues.map((i) => i.id).toSet();
    expect(ids, contains('android_build_gradle_missing'));
    expect(ids, contains('ios_project_missing'));
    expect(ids, contains('macos_appinfo_missing'));
    expect(ids, contains('linux_cmake_missing'));
    expect(ids, contains('pubspec_missing'));
  });
}
