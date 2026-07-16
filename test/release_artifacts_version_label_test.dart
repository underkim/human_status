import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `.github/workflows/release-artifacts.yml` derives the release archive's
/// version label by calling tool/ci/sanitize_version_label.{sh,ps1} with the
/// tag name / manual input available only as environment variables (never
/// spliced into the step's script body). These tests run the *actual*
/// scripts the workflow runs against pathological-but-permitted inputs
/// (empty, all-dots, over-length) to prove the shared sanitization rule
/// holds on both shells, instead of re-implementing the logic in Dart and
/// risking drift from what CI really executes.
String _runBashScript(Map<String, String> env) {
  final result = Process.runSync(
    'bash',
    ['tool/ci/sanitize_version_label.sh'],
    environment: env,
    includeParentEnvironment: true,
  );
  expect(
    result.exitCode,
    0,
    reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
  );
  return (result.stdout as String).trim();
}

String? _findPwshExecutable() {
  for (final candidate in ['pwsh', 'powershell']) {
    try {
      final probe = Process.runSync(candidate, [
        '-NoProfile',
        '-Command',
        'exit 0',
      ]);
      if (probe.exitCode == 0) return candidate;
    } on ProcessException {
      // Not installed on this machine -- try the next candidate.
    }
  }
  return null;
}

String _runPwshScript(String executable, Map<String, String> env) {
  final result = Process.runSync(
    executable,
    [
      '-NoProfile',
      '-NonInteractive',
      '-File',
      'tool/ci/sanitize_version_label.ps1',
    ],
    environment: env,
    includeParentEnvironment: true,
  );
  expect(
    result.exitCode,
    0,
    reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
  );
  return (result.stdout as String).trim();
}

void main() {
  group('sanitize_version_label.sh (bash)', () {
    test('입력이 모두 비어 있으면 dev로 대체된다', () {
      expect(
        _runBashScript({'INPUT_VERSION_LABEL': '', 'REF_NAME': ''}),
        'dev',
      );
    });

    test('안전한 태그 이름은 그대로 유지된다', () {
      expect(
        _runBashScript({'INPUT_VERSION_LABEL': 'v1.2.3', 'REF_NAME': ''}),
        'v1.2.3',
      );
    });

    test('슬래시/세미콜론/공백 등 위험 문자는 대시로 치환된다', () {
      final result = _runBashScript({
        'INPUT_VERSION_LABEL': 'refs/heads/feature;rm -rf',
        'REF_NAME': '',
      });
      expect(result, isNot(contains('/')));
      expect(result, isNot(contains(';')));
      expect(result, isNot(contains(' ')));
    });

    test('점(.)으로만 이루어진 입력은 dev로 대체된다', () {
      expect(
        _runBashScript({'INPUT_VERSION_LABEL': '.' * 20, 'REF_NAME': ''}),
        'dev',
      );
    });

    test('64자를 넘는 입력은 64자로 잘린다', () {
      final result = _runBashScript({
        'INPUT_VERSION_LABEL': 'a' * 80,
        'REF_NAME': '',
      });
      expect(result.length, lessThanOrEqualTo(64));
      expect(result, 'a' * 64);
    });

    test('잘린 뒤 끝에 점이 남는 입력도 정리된다', () {
      final raw = '${'a' * 63}${'.' * 20}';
      final result = _runBashScript({
        'INPUT_VERSION_LABEL': raw,
        'REF_NAME': '',
      });
      expect(result.length, lessThanOrEqualTo(64));
      expect(result.endsWith('.'), isFalse);
    });
  });

  final pwshExecutable = _findPwshExecutable();
  group(
    'sanitize_version_label.ps1 (PowerShell)',
    () {
      test('입력이 모두 비어 있으면 dev로 대체된다', () {
        expect(
          _runPwshScript(pwshExecutable!, {
            'INPUT_VERSION_LABEL': '',
            'REF_NAME': '',
          }),
          'dev',
        );
      });

      test('안전한 태그 이름은 그대로 유지된다', () {
        expect(
          _runPwshScript(pwshExecutable!, {
            'INPUT_VERSION_LABEL': 'v1.2.3',
            'REF_NAME': '',
          }),
          'v1.2.3',
        );
      });

      test('슬래시/세미콜론/공백 등 위험 문자는 대시로 치환된다', () {
        final result = _runPwshScript(pwshExecutable!, {
          'INPUT_VERSION_LABEL': 'refs/heads/feature;rm -rf',
          'REF_NAME': '',
        });
        expect(result, isNot(contains('/')));
        expect(result, isNot(contains(';')));
        expect(result, isNot(contains(' ')));
      });

      test('점(.)으로만 이루어진 입력은 dev로 대체된다', () {
        expect(
          _runPwshScript(pwshExecutable!, {
            'INPUT_VERSION_LABEL': '.' * 20,
            'REF_NAME': '',
          }),
          'dev',
        );
      });

      test('64자를 넘는 입력은 64자로 잘린다', () {
        final result = _runPwshScript(pwshExecutable!, {
          'INPUT_VERSION_LABEL': 'a' * 80,
          'REF_NAME': '',
        });
        expect(result.length, lessThanOrEqualTo(64));
        expect(result, 'a' * 64);
      });

      test('잘린 뒤 끝에 점이 남는 입력도 정리된다', () {
        final raw = '${'a' * 63}${'.' * 20}';
        final result = _runPwshScript(pwshExecutable!, {
          'INPUT_VERSION_LABEL': raw,
          'REF_NAME': '',
        });
        expect(result.length, lessThanOrEqualTo(64));
        expect(result.endsWith('.'), isFalse);
      });
    },
    skip: pwshExecutable == null ? 'pwsh/powershell 실행 파일을 찾을 수 없음' : false,
  );
}
