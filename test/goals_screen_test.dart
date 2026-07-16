import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/providers/goal_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/goals_screen.dart';
import 'package:human_status/widgets/goal_progress_card.dart';

import 'helpers/test_app.dart';

/// 완료 처리 중엔 계속 애니메이션하는 CircularProgressIndicator가 버튼
/// 안에 남아 있어 pumpAndSettle이 절대 멈추지 않는다 — 대신 고정된 프레임
/// 수만큼 수동으로 진행시킨다. goal_form_screen_test.dart의 `_pumpSubmit`과
/// 같은 패턴.
Future<void> _pumpUntilDone(WidgetTester tester, {int iterations = 10}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// deleteGoal/completeGoal 호출을 [gate]가 풀릴 때까지 붙잡아두고, 호출
/// 횟수를 세고, [shouldThrow]가 true면 실패를 재현하는 GoalsNotifier —
/// goal_form_screen_test.dart의 `_GatedGoalsNotifier`와 같은 패턴.
class _GatedGoalsListNotifier extends GoalsNotifier {
  _GatedGoalsListNotifier(super.storage, super.ref);

  int deleteCalls = 0;
  int completeCalls = 0;
  bool shouldThrow = false;
  Completer<void> gate = Completer<void>();

  @override
  Future<void> deleteGoal(String goalId) async {
    deleteCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated delete failure');
    await super.deleteGoal(goalId);
  }

  @override
  Future<GoalCompletionResult> completeGoal(String goalId) async {
    completeCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated complete failure');
    return super.completeGoal(goalId);
  }
}

Goal _goal(
  String id,
  String title, {
  GoalStatus status = GoalStatus.active,
  double? targetAmount,
  double currentAmount = 0,
}) =>
    Goal(
      id: id,
      title: title,
      description: '',
      statId: 'health',
      status: status,
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      createdAt: DateTime(2026, 7, 1),
      completedAt: status == GoalStatus.completed ? DateTime(2026, 7, 2) : null,
    );

void main() {
  testWidgets('목표가 없으면 빈 상태 안내가 나온다', (tester) async {
    final storage = await createTestStorage();
    await pumpApp(tester, storage, const GoalsScreen());

    expect(find.textContaining('아직 설정한 목표가 없어요'), findsOneWidget);
  });

  testWidgets('진행중·달성 목표가 각 섹션으로 나뉘어 표시된다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '진행중 목표'));
    await storage.saveGoal(_goal('g2', '끝낸 목표', status: GoalStatus.completed));

    await pumpApp(tester, storage, const GoalsScreen());

    expect(find.text('진행중인 목표'), findsOneWidget);
    expect(find.text('달성한 목표'), findsOneWidget);
    expect(find.text('진행중 목표'), findsOneWidget);
    expect(find.text('끝낸 목표'), findsOneWidget);
  });

  testWidgets('비재무 목표는 직접 완료 버튼으로 달성 처리되고 보너스 XP를 준다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '직접 완료 목표'));

    await pumpApp(tester, storage, const GoalsScreen());

    await tester.tap(find.text('목표 달성'));
    await tester.pumpAndSettle();

    expect(find.text('"직접 완료 목표" 목표를 달성했어요!'), findsOneWidget);
    // 보너스 XP 100으로 레벨업이 일어나 레벨업·업적 다이얼로그가 연달아 뜬다 —
    // 확인 버튼이 남아있는 동안 모두 닫는다.
    while (find.text('확인').evaluate().isNotEmpty) {
      await tester.tap(find.text('확인').first);
      await tester.pumpAndSettle();
    }

    expect(storage.getGoal('g1')!.status, GoalStatus.completed);
    // 목표 완료 보너스 XP 100은 정확히 Lv.1→Lv.2 임계치라 레벨업하고 잔여 XP는 0.
    final health = storage.getStat('health')!;
    expect(health.level, 2);
    expect(health.currentXp, 0);
  });

  testWidgets('목표 메뉴에서 삭제하면 확인 후 목록에서 사라진다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '지울 목표'));

    await pumpApp(tester, storage, const GoalsScreen());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.textContaining('삭제할까요'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(storage.getGoals(), isEmpty);
  });

  testWidgets('목표 메뉴의 수정은 편집 화면으로 이동한다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '수정할 목표'));

    await pumpApp(tester, storage, const GoalsScreen());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    expect(find.text('목표 수정'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '수정할 목표'), findsOneWidget);
  });

  testWidgets('재무 목표는 직접 완료 버튼 없이 금액 진행률만 보여준다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '비상금', targetAmount: 1000000, currentAmount: 400000));

    await pumpApp(tester, storage, const GoalsScreen());

    expect(find.text('400,000원 / 1,000,000원'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '목표 달성'), findsNothing);
  });

  testWidgets('삭제 확인창이 뜨기 전에 같은 목표를 빠르게 두 번 눌러도 확인창은 하나만 뜨고 삭제는 한 번만 반영된다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '지울 목표'));
    late _GatedGoalsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const GoalsScreen(),
      overrides: [
        goalsProvider.overrideWith((ref) {
          notifier = _GatedGoalsListNotifier(ref.watch(storageServiceProvider), ref);
          return notifier;
        }),
      ],
    );

    // 확인창이 뜨기도 전에(동일 콜백을 두 번 직접 호출) — 두 번째 호출은
    // pending 가드에 막혀야 한다.
    final card = tester.widget<GoalProgressCard>(find.byType(GoalProgressCard));
    card.onDelete!();
    card.onDelete!();
    await tester.pumpAndSettle();

    expect(find.textContaining('삭제할까요'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pump();
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(notifier.deleteCalls, 1);
    expect(storage.getGoals(), isEmpty);
  });

  testWidgets('삭제가 실패하면 일반 오류 메시지만 보여주고 목록은 그대로 남는다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '지울 목표'));
    late _GatedGoalsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const GoalsScreen(),
      overrides: [
        goalsProvider.overrideWith((ref) {
          notifier = _GatedGoalsListNotifier(ref.watch(storageServiceProvider), ref);
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pump();
    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('목표를 삭제하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('StateError'), findsNothing);
    expect(storage.getGoals(), hasLength(1));
    expect(find.text('지울 목표'), findsOneWidget);
  });

  testWidgets('완료 버튼을 리빌드 전에 두 번 눌러도 완료 처리는 한 번만 일어난다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '완료할 목표'));
    late _GatedGoalsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const GoalsScreen(),
      overrides: [
        goalsProvider.overrideWith((ref) {
          notifier = _GatedGoalsListNotifier(ref.watch(storageServiceProvider), ref);
          return notifier;
        }),
      ],
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '목표 달성'),
    );
    button.onPressed!();
    button.onPressed!();

    expect(notifier.completeCalls, 1);

    notifier.gate.complete();
    await _pumpUntilDone(tester);
    while (find.text('확인').evaluate().isNotEmpty) {
      await tester.tap(find.text('확인').first);
      await _pumpUntilDone(tester, iterations: 3);
    }
    await _pumpUntilDone(tester, iterations: 3);

    expect(notifier.completeCalls, 1);
    expect(storage.getGoal('g1')!.status, GoalStatus.completed);
  });

  testWidgets('완료가 실패하면 일반 오류 메시지만 보여주고 목표는 진행중으로 남는다', (tester) async {
    setScreenSize(tester, const Size(600, 1600));
    final storage = await createTestStorage();
    await storage.saveGoal(_goal('g1', '완료할 목표'));
    late _GatedGoalsListNotifier notifier;
    await pumpApp(
      tester,
      storage,
      const GoalsScreen(),
      overrides: [
        goalsProvider.overrideWith((ref) {
          notifier = _GatedGoalsListNotifier(ref.watch(storageServiceProvider), ref);
          notifier.shouldThrow = true;
          return notifier;
        }),
      ],
    );

    await tester.tap(find.text('목표 달성'));
    notifier.gate.complete();
    await _pumpUntilDone(tester);

    expect(find.text('목표 완료 처리에 실패했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('StateError'), findsNothing);
    expect(storage.getGoal('g1')!.status, GoalStatus.active);
  });
}
