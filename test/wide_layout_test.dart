import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/screens/goals_screen.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/screens/quests_screen.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/widgets/page_content_bounds.dart';

import 'helpers/test_app.dart';

const _compact = Size(400, 800);
const _wide = Size(2560, 1440);

/// Asserts the first [PageContentBounds]'s inner [ConstrainedBox] — the box
/// that actually carries the width cap, since [PageContentBounds] itself
/// resolves to [Center], whose render box always fills the space its parent
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
}
