import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/providers/observability_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/screens/dashboard_screen.dart';
import 'package:human_status/screens/finance_asset_tab_view.dart';
import 'package:human_status/screens/goals_screen.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/screens/quests_screen.dart';
import 'package:human_status/screens/report_screen.dart';
import 'package:human_status/screens/settings_screen.dart';
import 'package:human_status/theme/app_theme.dart';

import 'helpers/test_app.dart';

const _compact = Size(400, 800);
const _wide = Size(1440, 900);
const _captureKey = Key('l-m3-capture');

typedef ScreenFactory = Widget Function();

Future<void> _pumpCapture(
  WidgetTester tester, {
  required ScreenFactory screen,
  required ThemeMode themeMode,
  required Size viewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final storage = await createTestStorage();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        crashReporterProvider.overrideWithValue(FakeCrashReporter()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        builder: (context, child) =>
            RepaintBoundary(key: _captureKey, child: child!),
        home: screen(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // RenderFlex overflow and other framework render failures surface here.
  expect(tester.takeException(), isNull);
}

void main() {
  tearDown(Hive.close);

  final screens = <String, ScreenFactory>{
    'onboarding': () => const OnboardingScreen(),
    'dashboard': () => const DashboardScreen(),
    'quests': () => const QuestsScreen(),
    'goals': () => const GoalsScreen(),
    'finance': () => const FinanceScreen(),
    'report': () => const ReportScreen(),
    'settings': () => const SettingsScreen(),
  };
  final themes = <String, ThemeMode>{
    'light': ThemeMode.light,
    'dark': ThemeMode.dark,
  };
  final viewports = <String, Size>{'400x800': _compact, '1440x900': _wide};

  group('L-M3 7 screens x 2 themes x 2 viewports', () {
    for (final screen in screens.entries) {
      for (final theme in themes.entries) {
        for (final viewport in viewports.entries) {
          final name = '${screen.key}_${theme.key}_${viewport.key}';
          testWidgets(name, (tester) async {
            await _pumpCapture(
              tester,
              screen: screen.value,
              themeMode: theme.value,
              viewport: viewport.value,
            );
            await expectLater(
              find.byKey(_captureKey),
              matchesGoldenFile('goldens/l_m3/$name.png'),
            );
          });
        }
      }
    }
  });
}
