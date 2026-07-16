import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

// 대시보드 허브 아래 "진행중인 퀘스트" 남은 목록은 컴팩트 폰 크기(400x800)
// 뷰포트에서는 스크롤해야 보인다 — dashboard_screen_test.dart의 다중 퀘스트
// 테스트와 같은 더 큰 화면을 써서 스크롤 없이 남은 행들을 바로 찾는다.
const _tallScreen = Size(600, 1600);

/// completeQuest 호출을 [gate]가 풀릴 때까지 붙잡아두고, id별 호출 횟수를
/// 세고, [shouldThrow]가 true면 실패를 재현하는 QuestsNotifier —
/// quests_screen_flow_test.dart의 `_GatedQuestsListNotifier`와 같은 패턴.
class _GatedQuestsNotifier extends QuestsNotifier {
  _GatedQuestsNotifier(super.storage, super.ref);

  final Map<String, int> completeCallsById = {};
  bool shouldThrow = false;
  Completer<void> gate = Completer<void>();

  @override
  Future<QuestCompletionResult> completeQuest(String id) async {
    completeCallsById.update(id, (v) => v + 1, ifAbsent: () => 1);
    await gate.future;
    if (shouldThrow) throw StateError('simulated complete failure');
    return super.completeQuest(id);
  }
}

/// [title] 텍스트가 속한 QuestCard의 완료 버튼 — 다른 행이 완료 중이라
/// 텍스트가 스피너로 바뀌어도(즉 '완료' 텍스트로 찾는 인덱스가 밀려도)
/// 흔들리지 않도록 카드 단위로 앵커링한다.
Finder _completeButtonFor(String title) {
  return find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Card)),
    matching: find.byType(FilledButton),
  );
}

Future<Quest> _saveQuest(
  StorageService storage,
  String id,
  String title,
) async {
  final quest = Quest(
    id: id,
    title: title,
    description: '',
    statRewards: {'health': 10},
    createdAt: DateTime(2026, 7, 1),
  );
  await storage.saveQuest(quest);
  return quest;
}

/// 대시보드 허브가 강조하는 단 하나의 "다음 퀘스트"를 제외한 나머지 행은
/// 최소 3개의 진행중 퀘스트가 있어야 확실히 2개 이상 남는다(허브가 하나를
/// 가져가므로). 여기서는 goalId 없는 두 퀘스트 + 목표 연결로 최우선순위를
/// 강제로 뺏는 세 번째 퀘스트를 심어 "남은 목록"에 정확히 2개가 오도록 한다.
Future<void> _seedThreeActiveQuests(StorageService storage) async {
  await storage.saveQuest(
    Quest(
      id: 'hub',
      title: '허브 강조 퀘스트',
      description: '',
      statRewards: {'health': 5},
      difficulty: QuestDifficulty.hard,
      goalId: 'some-goal',
      createdAt: DateTime(2026, 7, 1),
    ),
  );
  await _saveQuest(storage, 'r1', '남은 퀘스트 1');
  await _saveQuest(storage, 'r2', '남은 퀘스트 2');
}

void main() {
  testWidgets('남은 퀘스트 행을 리빌드 전에 두 번 눌러도 해당 행만 pending이고 완료 호출은 한 번뿐이다', (
    tester,
  ) async {
    setScreenSize(tester, _tallScreen);
    final storage = await createTestStorage();
    await _seedThreeActiveQuests(storage);
    late _GatedQuestsNotifier notifier;

    await pumpApp(
      tester,
      storage,
      const DashboardScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsNotifier(
            ref.watch(storageServiceProvider),
            ref,
          );
          return notifier;
        }),
      ],
    );

    final r1Button = _completeButtonFor('남은 퀘스트 1');
    final r2Button = _completeButtonFor('남은 퀘스트 2');
    await tester.ensureVisible(r1Button);

    await tester.tap(r1Button);
    await tester.pump();
    await tester.tap(r1Button);
    await tester.pump();

    expect(notifier.completeCallsById['r1'], 1);
    // r1 행은 비활성화(스피너)됐지만 r2 행은 그대로 눌릴 수 있어야 한다.
    expect(tester.widget<FilledButton>(r1Button).onPressed, isNull);
    expect(tester.widget<FilledButton>(r2Button).onPressed, isNotNull);

    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(notifier.completeCallsById['r1'], 1);
    expect(notifier.completeCallsById['r2'], isNull);
    expect(find.text('"남은 퀘스트 1" 완료!'), findsOneWidget);
  });

  testWidgets('남은 퀘스트 완료가 실패하면 일반 오류 메시지만 뜨고 퀘스트는 남으며, 재시도는 성공한다', (
    tester,
  ) async {
    setScreenSize(tester, _tallScreen);
    final storage = await createTestStorage();
    await _seedThreeActiveQuests(storage);
    late _GatedQuestsNotifier notifier;

    await pumpApp(
      tester,
      storage,
      const DashboardScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsNotifier(
            ref.watch(storageServiceProvider),
            ref,
          );
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    final r1Button = _completeButtonFor('남은 퀘스트 1');
    await tester.ensureVisible(r1Button);
    await tester.tap(r1Button);
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('퀘스트 완료 처리에 실패했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('StateError'), findsNothing);
    expect(find.textContaining('완료!'), findsNothing);
    expect(find.text('남은 퀘스트 1'), findsOneWidget);
    expect(storage.getQuest('r1')!.status, QuestStatus.active);

    notifier.shouldThrow = false;
    notifier.gate = Completer<void>();
    await tester.tap(find.text('재시도'));
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(notifier.completeCallsById['r1'], 2);
    expect(storage.getQuest('r1')!.status, QuestStatus.completed);
  });

  testWidgets('완료 대기 중 화면이 dispose돼도 setState/다이얼로그 오류 없이 안전하다', (
    tester,
  ) async {
    setScreenSize(tester, _tallScreen);
    final storage = await createTestStorage();
    await _seedThreeActiveQuests(storage);
    late _GatedQuestsNotifier notifier;

    await pumpApp(
      tester,
      storage,
      const DashboardScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          notifier = _GatedQuestsNotifier(
            ref.watch(storageServiceProvider),
            ref,
          );
          return notifier;
        }),
      ],
    );

    final r1Button = _completeButtonFor('남은 퀘스트 1');
    await tester.ensureVisible(r1Button);
    await tester.tap(r1Button);
    await tester.pump();

    // 완료가 아직 pending인 채로 다른 화면으로 교체 — DashboardScreen 트리
    // 전체가 dispose된다.
    await tester.pumpWidget(const SizedBox.shrink());

    notifier.gate.complete();
    // 대기 중이던 completeQuest의 콜백이 dispose 이후 실행돼도 예외 없이
    // 조용히 끝나야 한다(테스트 실패는 프레임워크가 assertion으로 표면화한다).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('didComplete가 false면(다른 화면이 먼저 완료/삭제) 완료 스낵바나 다이얼로그를 띄우지 않는다', (
    tester,
  ) async {
    setScreenSize(tester, _tallScreen);
    final storage = await createTestStorage();
    await _seedThreeActiveQuests(storage);

    await pumpApp(
      tester,
      storage,
      const DashboardScreen(),
      overrides: [
        questsProvider.overrideWith((ref) {
          return _StaleNoOpQuestsNotifier(
            ref.watch(storageServiceProvider),
            ref,
          );
        }),
      ],
    );

    final r1Button = _completeButtonFor('남은 퀘스트 1');
    await tester.ensureVisible(r1Button);
    await tester.tap(r1Button);
    await tester.pumpAndSettle();

    expect(find.textContaining('완료!'), findsNothing);
    expect(find.text('🏆 업적 달성!'), findsNothing);
    expect(find.text('🎉 레벨업!'), findsNothing);
    expect(find.textContaining('실패'), findsNothing);
  });
}

/// 항상 didComplete: false인 안전한 무결과를 돌려주는 QuestsNotifier — 다른
/// 화면이 먼저 완료/삭제해서 이 호출이 조용한 stale no-op이 된 상황을
/// 재현한다.
class _StaleNoOpQuestsNotifier extends QuestsNotifier {
  _StaleNoOpQuestsNotifier(super.storage, super.ref);

  @override
  Future<QuestCompletionResult> completeQuest(String id) async {
    return const QuestCompletionResult(
      didComplete: false,
      levelUps: {},
      newAchievements: [],
    );
  }
}
