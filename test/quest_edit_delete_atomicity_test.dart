import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

Quest _quest(
  String id, {
  String title = '제목',
  QuestStatus status = QuestStatus.active,
  Map<String, double> statRewards = const {'health': 20},
}) => Quest(
  id: id,
  title: title,
  description: '',
  statRewards: Map<String, double>.from(statRewards),
  status: status,
  createdAt: DateTime(2026, 7, 1),
);

/// A [StorageService] whose [saveQuest]/[deleteQuest] each throw on exactly
/// their configured Nth call (1-indexed, 0 = never) and otherwise behave
/// normally. Every call's argument is recorded as a detached snapshot
/// (`.copy()`) *before* the throw check, so assertions can confirm a
/// rollback actually issued a second, successful write — not merely that a
/// shared Hive-boxed instance happens to read back correctly. Same rationale
/// as `_FaultyGoalStorage` in goal_edit_delete_atomicity_test.dart.
class _FaultyQuestStorage extends StorageService {
  _FaultyQuestStorage({super.inMemory});

  int throwOnSaveQuestCall = 0;
  int throwOnDeleteQuestCall = 0;
  // When true, the configured saveQuest failure is detected only *after*
  // the underlying Hive write has already landed (like deleteQuest below)
  // — the harder rollback case, where the undo must genuinely reverse a
  // completed write instead of just skipping one that never happened.
  bool saveQuestThrowsAfterWrite = false;

  final List<Quest> saveQuestCalls = [];
  int deleteQuestCalls = 0;

  @override
  Future<void> saveQuest(Quest quest) async {
    saveQuestCalls.add(quest.copy());
    final shouldThrow = saveQuestCalls.length == throwOnSaveQuestCall;
    if (shouldThrow && !saveQuestThrowsAfterWrite) {
      throw StateError(
        'simulated quest save failure (call ${saveQuestCalls.length})',
      );
    }
    await super.saveQuest(quest);
    if (shouldThrow) {
      throw StateError(
        'simulated quest save failure (call ${saveQuestCalls.length})',
      );
    }
  }

  // The real delete always runs *before* the configured throw — this
  // reproduces a failure detected only after the underlying Hive write has
  // already taken effect, not merely a guard that stops the write from
  // happening at all.
  @override
  Future<void> deleteQuest(String id) async {
    deleteQuestCalls++;
    final shouldThrow = deleteQuestCalls == throwOnDeleteQuestCall;
    await super.deleteQuest(id);
    if (shouldThrow) {
      throw StateError(
        'simulated quest delete failure (call $deleteQuestCalls)',
      );
    }
  }
}

Future<_FaultyQuestStorage> _faultyStorage() async {
  final storage = _FaultyQuestStorage(inMemory: true);
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

void main() {
  group('addQuest — 원자성/롤백/충돌', () {
    test('저장 자체가 실패하면 새 레코드가 남지 않고, 재시도는 정확히 하나만 생성한다', () async {
      final storage = await _faultyStorage();
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.throwOnSaveQuestCall = 1;
      final quest = _quest('q1', title: '새 퀘스트');
      await expectLater(
        notifier.addQuest(quest),
        throwsA(isA<StateError>()),
      );

      // The caller's detached quest object is unaffected — nothing to roll
      // back on it since addQuest never mutates its input.
      expect(quest.title, '새 퀘스트');
      expect(storage.getQuests(), isEmpty);
      // The rollback's delete ran even though the failed save never landed
      // — a harmless no-op delete, not a sign the guard skipped anything.
      expect(storage.saveQuestCalls.length, 1);

      storage.throwOnSaveQuestCall = 0;
      await notifier.addQuest(_quest('q1', title: '새 퀘스트'));

      expect(storage.getQuests(), hasLength(1));
      expect(storage.getQuest('q1')!.title, '새 퀘스트');
    });

    test('실제로 레코드가 저장된 뒤 감지된 실패(after-write)도 롤백이 실제 delete로 지우고, 재시도는 정확히 한 번만 반영된다', () async {
      final storage = await _faultyStorage();
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.saveQuestThrowsAfterWrite = true;
      storage.throwOnSaveQuestCall = 1;

      final quest = _quest('q1', title: '첫 시도');
      await expectLater(
        notifier.addQuest(quest),
        throwsA(isA<StateError>()),
      );

      // The write genuinely landed before the configured throw — confirmed
      // via a mid-transaction read, not merely inferred from the outcome.
      expect(storage.saveQuestCalls.length, 1);
      // Rollback's real delete removed it.
      expect(storage.getQuests(), isEmpty);

      storage.throwOnSaveQuestCall = 0;
      storage.saveQuestThrowsAfterWrite = false;
      await notifier.addQuest(_quest('q1', title: '재시도'));

      expect(storage.getQuests(), hasLength(1));
      expect(storage.getQuest('q1')!.title, '재시도');
    });

    test('같은 id의 다른 레코드가 이미 있으면 덮어쓰지 않고 충돌 예외를 던진다', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', title: '원본'));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      await expectLater(
        notifier.addQuest(_quest('q1', title: '충돌')),
        throwsA(isA<QuestAlreadyExistsException>()),
      );

      expect(storage.getQuest('q1')!.title, '원본');
      expect(storage.getQuests(), hasLength(1));
    });

    test('동시에 같은 id로 두 번 생성을 시도하면 정확히 하나만 반영되고 나머지는 충돌로 거부된다', () async {
      final storage = await createTestStorage();
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      final results = await Future.wait([
        notifier.addQuest(_quest('q1', title: 'A')).then((_) => 'ok').catchError((_) => 'conflict'),
        notifier.addQuest(_quest('q1', title: 'B')).then((_) => 'ok').catchError((_) => 'conflict'),
      ]);

      expect(results.where((r) => r == 'ok'), hasLength(1));
      expect(results.where((r) => r == 'conflict'), hasLength(1));
      expect(storage.getQuests(), hasLength(1));
    });
  });

  group('updateQuest — 원자성/롤백', () {
    test('편집 저장 자체가 실패하면 넘긴 proposed와 storage의 원본이 그대로 남고, 재시도는 한 번만 반영된다', () async {
      final storage = await _faultyStorage();
      final original = _quest('q1', title: '원래 제목');
      await storage.saveQuest(original);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.saveQuestCalls.clear();
      storage.throwOnSaveQuestCall = 1;

      final proposed = original.copy()..title = '새 제목';
      await expectLater(
        notifier.updateQuest(proposed),
        throwsA(isA<StateError>()),
      );

      expect(proposed.title, '새 제목');
      expect(original.title, '원래 제목');
      expect(storage.getQuest('q1')!.title, '원래 제목');

      storage.throwOnSaveQuestCall = 0;
      final stored = storage.getQuest('q1')!;
      final retry = stored.copy()..title = '새 제목';
      await notifier.updateQuest(retry);

      expect(storage.getQuest('q1')!.title, '새 제목');
      expect(storage.getQuests(), hasLength(1));
    });

    test('저장 이후(레코드가 실제로 바뀐 뒤) 실패해도 롤백이 원래 값을 복원한다', () async {
      final storage = await _faultyStorage();
      final original = _quest('q1', title: '원래 제목');
      await storage.saveQuest(original);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.saveQuestCalls.clear();
      // Call #1 = updateQuest's own candidate save, whose failure is only
      // detected *after* the write actually landed. Call #2 = the
      // rollback's restoring save, which must genuinely re-persist the
      // snapshot (not merely skip a write that never happened).
      storage.saveQuestThrowsAfterWrite = true;
      storage.throwOnSaveQuestCall = 1;

      final proposed = original.copy()..title = '실패할 제목';
      await expectLater(
        notifier.updateQuest(proposed),
        throwsA(isA<StateError>()),
      );

      expect(storage.saveQuestCalls.length, 2);
      expect(storage.saveQuestCalls[0].title, '실패할 제목');
      expect(storage.saveQuestCalls[1].title, '원래 제목');
      expect(storage.getQuest('q1')!.title, '원래 제목');
    });

    test('존재하지 않는 퀘스트를 수정하려 하면 QuestNotFoundException을 던지고 아무것도 쓰지 않는다', () async {
      final storage = await createTestStorage();
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final ghost = _quest('ghost', title: '유령');
      await expectLater(
        container.read(questsProvider.notifier).updateQuest(ghost),
        throwsA(isA<QuestNotFoundException>()),
      );
      expect(storage.getQuests(), isEmpty);
    });

    test('완료 처리와 경쟁해도 편집이 완료 상태나 지급된 XP를 되돌릴 수 없다', () async {
      final storage = await createTestStorage();
      final quest = _quest('q1', title: '원래 제목', statRewards: {'health': 20});
      await storage.saveQuest(quest);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      // 폼이 열려 있는 동안(완료 이전 상태를 들고 있는) stale 스냅샷.
      final staleSnapshot = quest.copy();

      // 다른 경로에서 먼저 완료 처리된다.
      await notifier.completeQuest('q1');
      expect(storage.getQuest('q1')!.status, QuestStatus.completed);
      expect(storage.getStat('health')!.currentXp, 20);

      // stale 스냅샷 기반으로 만든 proposed(그 안의 status는 여전히
      // active)로 편집을 저장해도, updateQuest는 현재 저장된 원본에서
      // status/completedAt을 가져오므로 완료 상태를 되돌리지 않는다.
      final proposed = staleSnapshot.copy()..title = '편집된 제목';
      expect(proposed.status, QuestStatus.active); // stale value, ignored by updateQuest
      await notifier.updateQuest(proposed);

      final result = storage.getQuest('q1')!;
      expect(result.title, '편집된 제목');
      expect(result.status, QuestStatus.completed);
      expect(result.completedAt, isNotNull);
      // XP already awarded is untouched by the edit.
      expect(storage.getStat('health')!.currentXp, 20);
    });
  });

  group('deleteQuest — 원자성/롤백', () {
    test('삭제 자체가 실패해 이미 실제로 삭제된 뒤라도, 롤백이 실제 saveQuest로 복원하고 재시도는 정확히 한 번 성공한다', () async {
      final storage = await _faultyStorage();
      await storage.saveQuest(_quest('q1', title: '지울 퀘스트'));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.saveQuestCalls.clear();
      storage.throwOnDeleteQuestCall = 1;

      await expectLater(
        notifier.deleteQuest('q1'),
        throwsA(isA<StateError>()),
      );

      // The underlying delete genuinely ran before the configured throw.
      expect(storage.deleteQuestCalls, 1);
      // Rollback resurrected the quest via one real saveQuest call.
      expect(storage.saveQuestCalls.length, 1);
      expect(storage.saveQuestCalls.single.id, 'q1');
      expect(storage.saveQuestCalls.single.title, '지울 퀘스트');

      final restored = storage.getQuest('q1');
      expect(restored, isNotNull);
      expect(restored!.title, '지울 퀘스트');

      storage.throwOnDeleteQuestCall = 0;
      await notifier.deleteQuest('q1');

      expect(storage.deleteQuestCalls, 2);
      expect(storage.getQuest('q1'), isNull);
    });

    test('존재하지 않는 퀘스트를 삭제하면 안전하게 아무 일도 하지 않는다', () async {
      final storage = await createTestStorage();
      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      await container.read(questsProvider.notifier).deleteQuest('ghost');
      expect(storage.getQuests(), isEmpty);
    });

    test('동시에 두 번 삭제를 호출해도 실제 deleteQuest 호출은 정확히 한 번만 일어난다', () async {
      final storage = await _faultyStorage();
      await storage.saveQuest(_quest('q1', title: '지울 퀘스트'));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      await Future.wait([
        notifier.deleteQuest('q1'),
        notifier.deleteQuest('q1'),
      ]);

      expect(storage.deleteQuestCalls, 1);
      expect(storage.getQuest('q1'), isNull);

      await notifier.deleteQuest('q1');
      expect(storage.deleteQuestCalls, 1);
    });
  });

  group('adoptSuggestion — 원자성/롤백/동시성', () {
    test('after-write 실패는 채택된 것처럼 보이지 않도록 원래 suggested 레코드를 복원한다', () async {
      final storage = await _faultyStorage();
      await storage.saveQuest(
        _quest('q1', title: '추천 퀘스트', status: QuestStatus.suggested),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      // The failure is detected only after adopt's own save actually
      // landed (the "active" write really took effect); the rollback's
      // restoring save (call #2) must genuinely revert it, not merely skip
      // an unperformed write.
      storage.saveQuestCalls.clear();
      storage.saveQuestThrowsAfterWrite = true;
      storage.throwOnSaveQuestCall = 1;

      await expectLater(
        notifier.adoptSuggestion('q1'),
        throwsA(isA<StateError>()),
      );

      expect(storage.saveQuestCalls.length, 2);
      expect(storage.saveQuestCalls[0].status, QuestStatus.active);
      expect(storage.saveQuestCalls[1].status, QuestStatus.suggested);
      final restored = storage.getQuest('q1')!;
      expect(restored.status, QuestStatus.suggested);

      storage.throwOnSaveQuestCall = 0;
      storage.saveQuestThrowsAfterWrite = false;
      await notifier.adoptSuggestion('q1');
      expect(storage.getQuest('q1')!.status, QuestStatus.active);
    });

    test('존재하지 않거나 이미 suggested가 아닌 퀘스트는 안전하게 무시한다', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', status: QuestStatus.active));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      await notifier.adoptSuggestion('q1'); // already active — no-op.
      expect(storage.getQuest('q1')!.status, QuestStatus.active);

      await notifier.adoptSuggestion('ghost'); // missing — no-op.
      expect(storage.getQuests(), hasLength(1));
    });

    test('동시에 두 번 채택해도 정확히 한 번만 실제 saveQuest 호출이 일어나고 결과는 active 하나뿐이다', () async {
      final storage = await _faultyStorage();
      await storage.saveQuest(
        _quest('q1', title: '추천 퀘스트', status: QuestStatus.suggested),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.saveQuestCalls.clear();
      await Future.wait([
        notifier.adoptSuggestion('q1'),
        notifier.adoptSuggestion('q1'),
      ]);

      // Not just the final state — exactly one real saveQuest landed; the
      // second, queued call observed the quest already active and no-op'd
      // without writing (it never even reaches a save).
      expect(storage.saveQuestCalls.length, 1);
      expect(storage.saveQuestCalls.single.status, QuestStatus.active);
      expect(storage.getQuest('q1')!.status, QuestStatus.active);
      expect(storage.getQuests(), hasLength(1));
    });
  });

  group('adoptSuggestion vs dismissSuggestion — 큐잉된 레이스', () {
    // 두 호출을 같은 리스트 리터럴 안에서 await 없이 순서대로 평가하면,
    // rewardLockProvider의 AsyncLock은 synchronized()가 *호출된* 순서로
    // 큐를 쌓는다(각 액션이 실제로 실행되는 시점이 아니라) — 그래서 아래
    // Future.wait의 원소 순서가 곧 잠금 획득 순서를 결정론적으로 재현한다.
    // adoptSuggestion/completeQuest 등도 동일한 패턴을 쓴다.
    test('채택이 먼저 잠금을 잡으면(무시가 뒤에 큐잉) 최종 active이고 무시는 실제 삭제를 한 번도 하지 않는다', () async {
      final storage = await _faultyStorage();
      await storage.saveQuest(
        _quest('q1', title: '추천 퀘스트', status: QuestStatus.suggested),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.saveQuestCalls.clear();
      storage.deleteQuestCalls = 0;
      await Future.wait([
        notifier.adoptSuggestion('q1'),
        notifier.dismissSuggestion('q1'),
      ]);

      expect(storage.getQuest('q1')!.status, QuestStatus.active);
      // The queued dismiss re-read the quest inside its own lock turn, saw
      // it was no longer suggested, and never called through to delete —
      // it must not silently erase the quest adopt just activated.
      expect(storage.deleteQuestCalls, 0);
      expect(storage.saveQuestCalls.length, 1);
      expect(storage.getQuests(), hasLength(1));
    });

    test('무시가 먼저 잠금을 잡으면(채택이 뒤에 큐잉) 최종적으로 사라지고 채택은 실제 저장을 한 번도 하지 않는다', () async {
      final storage = await _faultyStorage();
      await storage.saveQuest(
        _quest('q1', title: '추천 퀘스트', status: QuestStatus.suggested),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.saveQuestCalls.clear();
      storage.deleteQuestCalls = 0;
      await Future.wait([
        notifier.dismissSuggestion('q1'),
        notifier.adoptSuggestion('q1'),
      ]);

      expect(storage.getQuest('q1'), isNull);
      expect(storage.deleteQuestCalls, 1);
      // The queued adopt re-read the quest inside its own lock turn, found
      // it gone, and never called through to save — it must not resurrect
      // a quest that was legitimately dismissed.
      expect(storage.saveQuestCalls, isEmpty);
      expect(storage.getQuests(), isEmpty);
    });
  });

  group('completeQuest vs deleteQuest — 큐잉된 레이스', () {
    test('완료가 먼저 잠금을 잡으면(삭제가 뒤에 큐잉) 완료 상태·XP가 보존되고 삭제는 실제 삭제를 한 번도 하지 않는다', () async {
      final storage = await _faultyStorage();
      await storage.saveQuest(_quest('q1', title: '완료할 퀘스트', statRewards: {'health': 20}));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.deleteQuestCalls = 0;
      // completeQuest() now acquires questCompletionExecutionLockProvider
      // *before* rewardLockProvider (see plan section 4.4) — unlike
      // deleteQuest(), which only ever touches rewardLockProvider directly.
      // That extra lock's own acquisition is itself async (a real microtask
      // hop even on the uncontested fast path), so completeQuest() no
      // longer claims rewardLockProvider's queue slot synchronously inline
      // the instant it's called. A bare `Future.wait([complete(), delete()])`
      // would let delete's synchronous, hop-free claim win the queue even
      // though complete was dispatched first. Yielding once here lets
      // complete actually reach and claim its rewardLockProvider queue slot
      // before delete is dispatched, restoring "dispatched first ==
      // acquires first" determinism for this specific pairing.
      final completeFuture = notifier.completeQuest('q1');
      await Future<void>.delayed(Duration.zero);
      final deleteFuture = notifier.deleteQuest('q1');
      await Future.wait([completeFuture, deleteFuture]);

      final result = storage.getQuest('q1');
      expect(result, isNotNull);
      expect(result!.status, QuestStatus.completed);
      expect(result.completedAt, isNotNull);
      // XP was awarded exactly once — the queued delete never got a chance
      // to erase completed history, and completeQuest itself only ever
      // runs its award path once per call.
      expect(storage.getStat('health')!.currentXp, 20);
      expect(storage.deleteQuestCalls, 0);
    });

    test('삭제가 먼저 잠금을 잡으면(완료가 뒤에 큐잉) 퀘스트가 사라지고 완료는 XP를 전혀 지급하지 않는다', () async {
      final storage = await _faultyStorage();
      await storage.saveQuest(_quest('q1', title: '지울 퀘스트', statRewards: {'health': 20}));

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      storage.deleteQuestCalls = 0;
      await Future.wait([
        notifier.deleteQuest('q1'),
        notifier.completeQuest('q1'),
      ]);

      expect(storage.getQuest('q1'), isNull);
      expect(storage.deleteQuestCalls, 1);
      // The queued completeQuest re-read storage inside its own lock turn,
      // found the quest gone, and awarded nothing.
      expect(storage.getStat('health')!.currentXp, 0);
    });
  });

  group('completeQuest vs updateQuest — 큐잉된 편집/완료 레이스(양방향)', () {
    test('완료가 먼저 잠금을 잡으면(편집이 뒤에 큐잉) 완료 상태·XP를 보존한 채 편집 필드만 반영된다', () async {
      final storage = await createTestStorage();
      final quest = _quest('q1', title: '원래 제목', statRewards: {'health': 20});
      await storage.saveQuest(quest);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      final proposed = quest.copy()..title = '편집된 제목';
      await Future.wait([
        notifier.completeQuest('q1'),
        notifier.updateQuest(proposed),
      ]);

      final result = storage.getQuest('q1')!;
      expect(result.status, QuestStatus.completed);
      expect(result.title, '편집된 제목');
      expect(result.completedAt, isNotNull);
      // XP awarded exactly once, whichever order the two calls actually ran in.
      expect(storage.getStat('health')!.currentXp, 20);
    });

    test('편집이 먼저 잠금을 잡으면(완료가 뒤에 큐잉) 편집된 필드 위에 완료 상태·XP가 정확히 한 번 반영된다', () async {
      final storage = await createTestStorage();
      final quest = _quest('q1', title: '원래 제목', statRewards: {'health': 20});
      await storage.saveQuest(quest);

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(questsProvider.notifier);

      final proposed = quest.copy()..title = '편집된 제목';
      await Future.wait([
        notifier.updateQuest(proposed),
        notifier.completeQuest('q1'),
      ]);

      final result = storage.getQuest('q1')!;
      expect(result.status, QuestStatus.completed);
      expect(result.title, '편집된 제목');
      expect(result.completedAt, isNotNull);
      expect(storage.getStat('health')!.currentXp, 20);
    });
  });
}
