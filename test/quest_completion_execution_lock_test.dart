import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/quest_completion_execution_lock.dart';

/// Runs the same serialization/timeout/exception-release contract against
/// both [QuestCompletionLockBackend] implementations: the in-memory backend
/// (what every test and web build actually uses — see
/// `questCompletionExecutionLockProvider`) and the real file-based backend
/// (what production disk-backed storage uses). Sharing one test body proves
/// neither backend's semantics silently diverge from the other.
void main() {
  group('in-memory backend', () {
    _runLockContractTests(() async {
      final backend = InMemoryQuestCompletionLockBackend();
      return (backend, () async {});
    });
  });

  group('file backend', () {
    _runLockContractTests(() async {
      final dir = await Directory.systemTemp.createTemp(
        'quest_completion_lock_test_',
      );
      final path = '${dir.path}${Platform.pathSeparator}quest_completion.lock';
      final backend = FileQuestCompletionLockBackend(() async => path);
      return (backend, () async {
        await dir.delete(recursive: true);
      });
    });
  });

  group('FileQuestCompletionLockBackend', () {
    test('lock 파일 경로는 지연 평가되고 첫 acquire에서 한 번만 계산된다', () async {
      var resolveCalls = 0;
      final dir = await Directory.systemTemp.createTemp(
        'quest_completion_lock_test_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}quest_completion.lock';
      final backend = FileQuestCompletionLockBackend(() async {
        resolveCalls++;
        return path;
      });
      final lock = QuestCompletionExecutionLock(backend: backend);

      expect(resolveCalls, 0);
      await lock.synchronized(() async => 1);
      expect(resolveCalls, 1);
      await lock.synchronized(() async => 2);
      expect(resolveCalls, 1);
    });

    test('lock 파일은 존재해도 내용을 비우지 않는다', () async {
      final dir = await Directory.systemTemp.createTemp(
        'quest_completion_lock_test_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}quest_completion.lock';
      await File(path).writeAsString('preexisting-marker');

      final backend = FileQuestCompletionLockBackend(() async => path);
      final lock = QuestCompletionExecutionLock(backend: backend);
      await lock.synchronized(() async => null);

      expect(await File(path).readAsString(), 'preexisting-marker');
    });
  });
}

/// [makeBackend] returns a fresh backend for the test plus a teardown
/// callback (e.g. deleting a temp directory). Building it once per test
/// (rather than once for the whole group) keeps the two backends'
/// serialization state from leaking across tests.
void _runLockContractTests(
  Future<(QuestCompletionLockBackend, Future<void> Function())> Function()
  makeBackend,
) {
  test('두 호출이 동시에 들어오면 하나가 끝난 뒤에야 다음이 실행된다 (직렬화)', () async {
    final (backend, teardown) = await makeBackend();
    addTearDown(teardown);
    final lock = QuestCompletionExecutionLock(backend: backend);

    final events = <String>[];
    final firstGate = Completer<void>();

    final firstFuture = lock.synchronized(() async {
      events.add('first-enter');
      await firstGate.future;
      events.add('first-exit');
    });

    // Give the first call a chance to actually acquire the lock before the
    // second one is dispatched.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, ['first-enter']);

    final secondFuture = lock.synchronized(() async {
      events.add('second-enter');
    });

    // The second call must not be able to run while the first still holds
    // the lock, no matter how long we wait.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(events, ['first-enter']);

    firstGate.complete();
    await firstFuture;
    await secondFuture;

    expect(events, ['first-enter', 'first-exit', 'second-enter']);
  });

  test('잠금 획득이 타임아웃 전에 풀리지 않으면 QuestCompletionLockTimeoutException을 던진다', () async {
    final (backend, teardown) = await makeBackend();
    addTearDown(teardown);
    final holderLock = QuestCompletionExecutionLock(
      backend: backend,
      timeout: const Duration(seconds: 10),
    );
    final waiterLock = QuestCompletionExecutionLock(
      backend: backend,
      timeout: const Duration(milliseconds: 150),
    );

    final release = Completer<void>();
    final holderFuture = holderLock.synchronized(() => release.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await expectLater(
      waiterLock.synchronized(() async => 'never runs'),
      throwsA(isA<QuestCompletionLockTimeoutException>()),
    );

    release.complete();
    await holderFuture;
  });

  test('action이 예외를 던져도 잠금은 해제되어 다음 호출이 실행된다', () async {
    final (backend, teardown) = await makeBackend();
    addTearDown(teardown);
    final lock = QuestCompletionExecutionLock(backend: backend);

    await expectLater(
      lock.synchronized(() async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );

    // If the failed call had leaked the lock, this would hang/timeout
    // instead of completing.
    final result = await lock.synchronized(() async => 'ok');
    expect(result, 'ok');
  });

  test('release()를 두 번 호출해도 안전하다 (idempotent)', () async {
    final (backend, teardown) = await makeBackend();
    addTearDown(teardown);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final handle = await backend.acquire(deadline);

    await handle.release();
    await handle.release();

    // The lock must be free again — a fresh acquire should succeed
    // immediately rather than hang behind a phantom hold.
    final second = await backend.acquire(
      DateTime.now().add(const Duration(seconds: 5)),
    );
    await second.release();
  });
}
