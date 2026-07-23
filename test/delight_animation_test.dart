import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/data/achievement_definitions.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/screens/quests_screen.dart';
import 'package:human_status/services/xp_service.dart';
import 'package:human_status/theme/app_theme.dart';
import 'package:human_status/widgets/achievement_dialog.dart';
import 'package:human_status/widgets/level_up_dialog.dart';
import 'package:human_status/widgets/quest_completion_button.dart';

import 'helpers/test_app.dart';

/// [QuestCompletionButton]/축하 다이얼로그만 단독으로 pump하기 위한
/// 최소 MaterialApp 껍데기. [reduceMotion]은 `MediaQueryData.disableAnimations`
/// 를 흉내내 접근성 모션 감소 경로를 재현한다.
Widget _harness(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
  );
}

/// 버튼 하나로 `showLevelUpDialog`/`showAchievementDialog`를 여는 화면 —
/// 다이얼로그가 실제 Navigator route로 열리는 경로를 그대로 재현한다.
Widget _dialogOpener(
  WidgetBuilder openBuilder, {
  bool reduceMotion = false,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: Builder(builder: openBuilder))),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
  );
}

Stat _healthStat() => Stat(id: 'health', name: '건강', icon: '💪');

/// [MaterialPageRoute]의 기본(Zoom) 전환도 FadeTransition/ScaleTransition을
/// 쓰기 때문에 `find.byType`을 스코프 없이 쓰면 우리 위젯과 무관한 것까지
/// 걸린다. [QuestCompletionButton]의 펄스는 그 위젯의 자손이므로
/// descendant로, 다이얼로그 등장 transition은 다이얼로그 콘텐츠를 감싸는
/// 조상이므로 ancestor로 좁혀서 찾는다.
Finder _scaleTransitionDescendantOf(Finder of) =>
    find.descendant(of: of, matching: find.byType(ScaleTransition));

Finder _fadeTransitionAncestorOf(Finder of) =>
    find.ancestor(of: of, matching: find.byType(FadeTransition));

Finder _scaleTransitionAncestorOf(Finder of) =>
    find.ancestor(of: of, matching: find.byType(ScaleTransition));

AchievementDefinition _achievement(String id, String title, String desc) =>
    AchievementDefinition(
      id: id,
      title: title,
      description: desc,
      icon: '🏅',
      isUnlocked: (_) => true,
    );

Quest _quest(
  String id,
  String title, {
  double xp = 30,
  QuestStatus status = QuestStatus.active,
}) {
  return Quest(
    id: id,
    title: title,
    description: '',
    statRewards: {'health': xp},
    status: status,
    createdAt: DateTime(2026, 7, 1),
  );
}

/// completeQuest 호출을 [gate]가 풀릴 때까지 붙잡아두고, [shouldThrow]가
/// true면 실패를 재현하는 QuestsNotifier — quests_screen_flow_test.dart의
/// `_GatedQuestsListNotifier`와 같은 패턴.
class _GatedQuestsNotifier extends QuestsNotifier {
  _GatedQuestsNotifier(super.storage, super.ref);

  int completeCalls = 0;
  bool shouldThrow = false;
  Completer<void> gate = Completer<void>();

  @override
  Future<QuestCompletionResult> completeQuest(String id) async {
    completeCalls++;
    await gate.future;
    if (shouldThrow) throw StateError('simulated complete failure');
    return super.completeQuest(id);
  }
}

/// completeQuest가 항상 didComplete: false인 안전한 무결과를 돌려주는
/// QuestsNotifier — 다른 화면이 먼저 완료/삭제해서 이 호출이 조용한 stale
/// no-op이 된 상황을 재현한다.
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

void main() {
  group('QuestCompletionButton', () {
    testWidgets('완료 버튼을 누르면 즉시 한 번만 콜백하고 펄스 중 처리 중 표시로 전환한다', (tester) async {
      final semantics = tester.ensureSemantics();
      int tapCount = 0;

      await tester.pumpWidget(
        _harness(
          QuestCompletionButton(
            onPressed: () => tapCount++,
            isCompleting: false,
          ),
        ),
      );

      await tester.tap(find.byType(QuestCompletionButton));
      expect(tapCount, 1);

      final scaleFinder = _scaleTransitionDescendantOf(
        find.byType(QuestCompletionButton),
      );

      // Ticker는 시작 직후가 아니라 "시작 후 첫 프레임"을 0 지점으로 잡으므로,
      // duration 없는 pump로 그 기준 프레임을 한 번 흘려보낸 뒤에야 이어지는
      // pump(duration)이 실제 경과 시간을 의미 있게 반영한다.
      await tester.pump();

      // 펄스 진행 중(90ms 중 40ms 지점) scale이 1보다 작아야 한다.
      await tester.pump(const Duration(milliseconds: 40));
      final midScale = tester.widget<ScaleTransition>(scaleFinder).scale.value;
      expect(midScale, lessThan(1.0));

      // 펄스가 끝날 때까지(forward+reverse) 흘려보낸다. reverse는 forward
      // 완료 콜백 안에서 새로 시작되는 별도 구간이라 고정 duration 한 번으로는
      // 못 미더울 수 있어 pumpAndSettle로 완전히 정착시킨다.
      await tester.pumpAndSettle();
      final settledScale = tester
          .widget<ScaleTransition>(scaleFinder)
          .scale
          .value;
      expect(settledScale, 1.0);

      // 부모가 isCompleting: true로 rebuild하면 처리중 표시로 바뀐다.
      // AnimatedSwitcher 크로스페이드가 opacity 0인 첫 프레임(ticker 시작
      // 기준 프레임)을 지나야 새 child의 semantics가 온전히 트리에 잡힌다.
      // pendingActionIndicator 내부 CircularProgressIndicator는 무한 반복
      // 애니메이션이라 pumpAndSettle은 끝나지 않으므로, 유한한 duration으로
      // 직접 두 프레임만 흘려보낸다.
      await tester.pumpWidget(
        _harness(
          QuestCompletionButton(onPressed: null, isCompleting: true),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.bySemanticsLabel('완료 처리 중'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      semantics.dispose();
    });

    testWidgets('완료 버튼 연타와 rebuild는 완료 콜백을 중복 실행하지 않는다', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        _harness(
          QuestCompletionButton(
            onPressed: () => tapCount++,
            isCompleting: false,
          ),
        ),
      );
      await tester.tap(find.byType(QuestCompletionButton));
      expect(tapCount, 1);

      // 첫 탭 직후 부모가 isCompleting: true로 바꾸면(pending 전환) 버튼이
      // 비활성화되어 다시 눌러도 콜백이 늘어나지 않아야 한다.
      await tester.pumpWidget(
        _harness(
          QuestCompletionButton(
            onPressed: () => tapCount++,
            isCompleting: true,
          ),
        ),
      );
      await tester.tap(find.byType(QuestCompletionButton));
      expect(tapCount, 1);
    });

    testWidgets('모션 감소 설정에서는 완료 버튼이 중간 scale 없이 즉시 최종 상태가 된다', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _harness(
          QuestCompletionButton(onPressed: () {}, isCompleting: false),
          reduceMotion: true,
        ),
      );

      await tester.tap(find.byType(QuestCompletionButton));
      await tester.pump();

      final scale = tester
          .widget<ScaleTransition>(
            _scaleTransitionDescendantOf(find.byType(QuestCompletionButton)),
          )
          .scale
          .value;
      expect(scale, 1.0);

      // 모션 감소 시 AnimatedSwitcher의 duration도 zero이므로, isCompleting
      // 전환 직후 별도 경과 시간 없는 첫 pump에서 바로 처리 중 semantics와
      // 비활성 상태가 나타나야 한다.
      await tester.pumpWidget(
        _harness(
          QuestCompletionButton(onPressed: null, isCompleting: true),
          reduceMotion: true,
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('완료 처리 중'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      semantics.dispose();
    });
  });

  group('LevelUpDialog', () {
    testWidgets('레벨업 다이얼로그는 페이드와 스케일 중간 프레임 후 최종 내용을 표시한다', (tester) async {
      final stats = [_healthStat()];
      const results = {'health': LevelUpResult(levelsGained: 1, newLevel: 2)};

      await tester.pumpWidget(
        _dialogOpener(
          (context) => ElevatedButton(
            onPressed: () => showLevelUpDialog(context, stats, results),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();

      final dialogFinder = find.byType(LevelUpDialog);
      final fadeFinder = _fadeTransitionAncestorOf(dialogFinder);
      final scaleFinder = _scaleTransitionAncestorOf(dialogFinder);

      // 전환 도중(220ms 중 100ms 지점) opacity/scale이 아직 최종값이 아니다.
      await tester.pump(const Duration(milliseconds: 100));
      final midFade = tester.widget<FadeTransition>(fadeFinder).opacity.value;
      final midScale = tester.widget<ScaleTransition>(scaleFinder).scale.value;
      expect(midFade, greaterThan(0));
      expect(midFade, lessThan(1));
      expect(midScale, greaterThan(0));
      expect(midScale, lessThan(1));

      await tester.pump(const Duration(milliseconds: 200));
      final endFade = tester.widget<FadeTransition>(fadeFinder).opacity.value;
      expect(endFade, 1.0);

      expect(find.text('🎉 레벨업!'), findsOneWidget);
      expect(find.text('💪 건강 스텟이 Lv.2(으)로 올랐습니다!'), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
    });

    testWidgets('레벨업 결과가 없으면 route를 열지 않는다', (tester) async {
      await tester.pumpWidget(
        _dialogOpener(
          (context) => ElevatedButton(
            onPressed: () => showLevelUpDialog(context, [_healthStat()], {
              'health': const LevelUpResult(levelsGained: 0, newLevel: 1),
            }),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('🎉 레벨업!'), findsNothing);
      expect(find.byType(LevelUpDialog), findsNothing);
    });

    testWidgets('여러 stat 레벨업은 한 다이얼로그에 모두 표시한다', (tester) async {
      final stats = [
        _healthStat(),
        Stat(id: 'intelligence', name: '지능', icon: '🧠'),
      ];
      const results = {
        'health': LevelUpResult(levelsGained: 1, newLevel: 2),
        'intelligence': LevelUpResult(levelsGained: 1, newLevel: 3),
      };

      await tester.pumpWidget(
        _dialogOpener(
          (context) => ElevatedButton(
            onPressed: () => showLevelUpDialog(context, stats, results),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(LevelUpDialog), findsOneWidget);
      expect(find.text('💪 건강 스텟이 Lv.2(으)로 올랐습니다!'), findsOneWidget);
      expect(find.text('🧠 지능 스텟이 Lv.3(으)로 올랐습니다!'), findsOneWidget);
    });
  });

  group('AchievementDialog', () {
    testWidgets('업적 다이얼로그는 여러 업적을 한 번만 열고 모두 읽을 수 있다', (tester) async {
      final achievements = [
        _achievement('a1', '첫 걸음', '첫 퀘스트를 완료했어요'),
        _achievement('a2', '꾸준함', '7일 연속 완료했어요'),
      ];

      await tester.pumpWidget(
        _dialogOpener(
          (context) => ElevatedButton(
            onPressed: () => showAchievementDialog(context, achievements),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AchievementDialog), findsOneWidget);
      expect(find.text('첫 걸음'), findsOneWidget);
      expect(find.text('첫 퀘스트를 완료했어요'), findsOneWidget);
      expect(find.text('꾸준함'), findsOneWidget);
      expect(find.text('7일 연속 완료했어요'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  group('모션 감소 접근성', () {
    testWidgets('모션 감소 설정에서는 레벨업과 업적 다이얼로그가 첫 pump에 최종 상태다', (tester) async {
      final stats = [_healthStat()];
      const results = {'health': LevelUpResult(levelsGained: 1, newLevel: 2)};

      await tester.pumpWidget(
        _dialogOpener((context) {
          return ElevatedButton(
            onPressed: () => showLevelUpDialog(context, stats, results),
            child: const Text('open'),
          );
        }, reduceMotion: true),
      );

      await tester.tap(find.text('open'));
      await tester.pump();

      // 모션 감소 시 페이드/스케일 wrapper 자체를 생략하므로 중간 프레임이
      // 존재하지 않고, 첫 pump에 바로 최종 콘텐츠가 보인다. (MaterialPageRoute의
      // 기본 Zoom 전환이 항상 만들어두는 FadeTransition/ScaleTransition과
      // 헷갈리지 않도록 다이얼로그 콘텐츠의 조상만 좁혀서 확인한다.)
      final levelUpDialog = find.byType(LevelUpDialog);
      expect(_fadeTransitionAncestorOf(levelUpDialog), findsNothing);
      expect(_scaleTransitionAncestorOf(levelUpDialog), findsNothing);
      expect(find.text('🎉 레벨업!'), findsOneWidget);
      expect(find.text('💪 건강 스텟이 Lv.2(으)로 올랐습니다!'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      final achievements = [_achievement('a1', '첫 걸음', '첫 퀘스트를 완료했어요')];
      await tester.pumpWidget(
        _dialogOpener((context) {
          return ElevatedButton(
            onPressed: () => showAchievementDialog(context, achievements),
            child: const Text('open2'),
          );
        }, reduceMotion: true),
      );

      await tester.tap(find.text('open2'));
      await tester.pump();

      final achievementDialog = find.byType(AchievementDialog);
      expect(_fadeTransitionAncestorOf(achievementDialog), findsNothing);
      expect(_scaleTransitionAncestorOf(achievementDialog), findsNothing);
      expect(find.text('🏆 업적 달성!'), findsOneWidget);
      expect(find.text('첫 걸음'), findsOneWidget);
    });
  });

  group('다이얼로그 생명주기/레이아웃', () {
    testWidgets('다이얼로그는 확인, back 또는 route 전환으로 닫혀도 미완료 ticker를 남기지 않는다', (
      tester,
    ) async {
      final stats = [_healthStat()];
      const results = {'health': LevelUpResult(levelsGained: 1, newLevel: 2)};

      await tester.pumpWidget(
        _dialogOpener(
          (context) => ElevatedButton(
            onPressed: () => showLevelUpDialog(context, stats, results),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      // 전환 애니메이션이 끝나기 전(220ms 중 50ms 지점)에 route를 pop한다.
      await tester.pump(const Duration(milliseconds: 50));

      final dialogElement = tester.element(find.byType(LevelUpDialog));
      Navigator.of(dialogElement).pop();

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('텍스트 확대와 작은 화면에서도 축하 다이얼로그가 overflow하지 않는다', (tester) async {
      setScreenSize(tester, const Size(320, 480));
      final achievements = List.generate(
        6,
        (i) => _achievement('a$i', '업적 제목 $i', '아주 길게 설명하는 업적 설명 텍스트입니다 $i'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () =>
                      showAchievementDialog(context, achievements),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AchievementDialog), findsOneWidget);
    });
  });

  group('기존 완료 흐름 회귀', () {
    testWidgets('퀘스트 완료 성공은 스낵바 후 레벨업과 업적 다이얼로그를 순서대로 보여준다', (tester) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '운동 30분', xp: 120));

      await pumpApp(tester, storage, const QuestsScreen());
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(find.text('"운동 30분" 완료!'), findsOneWidget);
      expect(find.text('🎉 레벨업!'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(find.text('🏆 업적 달성!'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(find.text('🎉 레벨업!'), findsNothing);
      expect(find.text('🏆 업적 달성!'), findsNothing);
    });

    testWidgets('didComplete가 false이면 펜딩 상태를 해제하고 성공 다이얼로그를 열지 않는다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '물 마시기'));

      await pumpApp(
        tester,
        storage,
        const QuestsScreen(),
        overrides: [
          questsProvider.overrideWith(
            (ref) => _StaleNoOpQuestsNotifier(
              ref.watch(storageServiceProvider),
              ref,
            ),
          ),
        ],
      );

      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(find.text('🎉 레벨업!'), findsNothing);
      expect(find.text('🏆 업적 달성!'), findsNothing);
      // pending이 풀려 버튼이 다시 눌릴 수 있는 상태로 돌아온다.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('완료 실패는 성공 다이얼로그를 열지 않고 재시도 가능한 상태로 돌아간다', (tester) async {
      final storage = await createTestStorage();
      await storage.saveQuest(_quest('q1', '완료할 퀘스트'));
      late _GatedQuestsNotifier notifier;

      await pumpApp(
        tester,
        storage,
        const QuestsScreen(),
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

      await tester.tap(find.text('완료'));
      notifier.gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('퀘스트 완료 처리에 실패했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.text('🎉 레벨업!'), findsNothing);
      expect(find.text('🏆 업적 달성!'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      notifier.shouldThrow = false;
      notifier.gate = Completer<void>();
      await tester.tap(find.text('완료'));
      notifier.gate.complete();
      await tester.pumpAndSettle();
      while (find.text('확인').evaluate().isNotEmpty) {
        await tester.tap(find.text('확인').first);
        await tester.pumpAndSettle();
      }

      expect(notifier.completeCalls, 2);
      expect(storage.getQuest('q1')!.status, QuestStatus.completed);
    });

    testWidgets('홈 상단 ActionHubCard와 남은 퀘스트 목록은 동일한 완료 버튼 피드백을 사용한다', (
      tester,
    ) async {
      setScreenSize(tester, const Size(600, 1600));
      final storage = await createTestStorage();
      await storage.saveQuest(
        Quest(
          id: 'hub',
          title: '허브 강조 퀘스트',
          description: '',
          statRewards: {'health': 5},
          goalId: 'some-goal',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await storage.saveQuest(_quest('r1', '남은 퀘스트 1'));
      await storage.saveQuest(_quest('r2', '남은 퀘스트 2'));

      await pumpApp(tester, storage, const DashboardScreen());

      // 허브의 강조 카드 하나 + 남은 목록 2개, 총 3개가 같은 위젯 타입을 쓴다.
      expect(find.byType(QuestCompletionButton), findsNWidgets(3));
    });
  });
}
