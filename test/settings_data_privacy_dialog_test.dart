import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/settings_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('데이터 및 개인정보 다이얼로그는 로컬 저장·백업 제외·웹 경고를 모두 보여주고 데이터를 바꾸지 않는다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    await storage.saveClaudeApiKey('sk-ant-untouched');
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '건드리면 안 되는 퀘스트',
        description: '',
        statRewards: {'health': 10},
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    await pumpApp(tester, storage, const SettingsScreen());

    expect(find.text('데이터 및 개인정보'), findsOneWidget);
    expect(find.text('기기에 저장 · API 키는 백업에서 제외'), findsOneWidget);

    await tester.tap(find.text('데이터 및 개인정보'));
    await tester.pumpAndSettle();

    // 사실 진술 네 가지가 모두 보인다.
    expect(find.textContaining('계정이나 서버 동기화 없이'), findsOneWidget);
    expect(find.textContaining('백업 파일에는 포함되지 않아요'), findsOneWidget);
    expect(find.textContaining('먼저 내보내두는 걸 권장'), findsOneWidget);
    expect(find.textContaining('웹에서는 API 키 보호 수준'), findsOneWidget);

    // 닫기 버튼으로 명확하게 닫을 수 있다.
    final closeButton = find.widgetWithText(FilledButton, '닫기');
    expect(closeButton, findsOneWidget);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(find.text('데이터 및 개인정보'), findsOneWidget);
    expect(find.textContaining('계정이나 서버 동기화 없이'), findsNothing);

    // 정보 열람/닫기만으로는 어떤 데이터도 바뀌지 않는다.
    expect(storage.claudeApiKey, 'sk-ant-untouched');
    expect(storage.getQuests().single.title, '건드리면 안 되는 퀘스트');
  });
}
