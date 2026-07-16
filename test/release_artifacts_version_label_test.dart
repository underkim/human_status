import 'dart:async';
import 'dart:convert';
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
///
/// Every process is started asynchronously (never Process.runSync) and every
/// wait -- for exit, and separately for each output stream -- has its own
/// bounded timeout. On Windows, a shell like git-bash can spawn a lingering
/// helper process that keeps the stdout/stderr pipe's write end open even
/// after the script we care about has exited, which would otherwise make an
/// unbounded stream read hang forever with no visible process left to blame.
/// Bounding every wait independently, and force-killing on timeout, means a
/// missing/broken shell fails the test quickly instead of hanging the suite.
class ProcessTimeoutException implements Exception {
  ProcessTimeoutException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ProcessOutcome {
  _ProcessOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<void> _killTree(Process process) async {
  if (Platform.isWindows) {
    try {
      await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        '${process.pid}',
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort: fall through to the direct kill below regardless.
    }
  }
  process.kill(ProcessSignal.sigkill);
}

/// Starts [executable], waits for it to exit within [timeout], and collects
/// its output -- never with an unbounded wait. Kills the whole process tree
/// and throws [ProcessTimeoutException] (with whatever partial output was
/// captured) if the process doesn't exit in time, or if either output
/// stream never closes even after the process reports it has exited.
Future<_ProcessOutcome> _runProcess(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: true,
  );
  unawaited(process.stdin.close());

  final stdoutFuture = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final stderrFuture = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();

  const drainGrace = Duration(seconds: 5);

  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    await _killTree(process);
    final partialOut = await stdoutFuture.timeout(
      drainGrace,
      onTimeout: () => '(stdout unavailable after forced kill)',
    );
    final partialErr = await stderrFuture.timeout(
      drainGrace,
      onTimeout: () => '(stderr unavailable after forced kill)',
    );
    throw ProcessTimeoutException(
      '$executable ${arguments.join(' ')} timed out after $timeout and was '
      'force-killed.\npartial stdout: $partialOut\npartial stderr: $partialErr',
    );
  }

  // The process has exited, but on Windows a lingering grandchild can still
  // hold the stdout/stderr pipe open -- never wait unboundedly for it to
  // close, since the assertion only needs what the script already flushed.
  final stdout = await stdoutFuture.timeout(
    drainGrace,
    onTimeout: () => '(stdout stream did not close after process exit)',
  );
  final stderr = await stderrFuture.timeout(
    drainGrace,
    onTimeout: () => '(stderr stream did not close after process exit)',
  );

  return _ProcessOutcome(exitCode: exitCode, stdout: stdout, stderr: stderr);
}

Future<String> _runBashScript(Map<String, String> env) async {
  final outcome = await _runProcess('bash', [
    'tool/ci/sanitize_version_label.sh',
  ], environment: env);
  expect(
    outcome.exitCode,
    0,
    reason: 'stdout: ${outcome.stdout}\nstderr: ${outcome.stderr}',
  );
  return outcome.stdout.trim();
}

Future<String?> _findPwshExecutable() async {
  for (final candidate in ['pwsh', 'powershell']) {
    try {
      final outcome = await _runProcess(
        candidate,
        ['-NoProfile', '-Command', 'exit 0'],
        environment: const {},
        timeout: const Duration(seconds: 10),
      );
      if (outcome.exitCode == 0) return candidate;
    } on ProcessException {
      // Not installed on this machine -- try the next candidate.
    } on ProcessTimeoutException {
      // Hung/unresponsive -- treat as unavailable rather than block startup.
    }
  }
  return null;
}

Future<String> _runPwshScript(
  String executable,
  Map<String, String> env,
) async {
  final outcome = await _runProcess(executable, [
    '-NoProfile',
    '-NonInteractive',
    '-File',
    'tool/ci/sanitize_version_label.ps1',
  ], environment: env);
  expect(
    outcome.exitCode,
    0,
    reason: 'stdout: ${outcome.stdout}\nstderr: ${outcome.stderr}',
  );
  return outcome.stdout.trim();
}

void main() {
  group('sanitize_version_label.sh (bash)', () {
    test('입력이 모두 비어 있으면 dev로 대체된다', () async {
      expect(
        await _runBashScript({'INPUT_VERSION_LABEL': '', 'REF_NAME': ''}),
        'dev',
      );
    });

    test('안전한 태그 이름은 그대로 유지된다', () async {
      expect(
        await _runBashScript({'INPUT_VERSION_LABEL': 'v1.2.3', 'REF_NAME': ''}),
        'v1.2.3',
      );
    });

    test('슬래시/세미콜론/공백 등 위험 문자는 대시로 치환된다', () async {
      final result = await _runBashScript({
        'INPUT_VERSION_LABEL': 'refs/heads/feature;rm -rf',
        'REF_NAME': '',
      });
      expect(result, isNot(contains('/')));
      expect(result, isNot(contains(';')));
      expect(result, isNot(contains(' ')));
    });

    test('점(.)으로만 이루어진 입력은 dev로 대체된다', () async {
      expect(
        await _runBashScript({'INPUT_VERSION_LABEL': '.' * 20, 'REF_NAME': ''}),
        'dev',
      );
    });

    test('64자를 넘는 입력은 64자로 잘린다', () async {
      final result = await _runBashScript({
        'INPUT_VERSION_LABEL': 'a' * 80,
        'REF_NAME': '',
      });
      expect(result.length, lessThanOrEqualTo(64));
      expect(result, 'a' * 64);
    });

    test('잘린 뒤 끝에 점이 남는 입력도 정리된다', () async {
      final raw = '${'a' * 63}${'.' * 20}';
      final result = await _runBashScript({
        'INPUT_VERSION_LABEL': raw,
        'REF_NAME': '',
      });
      expect(result.length, lessThanOrEqualTo(64));
      expect(result.endsWith('.'), isFalse);
    });
  });

  group('sanitize_version_label.ps1 (PowerShell)', () {
    String? pwshExecutable;

    setUpAll(() async {
      pwshExecutable = await _findPwshExecutable();
    });

    test('입력이 모두 비어 있으면 dev로 대체된다', () async {
      if (pwshExecutable == null) {
        markTestSkipped('pwsh/powershell 실행 파일을 찾을 수 없음');
        return;
      }
      expect(
        await _runPwshScript(pwshExecutable!, {
          'INPUT_VERSION_LABEL': '',
          'REF_NAME': '',
        }),
        'dev',
      );
    });

    test('안전한 태그 이름은 그대로 유지된다', () async {
      if (pwshExecutable == null) {
        markTestSkipped('pwsh/powershell 실행 파일을 찾을 수 없음');
        return;
      }
      expect(
        await _runPwshScript(pwshExecutable!, {
          'INPUT_VERSION_LABEL': 'v1.2.3',
          'REF_NAME': '',
        }),
        'v1.2.3',
      );
    });

    test('슬래시/세미콜론/공백 등 위험 문자는 대시로 치환된다', () async {
      if (pwshExecutable == null) {
        markTestSkipped('pwsh/powershell 실행 파일을 찾을 수 없음');
        return;
      }
      final result = await _runPwshScript(pwshExecutable!, {
        'INPUT_VERSION_LABEL': 'refs/heads/feature;rm -rf',
        'REF_NAME': '',
      });
      expect(result, isNot(contains('/')));
      expect(result, isNot(contains(';')));
      expect(result, isNot(contains(' ')));
    });

    test('점(.)으로만 이루어진 입력은 dev로 대체된다', () async {
      if (pwshExecutable == null) {
        markTestSkipped('pwsh/powershell 실행 파일을 찾을 수 없음');
        return;
      }
      expect(
        await _runPwshScript(pwshExecutable!, {
          'INPUT_VERSION_LABEL': '.' * 20,
          'REF_NAME': '',
        }),
        'dev',
      );
    });

    test('64자를 넘는 입력은 64자로 잘린다', () async {
      if (pwshExecutable == null) {
        markTestSkipped('pwsh/powershell 실행 파일을 찾을 수 없음');
        return;
      }
      final result = await _runPwshScript(pwshExecutable!, {
        'INPUT_VERSION_LABEL': 'a' * 80,
        'REF_NAME': '',
      });
      expect(result.length, lessThanOrEqualTo(64));
      expect(result, 'a' * 64);
    });

    test('잘린 뒤 끝에 점이 남는 입력도 정리된다', () async {
      if (pwshExecutable == null) {
        markTestSkipped('pwsh/powershell 실행 파일을 찾을 수 없음');
        return;
      }
      final raw = '${'a' * 63}${'.' * 20}';
      final result = await _runPwshScript(pwshExecutable!, {
        'INPUT_VERSION_LABEL': raw,
        'REF_NAME': '',
      });
      expect(result.length, lessThanOrEqualTo(64));
      expect(result.endsWith('.'), isFalse);
    });
  });
}
