import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/services/daily_refresh_controller.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('resume 라이프사이클 이벤트가 DailyRefreshController.refreshIfDue를 호출한다', (
    tester,
  ) async {
    final storage = await createTestStorage();
    var refreshCalls = 0;

    final controller = DailyRefreshController(
      storage: storage,
      respawnRecurringQuests: (now) async => refreshCalls++,
      refreshRecommendations: () async {},
      refreshFinancialAdvice: () async {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: HumanStatusApp(refreshController: controller),
      ),
    );
    await tester.pump();

    // 최초 pump 자체는 controller.refreshIfDue()를 자동으로 호출하지 않는다 —
    // main()에서 별도로 한 번 트리거하는 startup 경로와 분리되어 있다.
    expect(refreshCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(refreshCalls, 1);

    // 같은 날 다시 resume해도 중복 호출되지 않는다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(refreshCalls, 1);
  });
}
