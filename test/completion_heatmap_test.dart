import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/theme/app_theme.dart';
import 'package:human_status/widgets/completion_heatmap.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Map<DateTime, int> _fourWeeks({Map<DateTime, int> overrides = const {}}) {
  // 2026-06-22(월)~2026-07-19(일) 완전한 4주.
  final result = <DateTime, int>{};
  for (var d = DateTime(2026, 6, 22); !d.isAfter(DateTime(2026, 7, 19)); d = d.add(const Duration(days: 1))) {
    result[DateTime(d.year, d.month, d.day)] = overrides[DateTime(d.year, d.month, d.day)] ?? 0;
  }
  return result;
}

void main() {
  testWidgets('주 수만큼 열이 생기고 각 날짜 셀이 렌더된다', (tester) async {
    await tester.pumpWidget(_wrap(CompletionHeatmap(countsByDay: _fourWeeks())));
    await tester.pumpAndSettle();

    // 4주 * 7일 = 28개 셀 + 범례 5개 = 33개 Container(장식 있는 것).
    final cells = find.byType(Container);
    expect(cells, findsWidgets);
    // 범례 라벨.
    expect(find.text('적음'), findsOneWidget);
    expect(find.text('많음'), findsOneWidget);
    // 요일 라벨(월/수/금/일).
    expect(find.text('월'), findsOneWidget);
    expect(find.text('일'), findsOneWidget);
  });

  testWidgets('완료가 있는 날 셀의 툴팁에 완료 수가 담긴다', (tester) async {
    final counts = _fourWeeks(overrides: {DateTime(2026, 7, 14): 3});
    await tester.pumpWidget(_wrap(CompletionHeatmap(countsByDay: counts)));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('7/14 · 3개 완료'),
      findsOneWidget,
    );
  });
}
