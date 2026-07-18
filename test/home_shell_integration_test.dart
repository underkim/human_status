import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/home_shell.dart';
import 'package:human_status/screens/onboarding_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('HomeShell의 IndexedStack에 마운트된 여러 FAB이 있어도 대시보드 AI 설계로 '
      '독립 마법사에 진입할 때 Hero 충돌이 없다', (tester) async {
    setScreenSize(tester, const Size(400, 800));
    final storage = await createTestStorage();
    final profile = storage.getProfile();
    profile.onboardingCompleted = true;
    await storage.saveProfile(profile);

    // 실제 HumanStatusApp을 그대로 pump한다 — HomeShell의 IndexedStack이
    // 퀘스트/목표/재무 탭의 FAB을 전부 동시에 마운트해두는 실제 조건에서만
    // heroTag 충돌이 재현되므로, DashboardScreen만 단독으로 pump하는
    // 테스트로는 이 회귀를 잡을 수 없다.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const HumanStatusApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('AI로 첫 퀘스트 설계하기'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
