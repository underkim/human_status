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
///
/// Output is accumulated via explicitly-owned [StreamSubscription]s instead
/// of `Stream.join()`. `Future.timeout()` on a `.join()` future only gives up
/// on *waiting*, it does not cancel the subscription `.join()` created
/// internally -- so if a grandchild process kept the pipe's write end open,
/// that subscription would keep listening forever, keeping the test
/// isolate's event loop alive even after every child process was gone. Owning
/// the subscriptions ourselves lets every exit path -- success, timeout, or
/// any other error -- cancel them in a `finally` block.
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
  await process.stdin.close();

  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();

  void completeOnce(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  final stdoutSub = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(
        stdoutBuffer.write,
        onDone: () => completeOnce(stdoutDone),
        onError: (Object _, StackTrace _) => completeOnce(stdoutDone),
        cancelOnError: false,
      );
  final stderrSub = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(
        stderrBuffer.write,
        onDone: () => completeOnce(stderrDone),
        onError: (Object _, StackTrace _) => completeOnce(stderrDone),
        cancelOnError: false,
      );

  const drainGrace = Duration(seconds: 5);

  try {
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      await _killTree(process);
      // Bound the wait for the kill to actually be observed, and for
      // whatever output the script already flushed to arrive, but never
      // wait unboundedly -- a killed process's exitCode/stream should
      // settle quickly, and if it doesn't we still must not hang here.
      await process.exitCode.timeout(drainGrace, onTimeout: () => -1);
      await stdoutDone.future.timeout(drainGrace, onTimeout: () {});
      await stderrDone.future.timeout(drainGrace, onTimeout: () {});
      throw ProcessTimeoutException(
        '$executable ${arguments.join(' ')} timed out after $timeout and was '
        'force-killed.\npartial stdout: $stdoutBuffer\npartial stderr: $stderrBuffer',
      );
    }

    // The process has exited, but on Windows a lingering grandchild can
    // still hold the stdout/stderr pipe open -- never wait unboundedly for
    // it to close, since the assertion only needs what the script already
    // flushed.
    await stdoutDone.future.timeout(drainGrace, onTimeout: () {});
    await stderrDone.future.timeout(drainGrace, onTimeout: () {});

    return _ProcessOutcome(
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  } finally {
    // Always release the subscriptions, on every exit path, so a pipe a
    // grandchild is still holding open can never keep this isolate alive.
    await stdoutSub.cancel();
    await stderrSub.cancel();
  }
}

/// Resolves a real POSIX shell to run tool/ci/sanitize_version_label.sh
/// with. On some Windows machines, `bash` on PATH resolves not to Git for
/// Windows' bash but to the WSL launcher stub Windows installs at
/// `%LOCALAPPDATA%\Microsoft\WindowsApps\bash.exe` (a "UWP App Execution
/// Alias"). That stub hangs indefinitely when started with redirected
/// stdio outside of an interactive WSL session -- confirmed directly with a
/// bare `Process.start('bash', ...)` with no Dart/Flutter test code
/// involved at all, so no amount of stream-handling logic here can work
/// around it. GitHub Actions' windows-latest runners don't have WSL
/// enabled, so this ambiguity is a local-dev-machine-only problem; we still
/// route around it explicitly rather than depend on `bash` resolving to the
/// right thing.
///
/// Takes its inputs as parameters (rather than reading `Platform.*`
/// directly) purely so the "bash resolution" test group below can exercise
/// every branch (override present/missing, Windows/non-Windows, Git found
/// at either location) against a fake environment/filesystem, without
/// needing to mutate the real one or actually spawn a process.
String resolveBashExecutableFor({
  required Map<String, String> environment,
  required bool isWindows,
  required bool Function(String path) fileExists,
}) {
  final override = environment['GIT_BASH_PATH'];
  if (override != null && override.isNotEmpty && fileExists(override)) {
    return override;
  }
  if (isWindows) {
    for (final envVar in ['ProgramFiles', 'ProgramFiles(x86)']) {
      final programFiles = environment[envVar];
      if (programFiles == null || programFiles.isEmpty) continue;
      for (final suffix in [r'Git\bin\bash.exe', r'Git\usr\bin\bash.exe']) {
        final candidate = '$programFiles\\$suffix';
        if (fileExists(candidate)) return candidate;
      }
    }
  }
  // Linux/macOS (and any Windows machine without Git for Windows installed
  // at one of the usual locations) fall back to plain PATH resolution.
  return 'bash';
}

String _resolveBashExecutable() => resolveBashExecutableFor(
  environment: Platform.environment,
  isWindows: Platform.isWindows,
  fileExists: (path) => File(path).existsSync(),
);

Future<String> _runBashScript(
  String bashExecutable,
  Map<String, String> env,
) async {
  final outcome = await _runProcess(bashExecutable, [
    // Skip login/interactive startup files: irrelevant to the WSL-stub
    // hang above (that stub hangs before any profile would even run), but
    // cheap defense-in-depth against any real bash whose profile does
    // something slow.
    '--noprofile',
    '--norc',
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
  group('resolveBashExecutableFor (bash 실행 파일 탐색)', () {
    test('GIT_BASH_PATH가 실제 존재하는 파일을 가리키면 그것을 쓴다', () {
      expect(
        resolveBashExecutableFor(
          environment: const {'GIT_BASH_PATH': r'C:\fake\bash.exe'},
          isWindows: true,
          fileExists: (path) => path == r'C:\fake\bash.exe',
        ),
        r'C:\fake\bash.exe',
      );
    });

    test('GIT_BASH_PATH가 존재하지 않는 파일이면 무시하고 계속 탐색한다', () {
      final result = resolveBashExecutableFor(
        environment: const {
          'GIT_BASH_PATH': r'C:\missing\bash.exe',
          'ProgramFiles': r'C:\Program Files',
        },
        isWindows: true,
        fileExists: (path) => path == r'C:\Program Files\Git\bin\bash.exe',
      );
      expect(result, r'C:\Program Files\Git\bin\bash.exe');
    });

    test('Windows에서 Git\\bin\\bash.exe가 있으면 그것을 쓴다', () {
      final result = resolveBashExecutableFor(
        environment: const {'ProgramFiles': r'C:\Program Files'},
        isWindows: true,
        fileExists: (path) => path == r'C:\Program Files\Git\bin\bash.exe',
      );
      expect(result, r'C:\Program Files\Git\bin\bash.exe');
    });

    test('Git\\bin에 없으면 Git\\usr\\bin\\bash.exe로 대체한다', () {
      final result = resolveBashExecutableFor(
        environment: const {'ProgramFiles': r'C:\Program Files'},
        isWindows: true,
        fileExists: (path) => path == r'C:\Program Files\Git\usr\bin\bash.exe',
      );
      expect(result, r'C:\Program Files\Git\usr\bin\bash.exe');
    });

    test('Windows에서 Git을 어디서도 찾지 못하면 PATH의 bash로 대체한다', () {
      final result = resolveBashExecutableFor(
        environment: const {'ProgramFiles': r'C:\Program Files'},
        isWindows: true,
        fileExists: (_) => false,
      );
      expect(result, 'bash');
    });

    test('Windows가 아니면 Git 탐색 없이 곧바로 PATH의 bash를 쓴다', () {
      final result = resolveBashExecutableFor(
        environment: const {'ProgramFiles': r'C:\Program Files'},
        isWindows: false,
        fileExists: (_) => true,
      );
      expect(result, 'bash');
    });
  });

  group('sanitize_version_label.sh (bash)', () {
    late String bashExecutable;

    setUpAll(() {
      bashExecutable = _resolveBashExecutable();
    });

    test('입력이 모두 비어 있으면 dev로 대체된다', () async {
      expect(
        await _runBashScript(bashExecutable, {
          'INPUT_VERSION_LABEL': '',
          'REF_NAME': '',
        }),
        'dev',
      );
    });

    test('안전한 태그 이름은 그대로 유지된다', () async {
      expect(
        await _runBashScript(bashExecutable, {
          'INPUT_VERSION_LABEL': 'v1.2.3',
          'REF_NAME': '',
        }),
        'v1.2.3',
      );
    });

    test('슬래시/세미콜론/공백 등 위험 문자는 대시로 치환된다', () async {
      final result = await _runBashScript(bashExecutable, {
        'INPUT_VERSION_LABEL': 'refs/heads/feature;rm -rf',
        'REF_NAME': '',
      });
      expect(result, isNot(contains('/')));
      expect(result, isNot(contains(';')));
      expect(result, isNot(contains(' ')));
    });

    test('점(.)으로만 이루어진 입력은 dev로 대체된다', () async {
      expect(
        await _runBashScript(bashExecutable, {
          'INPUT_VERSION_LABEL': '.' * 20,
          'REF_NAME': '',
        }),
        'dev',
      );
    });

    test('64자를 넘는 입력은 64자로 잘린다', () async {
      final result = await _runBashScript(bashExecutable, {
        'INPUT_VERSION_LABEL': 'a' * 80,
        'REF_NAME': '',
      });
      expect(result.length, lessThanOrEqualTo(64));
      expect(result, 'a' * 64);
    });

    test('잘린 뒤 끝에 점이 남는 입력도 정리된다', () async {
      final raw = '${'a' * 63}${'.' * 20}';
      final result = await _runBashScript(bashExecutable, {
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
