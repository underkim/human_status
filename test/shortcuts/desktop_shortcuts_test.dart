// Phase 6 Part C — 데스크톱 단축키가 실제로 동작하는지, 그리고 모바일
// 플랫폼에서는 완전히 비활성인지 확인한다.
//
// `flutter test`의 기본 `defaultTargetPlatform`은 android라서, 데스크톱
// 전용 코드 경로를 켜려면 각 테스트에서 명시적으로
// `debugDefaultTargetPlatformOverride`를 지정해야 한다. `addTearDown`으로
// 되돌리면 flutter_test의 `_verifyInvariants`가 테스트 본문이 끝나기 전에
// (addTearDown 큐가 비워지기 전에) 먼저 실행돼 "foundation debug
// variable" 오류를 내므로, 본문 안에서 try/finally로 직접 되돌린다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/home_shell.dart';
import 'package:human_status/screens/quest_form_screen.dart';
import 'package:human_status/screens/quests_screen.dart';

import '../helpers/test_app.dart';

Future<void> _runWithPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final original = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = original;
  }
}

Future<void> _pressChord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  group('탭 전환 (Ctrl+1..5)', () {
    testWidgets('Windows/Linux에서 Ctrl+2는 퀘스트 탭으로 전환한다', (tester) async {
      await _runWithPlatform(TargetPlatform.linux, () async {
        final storage = await createTestStorage();
        await pumpApp(tester, storage, const HomeShell());
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsOneWidget);
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          0,
        );

        await _pressChord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.digit2,
        );

        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          1,
        );
      });
    });

    testWidgets('macOS에서는 Ctrl이 아니라 Cmd(meta)+2가 전환한다', (tester) async {
      await _runWithPlatform(TargetPlatform.macOS, () async {
        final storage = await createTestStorage();
        await pumpApp(tester, storage, const HomeShell());
        await tester.pumpAndSettle();

        // Ctrl+2(잘못된 modifier)는 아무 효과가 없다.
        await _pressChord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.digit2,
        );
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          0,
        );

        await _pressChord(
          tester,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.digit2,
        );
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          1,
        );
      });
    });

    testWidgets('Android에서는 Ctrl+2가 아무 효과가 없다', (tester) async {
      await _runWithPlatform(TargetPlatform.android, () async {
        final storage = await createTestStorage();
        await pumpApp(tester, storage, const HomeShell());
        await tester.pumpAndSettle();

        await _pressChord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.digit2,
        );

        // compact 폭이 아니라도(테스트 기본 폭은 medium) 최소한 선택된
        // 탭이 그대로인지로 무효과를 확인한다.
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          0,
        );
      });
    });
  });

  group('퀘스트 화면 단축키', () {
    testWidgets('Ctrl+F는 검색을 열고 입력에 포커스를 준다', (tester) async {
      await _runWithPlatform(TargetPlatform.linux, () async {
        final storage = await createTestStorage();
        await pumpApp(tester, storage, const QuestsScreen());
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);

        await _pressChord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyF,
        );

        expect(find.byType(TextField), findsOneWidget);
        expect(tester.testTextInput.hasAnyClients, isTrue);
      });
    });

    testWidgets('검색이 이미 열려 있을 때 Ctrl+F는 입력에 포커스만 되돌린다', (tester) async {
      await _runWithPlatform(TargetPlatform.linux, () async {
        final storage = await createTestStorage();
        await pumpApp(tester, storage, const QuestsScreen());
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('퀘스트 검색'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '물');
        await tester.pump();

        // 검색이 이미 열려 있는 상태에서 다시 Ctrl+F를 눌러도 예외 없이
        // 같은 입력에 포커스를 유지한다(재오픈으로 검색어를 지우지 않음).
        await _pressChord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyF,
        );

        expect(tester.testTextInput.hasAnyClients, isTrue);
        // 검색어는 그대로 유지된다 — 재오픈이 아니라 포커스만 이동했다.
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller?.text, '물');
      });
    });

    testWidgets('Ctrl+N은 새 퀘스트 화면으로 이동한다', (tester) async {
      await _runWithPlatform(TargetPlatform.linux, () async {
        final storage = await createTestStorage();
        final navigatorKey = GlobalKey<NavigatorState>();
        await pumpApp(
          tester,
          storage,
          Navigator(
            key: navigatorKey,
            onGenerateRoute: (_) =>
                MaterialPageRoute(builder: (_) => const QuestsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await _pressChord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyN,
        );

        expect(find.byType(QuestFormScreen), findsOneWidget);
      });
    });

    testWidgets('Escape는 검색이 열려 있을 때만 검색을 닫는다', (tester) async {
      await _runWithPlatform(TargetPlatform.linux, () async {
        final storage = await createTestStorage();
        await storage.saveQuest(
          Quest(
            id: 'q1',
            title: '물 마시기',
            description: '',
            statRewards: const {'health': 10},
            status: QuestStatus.active,
            source: QuestSource.manual,
            createdAt: DateTime(2026, 7, 1),
          ),
        );
        await pumpApp(tester, storage, const QuestsScreen());
        await tester.pumpAndSettle();

        // 검색이 닫혀 있을 때 Escape는 아무 것도 하지 않는다(예외 없음).
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('퀘스트'), findsOneWidget);

        await tester.tap(find.byTooltip('퀘스트 검색'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
        expect(find.text('퀘스트'), findsOneWidget);
      });
    });
  });
}
