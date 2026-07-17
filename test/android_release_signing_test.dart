import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/release_readiness/checker.dart';

/// Focused regression tests for Android release signing wiring:
/// - `tool/release_readiness/checker.dart`'s signing-credential detection
///   (dynamic: runs real Dart code against fixture directories + an
///   injectable environment map).
/// - Static "contract" checks over the real
///   `android/app/build.gradle.kts` and `android/key.properties.example`,
///   since no Android SDK is available in this environment to actually run
///   Gradle (`ANDROID_HOME` is unset) -- see docs/RELEASE_CHECKLIST.md.
void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync(
      'android_release_signing_test_',
    );
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  void writeFile(String relativePath, String content) {
    final file = File('${tempRoot.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  const wiredGradle = '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
    signingConfigs {
        create("release") {
            // ANDROID_KEYSTORE_PATH ANDROID_STORE_PASSWORD
            // ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
''';

  const debugSigningGradle = '''
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
''';

  /// Minimal platform fixture set (everything checkReleaseReadiness needs
  /// besides android/app/build.gradle.kts) so these tests only vary the
  /// signing-related inputs.
  void writeNonAndroidFixtures() {
    writeFile(
      'android/app/src/main/kotlin/com/acme/human_status/MainActivity.kt',
      'package com.acme.human_status\nclass MainActivity\n',
    );
    writeFile('ios/Runner.xcodeproj/project.pbxproj', '''
PRODUCT_BUNDLE_IDENTIFIER = com.acme.humanStatus;
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

  Set<String> androidIssueIds(ReleaseReadinessReport report) => report.issues
      .where((i) => i.category == 'android')
      .map((i) => i.id)
      .toSet();

  group('디버그 서명 금지', () {
    test('release 빌드가 여전히 debug 서명 키를 쓰면 실패한다', () {
      writeFile('android/app/build.gradle.kts', debugSigningGradle);
      writeNonAndroidFixtures();
      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        contains('android_release_signing_debug'),
      );
      expect(
        androidIssueIds(report),
        isNot(contains('android_release_signing_credentials_missing')),
      );
    });
  });

  group('로컬 key.properties happy path', () {
    test('가짜 keystore와 완전한 key.properties면 서명 이슈가 없다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      writeFile('android/key.properties', '''
storeFile=fake-release.jks
storePassword=local-store-password
keyAlias=local-alias
keyPassword=local-key-password
''');
      writeFile('android/fake-release.jks', 'not a real keystore');

      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        isNot(
          contains(
            anyOf([
              'android_release_signing_debug',
              'android_release_signing_not_wired',
              'android_release_signing_env_not_wired',
              'android_release_signing_credentials_missing',
              'android_release_signing_keystore_missing',
            ]),
          ),
        ),
      );
    });

    test('storeFile이 절대 경로여도 동작한다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      final absoluteKeystore = File('${tempRoot.path}/outside/release.jks');
      absoluteKeystore.parent.createSync(recursive: true);
      absoluteKeystore.writeAsStringSync('not a real keystore');
      writeFile('android/key.properties', '''
storeFile=${absoluteKeystore.path}
storePassword=local-store-password
keyAlias=local-alias
keyPassword=local-key-password
''');

      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        isNot(contains('android_release_signing_keystore_missing')),
      );
    });
  });

  group('CI 환경변수 happy path', () {
    test('key.properties 없이 4개 환경변수만으로 통과한다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      final keystore = File('${tempRoot.path}/android/ci-release.jks');
      keystore.writeAsStringSync('not a real keystore');

      final report = checkReleaseReadiness(
        tempRoot,
        environment: {
          'ANDROID_KEYSTORE_PATH': 'ci-release.jks',
          'ANDROID_STORE_PASSWORD': 'ci-store-password',
          'ANDROID_KEY_ALIAS': 'ci-alias',
          'ANDROID_KEY_PASSWORD': 'ci-key-password',
        },
      );
      expect(
        androidIssueIds(report),
        isNot(
          contains(
            anyOf([
              'android_release_signing_credentials_missing',
              'android_release_signing_keystore_missing',
            ]),
          ),
        ),
      );
    });
  });

  group('env가 local key.properties보다 우선한다', () {
    test('둘 다 있으면 환경변수 쪽 keystore 경로를 사용한다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      // Local file points at a keystore that does NOT exist.
      writeFile('android/key.properties', '''
storeFile=missing-local.jks
storePassword=local-store-password
keyAlias=local-alias
keyPassword=local-key-password
''');
      // The env-provided keystore DOES exist.
      final envKeystore = File('${tempRoot.path}/android/ci-release.jks');
      envKeystore.writeAsStringSync('not a real keystore');

      final report = checkReleaseReadiness(
        tempRoot,
        environment: {
          'ANDROID_KEYSTORE_PATH': 'ci-release.jks',
          'ANDROID_STORE_PASSWORD': 'ci-store-password',
          'ANDROID_KEY_ALIAS': 'ci-alias',
          'ANDROID_KEY_PASSWORD': 'ci-key-password',
        },
      );
      // If local had won, ci-release.jks wouldn't matter and
      // missing-local.jks (nonexistent) would be flagged. Passing proves env
      // took precedence.
      expect(
        androidIssueIds(report),
        isNot(contains('android_release_signing_keystore_missing')),
      );
    });

    test('환경변수가 빈 문자열이면 local 값으로 fall back한다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      writeFile('android/key.properties', '''
storeFile=fake-release.jks
storePassword=local-store-password
keyAlias=local-alias
keyPassword=local-key-password
''');
      writeFile('android/fake-release.jks', 'not a real keystore');

      final report = checkReleaseReadiness(
        tempRoot,
        environment: const {
          'ANDROID_KEYSTORE_PATH': '',
          'ANDROID_STORE_PASSWORD': '   ',
        },
      );
      expect(
        androidIssueIds(report),
        isNot(
          contains(
            anyOf([
              'android_release_signing_credentials_missing',
              'android_release_signing_keystore_missing',
            ]),
          ),
        ),
      );
    });
  });

  group('필드 누락', () {
    for (final missingField in [
      'storeFile',
      'storePassword',
      'keyAlias',
      'keyPassword',
    ]) {
      test('$missingField 가 없으면 credentials_missing 이슈를 보고한다', () {
        writeFile('android/app/build.gradle.kts', wiredGradle);
        writeNonAndroidFixtures();
        writeFile('android/fake-release.jks', 'not a real keystore');
        final fields = <String, String>{
          'storeFile': 'fake-release.jks',
          'storePassword': 'local-store-password',
          'keyAlias': 'local-alias',
          'keyPassword': 'local-key-password',
        }..remove(missingField);
        writeFile(
          'android/key.properties',
          fields.entries.map((e) => '${e.key}=${e.value}').join('\n'),
        );

        final report = checkReleaseReadiness(tempRoot, environment: const {});
        expect(
          androidIssueIds(report),
          contains('android_release_signing_credentials_missing'),
        );
      });
    }
  });

  group('keystore 파일 누락', () {
    test('네 필드가 모두 있어도 storeFile이 가리키는 파일이 없으면 실패한다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      writeFile('android/key.properties', '''
storeFile=does-not-exist.jks
storePassword=local-store-password
keyAlias=local-alias
keyPassword=local-key-password
''');

      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        contains('android_release_signing_keystore_missing'),
      );
    });
  });

  group('비밀 값이 리포트에 노출되지 않는다', () {
    test('human/JSON 출력 어디에도 실제 비밀번호 문자열이 없다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      const secretStorePassword = 'sUp3r-Secret-Store-Pw-9f8e7d';
      const secretKeyPassword = 'sUp3r-Secret-Key-Pw-1a2b3c';
      writeFile('android/key.properties', '''
storeFile=fake-release.jks
storePassword=$secretStorePassword
keyAlias=local-alias
keyPassword=$secretKeyPassword
''');
      // Deliberately do NOT create fake-release.jks, and also exercise the
      // env path with its own secret value, so both code paths are covered.
      const secretEnvPassword = 'eNv-Secret-9z8y7x-DoNotLeak';

      final report = checkReleaseReadiness(
        tempRoot,
        environment: {'ANDROID_KEY_PASSWORD': secretEnvPassword},
      );

      final humanText = report.issues.map((i) => i.message).join('\n');
      final jsonText = const JsonEncoder.withIndent(
        '  ',
      ).convert(report.toJson());

      for (final secret in [
        secretStorePassword,
        secretKeyPassword,
        secretEnvPassword,
      ]) {
        expect(humanText.contains(secret), isFalse);
        expect(jsonText.contains(secret), isFalse);
      }
    });
  });

  group('android/key.properties.example', () {
    test('placeholder만 포함하고 그럴듯한 실제 비밀은 없다', () {
      final example = File('android/key.properties.example');
      expect(example.existsSync(), isTrue);
      final content = example.readAsStringSync();

      for (final key in [
        'storeFile',
        'storePassword',
        'keyAlias',
        'keyPassword',
      ]) {
        expect(content.contains('$key='), isTrue, reason: '$key 항목이 있어야 함');
      }

      // Every non-comment `key=value` line's value must be an obvious
      // placeholder, not something that looks like a real secret.
      for (final rawLine in content.split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final separator = line.indexOf('=');
        if (separator <= 0) continue;
        final value = line.substring(separator + 1).trim();
        expect(
          value.startsWith('REPLACE_WITH_'),
          isTrue,
          reason: 'placeholder가 아닌 값처럼 보임: $value',
        );
      }
    });
  });

  group('debug 계열 태스크는 자격 증명 없이도 구성 가능해야 한다', () {
    test('build.gradle.kts의 fail-early guard는 "release"가 포함된 태스크에만 적용된다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      // Static contract check (no Android SDK available to run Gradle
      // itself here): the GradleException throw must be gated behind a
      // task-name check containing "release", not unconditional.
      final guardIndex = gradle.indexOf('isReleaseTaskRequested');
      expect(guardIndex, greaterThan(-1));
      final ifIndex = gradle.indexOf('if (isReleaseTaskRequested', guardIndex);
      expect(
        ifIndex,
        greaterThan(-1),
        reason: 'throw는 isReleaseTaskRequested 조건 안에서만 일어나야 함',
      );
      final throwIndex = gradle.indexOf('throw GradleException', ifIndex);
      expect(throwIndex, greaterThan(-1));
      // No unconditional throw/error appears before the android {} block
      // configures (which debug/test/analyze tasks also need to reach).
      final androidBlockIndex = gradle.indexOf('\nandroid {');
      expect(androidBlockIndex, greaterThan(throwIndex));
    });

    test('taskNames는 "release"를 포함하는지 대소문자 구분 없이 검사한다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('ignoreCase = true'));
      expect(gradle, contains('gradle.startParameter.taskNames'));
    });
  });

  group('release 태스크 fail-closed guard', () {
    test('signingConfigs.release는 항상 존재하고 debug로 대체되지 않는다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('signingConfigs.getByName("release")'));
      expect(
        gradle,
        isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
      );
    });

    test('네 개의 CI 환경변수 이름이 모두 등장한다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      for (final envVar in [
        'ANDROID_KEYSTORE_PATH',
        'ANDROID_STORE_PASSWORD',
        'ANDROID_KEY_ALIAS',
        'ANDROID_KEY_PASSWORD',
      ]) {
        expect(gradle, contains(envVar));
      }
    });

    test('오류 메시지 코드에 실제 비밀 값을 문자열 보간하지 않는다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final throwStart = gradle.indexOf('throw GradleException(');
      expect(throwStart, greaterThan(-1));
      final throwEnd = gradle.indexOf(')\n}', throwStart);
      final throwBody = gradle.substring(
        throwStart,
        throwEnd == -1 ? gradle.length : throwEnd,
      );
      // The message may reference *field names* and env *var names*, but
      // must never interpolate the resolved secret values themselves.
      expect(throwBody, isNot(contains('releaseSigningValue(')));
      expect(throwBody, isNot(contains(r'${releaseStorePassword')));
      expect(throwBody, isNot(contains(r'${releaseKeyPassword')));
    });
  });
}
