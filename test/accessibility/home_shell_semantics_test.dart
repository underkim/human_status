import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/screens/home_shell.dart';

import '../helpers/test_app.dart';
import 'a11y_harness.dart';

void main() {
  group('HomeShell 탭 semantics', () {
    testWidgets('IndexedStack의 비활성 탭은 위젯 트리엔 남아 있지만 semantics tree에서는 제외된다', (
      tester,
    ) async {
      final storage = await createTestStorage();
      final handle = tester.ensureSemantics();

      await pumpApp(tester, storage, const HomeShell());
      await tester.pumpAndSettle();

      // '더보기' 탭(index 4) 안의 문구는 nav 목적지 라벨과 겹치지 않는
      // 고유 문자열이라 위젯/semantics 트리를 명확히 구분할 수 있다. 기본
      // 선택 탭(홈, index 0)에서는 이 문구가 위젯 트리에는 빌드돼 있지만
      // (IndexedStack이 비활성 자식도 모두 빌드) 화면에 그려지거나
      // 보조기술에 노출되지는 않는다.
      // find.text의 기본 skipOffstage:true 자체가 이미 IndexedStack의
      // 비활성 자식을 건너뛰므로, "빌드는 됐다"를 확인하려면 명시적으로
      // skipOffstage:false를 줘야 한다 — semantics tree 부재라는 이
      // 테스트의 실제 관심사는 별도로 find.bySemanticsLabel로 확인한다.
      const moreScreenMarker = 'API 키 · 알림 · 백업 · 초기화';
      expect(find.text(moreScreenMarker, skipOffstage: false), findsOneWidget);
      expect(findBySemanticsLabelContaining(moreScreenMarker), findsNothing);

      // 더보기 탭으로 전환한다. '더보기' 텍스트는 nav 목적지 라벨과
      // (비활성인) MoreScreen AppBar 제목 양쪽에 있으므로, nav 쪽만
      // 명시적으로 짚어 탭한다.
      final navDestinationLabel = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('더보기'),
      );
      await tester.tap(navDestinationLabel);
      await tester.pumpAndSettle();

      expect(find.text(moreScreenMarker), findsOneWidget);
      expect(findBySemanticsLabelContaining(moreScreenMarker), findsOneWidget);

      handle.dispose();
    });
  });
}
