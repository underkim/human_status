import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/banksalad_import_screen.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/screens/finance_asset_tab_view.dart';
import 'package:human_status/screens/financial_planning_wizard_screen.dart';
import 'package:human_status/screens/goal_form_screen.dart';
import 'package:human_status/screens/goals_screen.dart';
import 'package:human_status/screens/insights_screen.dart';
import 'package:human_status/screens/more_screen.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/screens/quest_form_screen.dart';
import 'package:human_status/screens/quests_screen.dart';
import 'package:human_status/screens/report_screen.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/widgets/page_content_bounds.dart';

import 'helpers/test_app.dart';

const _compact = Size(400, 800);
const _wide = Size(2560, 1440);

/// Asserts the first [PageContentBounds]'s inner [ConstrainedBox] — the box
/// that actually carries the width cap, since [PageContentBounds] itself
/// resolves to [Align], whose render box always fills the space its parent
/// gives it — is capped at [maxWidth] and centered once the screen is wider
/// than that cap, and simply fills the screen width below the cap (a no-op
/// on compact/mobile widths).
void _expectBounded(WidgetTester tester, double maxWidth, double screenWidth) {
  final rect = tester.getRect(
    find
        .descendant(
          of: find.byType(PageContentBounds).first,
          matching: find.byType(ConstrainedBox),
        )
        .first,
  );
  if (screenWidth <= maxWidth) {
    expect(rect.width, closeTo(screenWidth, 0.5));
    expect(rect.left, closeTo(0, 0.5));
  } else {
    expect(rect.width, closeTo(maxWidth, 0.5));
    final expectedLeft = (screenWidth - maxWidth) / 2;
    expect(rect.left, closeTo(expectedLeft, 0.5));
  }
}

void main() {
  group('PageContentBounds', () {
    testWidgets('컴팩트 너비에서는 화면 전체 너비를 그대로 채운다', (tester) async {
      tester.view.physicalSize = _compact;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageContentBounds(
              maxWidth: PageContentBounds.wide,
              child: Container(key: const Key('inner'), color: Colors.red),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byKey(const Key('inner')));
      expect(rect.width, closeTo(_compact.width, 0.5));
      expect(rect.left, closeTo(0, 0.5));
    });

    testWidgets('넓은 너비에서는 maxWidth로 잘리고 가운데 정렬된다', (tester) async {
      tester.view.physicalSize = _wide;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageContentBounds(
              maxWidth: PageContentBounds.wide,
              child: Container(key: const Key('inner'), color: Colors.red),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byKey(const Key('inner')));
      expect(rect.width, closeTo(PageContentBounds.wide, 0.5));
      final expectedLeft = (_wide.width - PageContentBounds.wide) / 2;
      expect(rect.left, closeTo(expectedLeft, 0.5));
    });

    testWidgets('짧은 콘텐츠도 세로 중앙으로 밀지 않고 상단에 둔다', (tester) async {
      tester.view.physicalSize = _wide;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageContentBounds(
              maxWidth: PageContentBounds.wide,
              child: SizedBox(key: const Key('short-content'), height: 100),
            ),
          ),
        ),
      );

      expect(tester.getTopLeft(find.byKey(const Key('short-content'))).dy, 0);
    });
  });

  group('온보딩 — 컴팩트/와이드 폭 제약과 조작 가능성', () {
    testWidgets('컴팩트 400x800에서 다음 버튼이 오버플로우 없이 눌린다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const OnboardingScreen());

      _expectBounded(tester, PageContentBounds.narrow, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('먼저 키우고 싶은 영역을 골라주세요'), findsOneWidget);
    });

    testWidgets('와이드 2560x1440에서 본문이 960 근처로 잘리고 가운데 정렬되며 계속 조작 가능하다', (
      tester,
    ) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const OnboardingScreen());

      _expectBounded(tester, PageContentBounds.narrow, _wide.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('먼저 키우고 싶은 영역을 골라주세요'), findsOneWidget);
    });
  });

  group('대시보드 — 컴팩트/와이드 폭 제약과 조작 가능성', () {
    Future<void> pumpDashboard(WidgetTester tester) async {
      final storage = await createTestStorage();
      await storage.saveQuest(
        Quest(
          id: 'q1',
          title: '스트레칭',
          description: '',
          statRewards: {'health': 10},
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await pumpApp(tester, storage, const DashboardScreen());
    }

    testWidgets('컴팩트 400x800에서 완료 버튼이 오버플로우 없이 눌린다', (tester) async {
      setScreenSize(tester, _compact);
      await pumpDashboard(tester);

      _expectBounded(tester, PageContentBounds.wide, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, '완료'));
      await tester.pumpAndSettle();
      expect(find.text('"스트레칭" 완료!'), findsOneWidget);
    });

    testWidgets(
      '와이드 2560x1440에서 본문이 1200 근처로 잘리고 가운데 정렬되며 완료 버튼이 카드 옆에 붙어 조작 가능하다',
      (tester) async {
        setScreenSize(tester, _wide);
        await pumpDashboard(tester);

        _expectBounded(tester, PageContentBounds.wide, _wide.width);
        expect(tester.takeException(), isNull);

        final buttonRect = tester.getRect(
          find.widgetWithText(FilledButton, '완료').first,
        );
        // 완료 버튼이 창의 오른쪽 가장자리(2560 근처)가 아니라 잘린 본문
        // 폭(가운데 1200 영역) 안에 있어야 한다.
        final bodyRect = tester.getRect(
          find
              .descendant(
                of: find.byType(PageContentBounds).first,
                matching: find.byType(ConstrainedBox),
              )
              .first,
        );
        expect(buttonRect.right, lessThanOrEqualTo(bodyRect.right + 0.5));

        await tester.tap(find.widgetWithText(FilledButton, '완료').first);
        await tester.pumpAndSettle();
        expect(find.text('"스트레칭" 완료!'), findsOneWidget);
      },
    );
  });

  group('퀘스트 화면 — 컴팩트/와이드 폭 제약과 조작 가능성', () {
    Future<void> pumpQuests(WidgetTester tester) async {
      final storage = await createTestStorage();
      await storage.saveQuest(
        Quest(
          id: 'q1',
          title: '스트레칭',
          description: '',
          statRewards: {'health': 10},
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await pumpApp(tester, storage, const QuestsScreen());
    }

    testWidgets('컴팩트 400x800에서 탭 전환과 완료가 오버플로우 없이 동작한다', (tester) async {
      setScreenSize(tester, _compact);
      await pumpQuests(tester);

      _expectBounded(tester, PageContentBounds.wide, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, '완료'));
      await tester.pumpAndSettle();
      expect(find.text('"스트레칭" 완료!'), findsOneWidget);
    });

    testWidgets('와이드 2560x1440에서 본문이 1200 근처로 잘리고 가운데 정렬되며 탭·완료가 계속 동작한다', (
      tester,
    ) async {
      setScreenSize(tester, _wide);
      await pumpQuests(tester);

      _expectBounded(tester, PageContentBounds.wide, _wide.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('완료 (0)'));
      await tester.pumpAndSettle();
      expect(find.text('스트레칭'), findsNothing);

      await tester.tap(find.text('진행중 (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '완료'));
      await tester.pumpAndSettle();
      expect(find.text('"스트레칭" 완료!'), findsOneWidget);
    });
  });

  group('목표 화면 — 컴팩트/와이드 폭 제약과 조작 가능성', () {
    Future<void> pumpGoals(WidgetTester tester) async {
      final storage = await createTestStorage();
      await storage.saveGoal(
        Goal(
          id: 'g1',
          title: '건강해지기',
          description: '',
          statId: 'health',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await pumpApp(tester, storage, const GoalsScreen());
    }

    testWidgets('컴팩트 400x800에서 목표 카드가 오버플로우 없이 보인다', (tester) async {
      setScreenSize(tester, _compact);
      await pumpGoals(tester);

      _expectBounded(tester, PageContentBounds.wide, _compact.width);
      expect(tester.takeException(), isNull);
      expect(find.text('건강해지기'), findsOneWidget);
    });

    testWidgets('와이드 2560x1440에서 본문이 1200 근처로 잘리고 가운데 정렬되며 FAB로 새 목표를 열 수 있다', (
      tester,
    ) async {
      setScreenSize(tester, _wide);
      await pumpGoals(tester);

      _expectBounded(tester, PageContentBounds.wide, _wide.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('목표 추가'), findsOneWidget);
    });
  });

  group('설정 화면 — 컴팩트/와이드 폭 제약', () {
    testWidgets('컴팩트 400x800에서 목록이 오버플로우 없이 스크롤된다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const SettingsScreen());

      _expectBounded(tester, PageContentBounds.wide, _compact.width);
      expect(tester.takeException(), isNull);
      // 자동 백업 섹션이 추가되며 목록이 늘어나 '데이터 및 개인정보'가 이
      // 좁은/짧은 뷰포트에서는 스크롤해야만 보인다.
      await tester.scrollUntilVisible(find.text('데이터 및 개인정보'), 300);
      expect(tester.takeException(), isNull);
      expect(find.text('데이터 및 개인정보'), findsOneWidget);
    });

    testWidgets('와이드 2560x1440에서 본문이 1200 근처로 잘리고 가운데 정렬된다', (tester) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const SettingsScreen());

      _expectBounded(tester, PageContentBounds.wide, _wide.width);
      expect(tester.takeException(), isNull);
      expect(find.text('데이터 및 개인정보'), findsOneWidget);
    });
  });

  group('더보기 화면 — 컴팩트/와이드 폭 제약과 목적지 이동', () {
    testWidgets('컴팩트 400x800에서 세 행이 각 목적지로 이동한다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const MoreScreen());

      _expectBounded(tester, PageContentBounds.wide, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('리포트'));
      await tester.pumpAndSettle();
      expect(find.text('요약'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('통계'));
      await tester.pumpAndSettle();
      expect(find.text('완료 기록'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      // 자동 백업 섹션이 추가되며 목록이 늘어나 '데이터 및 개인정보'가 이
      // 좁은/짧은 뷰포트에서는 스크롤해야만 보인다.
      await tester.scrollUntilVisible(find.text('데이터 및 개인정보'), 300);
      expect(find.text('데이터 및 개인정보'), findsOneWidget);
    });

    testWidgets('와이드 2560x1440에서 본문이 1200 근처로 잘리고 가운데 정렬되며 세 행 모두 이동 가능하다', (
      tester,
    ) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const MoreScreen());

      _expectBounded(tester, PageContentBounds.wide, _wide.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('리포트'));
      await tester.pumpAndSettle();
      expect(find.text('요약'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('통계'));
      await tester.pumpAndSettle();
      expect(find.text('완료 기록'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      expect(find.text('데이터 및 개인정보'), findsOneWidget);
    });
  });

  group('재무 화면 — 컴팩트/와이드 폭 제약과 탭 전환', () {
    testWidgets('컴팩트 400x800에서 탭 전환이 오버플로우 없이 동작한다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(
        tester,
        storage,
        const Scaffold(body: FinanceAssetTabView()),
      );

      _expectBounded(tester, PageContentBounds.wide, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('자산현황'));
      await tester.pumpAndSettle();
      expect(find.textContaining('아직 가져온 자산 현황이 없어요'), findsOneWidget);

      await tester.tap(find.text('거래내역'));
      await tester.pumpAndSettle();
      expect(find.text('이번 달'), findsOneWidget);
    });

    testWidgets('와이드 2560x1440에서 본문이 1200 근처로 잘리고 가운데 정렬되며 탭 전환·스크롤이 계속 동작한다', (
      tester,
    ) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(
        tester,
        storage,
        const Scaffold(body: FinanceAssetTabView()),
      );

      _expectBounded(tester, PageContentBounds.wide, _wide.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('자산현황'));
      await tester.pumpAndSettle();
      expect(find.textContaining('아직 가져온 자산 현황이 없어요'), findsOneWidget);

      await tester.tap(find.text('거래내역'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('이번 달'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('리포트 화면 — 컴팩트/와이드 폭 제약과 기간 전환', () {
    testWidgets('컴팩트 400x800에서 주간/월간 전환이 오버플로우 없이 동작한다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const ReportScreen());

      _expectBounded(tester, PageContentBounds.wide, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('월간'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('와이드 2560x1440에서 본문이 1200 근처로 잘리고 가운데 정렬되며 기간 전환이 계속 동작한다', (
      tester,
    ) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const ReportScreen());

      _expectBounded(tester, PageContentBounds.wide, _wide.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('월간'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('통계 화면 — 컴팩트/와이드 폭 제약', () {
    testWidgets('컴팩트 400x800에서 스크롤 가능하고 오버플로우가 없다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const InsightsScreen());

      _expectBounded(tester, PageContentBounds.wide, _compact.width);
      expect(tester.takeException(), isNull);
      expect(find.text('완료 기록'), findsOneWidget);

      await tester.drag(find.text('완료 기록'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('와이드 2560x1440에서 본문이 1200 근처로 잘리고 가운데 정렬된다', (tester) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const InsightsScreen());

      _expectBounded(tester, PageContentBounds.wide, _wide.width);
      expect(tester.takeException(), isNull);
      expect(find.text('완료 기록'), findsOneWidget);
    });
  });

  group('목표 폼 — 컴팩트/와이드 폭 제약과 제출 가능성', () {
    testWidgets('컴팩트 400x800에서 저장 버튼이 오버플로우 없이 눌린다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const GoalFormScreen());

      _expectBounded(tester, PageContentBounds.narrow, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.widgetWithText(TextFormField, '목표'), '새 목표');
      await tester.tap(find.widgetWithText(FilledButton, '추가하기'));
      // 제출 중 계속 애니메이션하는 CircularProgressIndicator가 남아 있어
      // pumpAndSettle이 멈추지 않는다 — goal_form_screen_test.dart와 동일하게
      // 고정된 프레임 수만큼만 진행시킨다.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '와이드 2560x1440에서 본문이 960 근처로 잘리고 가운데 정렬되며 저장 버튼이 창 오른쪽 끝이 아닌 잘린 폭 안에 있다',
      (tester) async {
        setScreenSize(tester, _wide);
        final storage = await createTestStorage();
        await pumpApp(tester, storage, const GoalFormScreen());

        _expectBounded(tester, PageContentBounds.narrow, _wide.width);
        expect(tester.takeException(), isNull);

        final buttonRect = tester.getRect(
          find.widgetWithText(FilledButton, '추가하기'),
        );
        final bodyRect = tester.getRect(
          find
              .descendant(
                of: find.byType(PageContentBounds).first,
                matching: find.byType(ConstrainedBox),
              )
              .first,
        );
        expect(buttonRect.right, lessThanOrEqualTo(bodyRect.right + 0.5));
        // 좁은 콘텐츠라도 세로 중앙이 아니라 상단 근처에서 시작해야 한다.
        expect(tester.getTopLeft(find.byType(Form)).dy, lessThan(200));

        await tester.enterText(
          find.widgetWithText(TextFormField, '목표'),
          '새 목표',
        );
        await tester.tap(find.widgetWithText(FilledButton, '추가하기'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('퀘스트 폼 — 컴팩트/와이드 폭 제약과 제출 가능성', () {
    testWidgets('컴팩트 400x800에서 저장 버튼이 오버플로우 없이 눌린다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const QuestFormScreen());

      _expectBounded(tester, PageContentBounds.narrow, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.widgetWithText(TextFormField, '제목'), '새 퀘스트');
      await tester.tap(find.widgetWithText(FilledButton, '추가하기'));
      await tester.pumpAndSettle();
    });

    testWidgets('와이드 2560x1440에서 본문이 960 근처로 잘리고 가운데 정렬되며 저장 버튼이 잘린 폭 안에 있다', (
      tester,
    ) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const QuestFormScreen());

      _expectBounded(tester, PageContentBounds.narrow, _wide.width);
      expect(tester.takeException(), isNull);

      final buttonRect = tester.getRect(
        find.widgetWithText(FilledButton, '추가하기'),
      );
      final bodyRect = tester.getRect(
        find
            .descendant(
              of: find.byType(PageContentBounds).first,
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(buttonRect.right, lessThanOrEqualTo(bodyRect.right + 0.5));

      await tester.enterText(find.widgetWithText(TextFormField, '제목'), '새 퀘스트');
      await tester.tap(find.widgetWithText(FilledButton, '추가하기'));
      await tester.pumpAndSettle();
    });
  });

  group('뱅크샐러드 가져오기 화면 — 컴팩트/와이드 폭 제약', () {
    testWidgets('컴팩트 400x800에서 파일 선택 버튼이 오버플로우 없이 보인다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const BanksaladImportScreen());

      _expectBounded(tester, PageContentBounds.narrow, _compact.width);
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(OutlinedButton, '파일 선택'), findsOneWidget);
    });

    testWidgets('와이드 2560x1440에서 본문이 960 근처로 잘리고 가운데 정렬된다', (tester) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const BanksaladImportScreen());

      _expectBounded(tester, PageContentBounds.narrow, _wide.width);
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(OutlinedButton, '파일 선택'), findsOneWidget);
      // 좁은 콘텐츠라도 세로 중앙이 아니라 상단 근처에서 시작해야 한다.
      expect(
        tester.getTopLeft(find.widgetWithText(OutlinedButton, '파일 선택')).dy,
        lessThan(200),
      );
    });
  });

  group('장기 재무계획 마법사 — 컴팩트/와이드 폭 제약과 스텝 진행', () {
    testWidgets('컴팩트 400x800에서 다음 버튼이 오버플로우 없이 눌린다', (tester) async {
      setScreenSize(tester, _compact);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const FinancialPlanningWizardScreen());

      _expectBounded(tester, PageContentBounds.narrow, _compact.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, '다음').hitTestable());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('와이드 2560x1440에서 본문이 960 근처로 잘리고 가운데 정렬되며 스텝 진행이 계속 동작한다', (
      tester,
    ) async {
      setScreenSize(tester, _wide);
      final storage = await createTestStorage();
      await pumpApp(tester, storage, const FinancialPlanningWizardScreen());

      _expectBounded(tester, PageContentBounds.narrow, _wide.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, '다음').hitTestable());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
