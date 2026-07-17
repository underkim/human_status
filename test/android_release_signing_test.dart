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

  // Executable-looking wiring (quoted env-var literals + a real
  // System.getenv(...) call) -- this is what checker.dart now requires to
  // recognize CI wiring as real, as opposed to the names merely being
  // mentioned in a comment (see commentOnlyEnvWiringGradle below).
  const wiredGradle = '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
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
}
''';

  // Same signingConfigs.release wiring, but the four env var names only
  // ever appear inside a comment -- no System.getenv(...) call anywhere.
  // A real Gradle script would never pick these up; the checker must not
  // be fooled into treating this as wired.
  const commentOnlyEnvWiringGradle = '''
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

  // Adversarial counterexample: the exact wiring code from wiredGradle
  // above, but every line is `//`-commented out. Before checker.dart
  // stripped comments, this fooled it: the text `System.getenv(` and every
  // quoted "ANDROID_..." literal were present verbatim, just inside `//`
  // comments that no Kotlin compiler would ever execute.
  const lineCommentFakeWiringGradle = '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
    signingConfigs {
        create("release") {
            // val envKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
            // val envStorePassword = System.getenv("ANDROID_STORE_PASSWORD")
            // val envKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
            // val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
''';

  // Same adversarial counterexample, but using a `/* ... */` block comment
  // instead of `//` line comments.
  const blockCommentFakeWiringGradle = '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
    signingConfigs {
        create("release") {
            /*
            val envKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
            val envStorePassword = System.getenv("ANDROID_STORE_PASSWORD")
            val envKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
            val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            */
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

    test('storeFile이 Java Properties 이스케이프 형식의 절대 경로면 동작한다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      final absoluteKeystore = File('${tempRoot.path}/outside/release.jks');
      absoluteKeystore.parent.createSync(recursive: true);
      absoluteKeystore.writeAsStringSync('not a real keystore');
      // android/key.properties is parsed as a Java Properties file, which
      // treats "\" as an escape character -- a real file must double any
      // backslash (as done here) to survive parsing intact. This mirrors
      // java.util.Properties.load() in android/app/build.gradle.kts.
      final escapedPath = absoluteKeystore.path.replaceAll(r'\', r'\\');
      writeFile('android/key.properties', '''
storeFile=$escapedPath
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

    test('이스케이프하지 않은 단일 백슬래시 경로는 Properties 의미론상 깨진다', () {
      writeFile('android/app/build.gradle.kts', wiredGradle);
      writeNonAndroidFixtures();
      // This documents/tests the supported form: real java.util.Properties
      // parsing drops an unescaped backslash and keeps the following
      // character literally, so "C:\keys\release.jks" becomes
      // "C:keysrelease.jks" -- a path that does not exist. This is exactly
      // why docs/RELEASE_CHECKLIST.md and android/key.properties.example
      // tell users to use forward slashes or doubled backslashes for
      // storeFile inside this file specifically (unlike the
      // ANDROID_KEYSTORE_PATH env var, which is not Properties-parsed).
      writeFile('android/key.properties', r'''
storeFile=C:\keys\release.jks
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

  group('CI 환경변수 배관은 주석만으로는 인정되지 않는다', () {
    test('환경변수 이름이 주석에만 있으면 env_not_wired 이슈를 보고한다', () {
      writeFile('android/app/build.gradle.kts', commentOnlyEnvWiringGradle);
      writeNonAndroidFixtures();

      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        contains('android_release_signing_env_not_wired'),
      );
      // A comment-only file has no usable wiring, so credential resolution
      // must never even be attempted/reported as the (wrong) problem.
      expect(
        androidIssueIds(report),
        isNot(contains('android_release_signing_credentials_missing')),
      );
    });

    test('`//` 줄 주석 안에 완전한 System.getenv(...) 코드를 흉내내도 통과하지 않는다', () {
      // Exact counterexample: every line of real wiring code, `//`-commented
      // out. Both "System.getenv(" and every quoted "ANDROID_..." literal
      // are present verbatim in the raw file text -- if checker.dart didn't
      // strip comments first, this would have been (and previously was)
      // mistaken for real wiring.
      writeFile('android/app/build.gradle.kts', lineCommentFakeWiringGradle);
      writeNonAndroidFixtures();

      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        contains('android_release_signing_env_not_wired'),
      );
    });

    test('`/* */` 블록 주석 안에 완전한 System.getenv(...) 코드를 흉내내도 통과하지 않는다', () {
      writeFile('android/app/build.gradle.kts', blockCommentFakeWiringGradle);
      writeNonAndroidFixtures();

      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        contains('android_release_signing_env_not_wired'),
      );
    });

    test('주석을 제거한 실제 코드에는 여전히 정상적으로 배관을 인식한다 (code-only recognition)', () {
      // Positive control for the two counterexamples above: the exact same
      // wiring, without being commented out, must still be recognized.
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
        isNot(contains('android_release_signing_env_not_wired')),
      );
    });

    test('문자열 리터럴에 담긴 "//"가 같은 줄의 실제 코드를 가리지 않는다', () {
      // Comment-stripping must be string-literal-aware: naive regex
      // stripping would treat a "//" inside a string as a line-comment
      // start and wrongly discard the real wiring code after it.
      writeFile('android/app/build.gradle.kts', '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
    signingConfigs {
        create("release") {
            val docs = "see https://example.com/notes" ; val a = System.getenv("ANDROID_KEYSTORE_PATH")
            val b = System.getenv("ANDROID_STORE_PASSWORD")
            val c = System.getenv("ANDROID_KEY_ALIAS")
            val d = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
''');
      writeNonAndroidFixtures();

      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        isNot(contains('android_release_signing_env_not_wired')),
      );
    });

    test('문자열 리터럴에 담긴 "/*"가 뒤따르는 실제 코드를 가리지 않는다', () {
      // Same string-awareness requirement for block comments: a "/*"
      // inside a string must not be mistaken for a block-comment start,
      // which would otherwise swallow the real wiring lines that follow.
      writeFile('android/app/build.gradle.kts', '''
android {
    namespace = "com.acme.human_status"
    defaultConfig {
        applicationId = "com.acme.human_status"
    }
    signingConfigs {
        create("release") {
            val docs = "style: /* looks like a comment start */ but is text"
            val a = System.getenv("ANDROID_KEYSTORE_PATH")
            val b = System.getenv("ANDROID_STORE_PASSWORD")
            val c = System.getenv("ANDROID_KEY_ALIAS")
            val d = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
''');
      writeNonAndroidFixtures();

      final report = checkReleaseReadiness(tempRoot, environment: const {});
      expect(
        androidIssueIds(report),
        isNot(contains('android_release_signing_env_not_wired')),
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
    test('두 가드 모두 "release"가 포함된 태스크에만 적용된다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      // Guard #1 (fast-fail): gated on isReleaseTaskRequested.
      expect(gradle, contains('if (isReleaseTaskRequested)'));
      // Guard #2 (authoritative): gated on the resolved task's own name,
      // not just what was requested on the command line.
      final configureEachIndex = gradle.indexOf('tasks.configureEach');
      expect(configureEachIndex, greaterThan(-1));
      expect(
        gradle.substring(configureEachIndex),
        contains('name.contains("release", ignoreCase = true)'),
      );
      // Neither guard's fail path runs unconditionally: this is the whole
      // point -- assembleDebug/test/analyze never hit it.
      expect(gradle, isNot(contains('\nthrow GradleException')));
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

    test('throw는 하나의 공용 실패 함수 안에서만 일어난다', () {
      // Both guards call the same failIfReleaseSigningIncomplete() function
      // instead of duplicating the throw, so they can never drift out of
      // sync (e.g. one guard leaking a secret the other doesn't).
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final throwCount = 'throw GradleException'.allMatches(gradle).length;
      expect(throwCount, 1);
    });

    test('가드 #2: 실제 태스크 그래프(tasks.configureEach + doFirst) 기반 가드가 존재한다', () {
      // startParameter alone (guard #1) can be bypassed by Gradle's
      // camelCase task-name abbreviation on the CLI, or by some other,
      // differently-named task that transitively depends on a
      // release-signed task. This proves a SECOND, authoritative guard
      // exists that checks the actual resolved task graph right before
      // execution -- not merely gradle.startParameter.taskNames.
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final configureEachIndex = gradle.indexOf('tasks.configureEach');
      expect(configureEachIndex, greaterThan(-1));
      final block = gradle.substring(configureEachIndex);
      expect(block, contains('doFirst'));
      expect(block, contains('name.contains("release"'));
      expect(block, contains('failIfReleaseSigningIncomplete()'));
    });

    test('오류 메시지 코드에 실제 비밀 값을 문자열 보간하지 않는다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final fnStart = gradle.indexOf('fun failIfReleaseSigningIncomplete()');
      expect(fnStart, greaterThan(-1));
      final fnEnd = gradle.indexOf('\n}', fnStart);
      final fnBody = gradle.substring(
        fnStart,
        fnEnd == -1 ? gradle.length : fnEnd,
      );
      expect(fnBody, contains('throw GradleException'));
      // The message may reference *field names* and env *var names*, but
      // must never interpolate the resolved secret values themselves.
      expect(fnBody, isNot(contains(r'${releaseSigningValue(')));
      expect(fnBody, isNot(contains(r'${releaseStorePassword')));
      expect(fnBody, isNot(contains(r'${releaseKeyPassword')));
    });
  });
}
