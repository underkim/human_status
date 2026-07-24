// Phase 6 Part B — 핵심 화면이 큰 글꼴 배율(1.3/2.0/3.0)에서도 레이아웃
// 예외(overflow) 없이 렌더링되는지 확인한다. 실제 콘텐츠가 잘리는지는 이
// 테스트로 판단할 수 없고, `FlutterError`(RenderFlex overflow 등)가 나지
// 않는지만 자동으로 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/providers/observability_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/screens/quests_screen.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/theme/app_theme.dart';

import '../helpers/test_app.dart';
import 'a11y_harness.dart';

Future<void> _pumpAtScale(
  WidgetTester tester,
  StorageService storage,
  Widget home,
  double scale,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        crashReporterProvider.overrideWithValue(FakeCrashReporter()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
}

void main() {
  group('큰 글꼴 배율에서 레이아웃 예외 없음', () {
    testWidgets('대시보드', (tester) async {
      final storage = await createTestStorage();
      await expectNoOverflowAtTextScales(tester, (scale) async {
        await _pumpAtScale(tester, storage, const DashboardScreen(), scale);
        await tester.pump();
      });
    });

    testWidgets('퀘스트 화면', (tester) async {
      final storage = await createTestStorage();
      await expectNoOverflowAtTextScales(tester, (scale) async {
        await _pumpAtScale(tester, storage, const QuestsScreen(), scale);
        await tester.pump();
      });
    });

    testWidgets('설정 화면', (tester) async {
      final storage = await createTestStorage();
      await expectNoOverflowAtTextScales(tester, (scale) async {
        await _pumpAtScale(tester, storage, const SettingsScreen(), scale);
        await tester.pump();
      });
    });
  });
}
