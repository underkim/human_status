import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/screens/settings_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('데이터 및 개인정보 다이얼로그는 로컬 저장·백업 제외·웹 경고를 모두 보여주고 데이터를 바꾸지 않는다', (
    tester,
  ) async {
    // 자동 백업 섹션이 추가되며 목록이 길어져, '데이터 및 개인정보'가 기본
    // 뷰포트의 가상화 캐시 범위 밖으로 밀려난다 — 처음부터 전부 mount되도록
    // 화면을 세로로 넉넉하게 잡는다.
    setScreenSize(tester, const Size(800, 1400));
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

    await tester.ensureVisible(find.text('데이터 및 개인정보'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데이터 및 개인정보'));
    await tester.pumpAndSettle();

    // 사실 진술 다섯 가지가 모두 보인다.
    expect(find.textContaining('계정이나 서버 동기화 없이'), findsOneWidget);
    // 자동 백업 문단도 "...백업 파일에는 포함되지 않아요"로 끝나 textContaining만으로는
    // 두 문단이 함께 걸리므로, API 키 문단에서만 나오는 구절로 특정한다.
    expect(
      find.textContaining('Linux libsecret)에 저장되고, 백업 파일에는 포함되지 않아요'),
      findsOneWidget,
    );
    expect(find.textContaining('먼저 내보내두는 걸 권장'), findsOneWidget);
    expect(find.textContaining('동기화 폴더라면 해당 서비스 정책에 따라'), findsOneWidget);
    expect(find.textContaining('웹에서는 API 키 보호 수준'), findsOneWidget);
    // 크래시 리포팅은 기본 꺼짐/선택 전송/Sentry 처리자/정책 문구도 보인다.
    expect(find.textContaining('기본적으로 꺼져 있고'), findsOneWidget);
    expect(find.textContaining('직접 켠 경우에만'), findsOneWidget);
    expect(find.textContaining('Sentry로 전송돼요'), findsOneWidget);

    // 전체 개인정보처리방침을 앱 안에서 바로 볼 수 있는 진입점이 있다.
    final viewPolicyButton = find.widgetWithText(TextButton, '개인정보처리방침 전체 보기');
    expect(viewPolicyButton, findsOneWidget);
    await tester.tap(viewPolicyButton);
    await tester.pumpAndSettle();
    expect(find.text('개인정보처리방침'), findsOneWidget);
    expect(find.textContaining('선택적 크래시 리포팅'), findsOneWidget);
    // 두 다이얼로그가 겹쳐 있으므로(개인정보처리방침 다이얼로그가 위) 가장 나중에
    // 추가된, 즉 화면에 보이는 다이얼로그의 닫기 버튼을 눌러 그것만 닫는다.
    await tester.tap(find.widgetWithText(FilledButton, '닫기').last);
    await tester.pumpAndSettle();
    expect(find.text('개인정보처리방침'), findsNothing);

    // 닫기 버튼으로 명확하게 닫을 수 있다.
    final closeButton = find.widgetWithText(FilledButton, '닫기');
    expect(closeButton, findsOneWidget);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(find.text('데이터 및 개인정보'), findsOneWidget);
    expect(find.textContaining('계정이나 서버 동기화 없이'), findsNothing);

    // 정보 열람/닫기만으로는 어떤 데이터도 바뀌지 않는다(크래시 리포팅 동의 포함).
    expect(storage.claudeApiKey, 'sk-ant-untouched');
    expect(storage.getQuests().single.title, '건드리면 안 되는 퀘스트');
    expect(storage.crashReportingEnabled, isFalse);
  });
}
