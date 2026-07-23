import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/progression_provider.dart';
import '../screens/home_shell.dart';
import '../services/auto_backup_controller.dart';
import '../services/daily_refresh_controller.dart';
import '../theme/app_theme.dart';

class HumanStatusApp extends ConsumerStatefulWidget {
  const HumanStatusApp({
    super.key,
    this.refreshController,
    this.autoBackupController,
  });

  final DailyRefreshController? refreshController;

  /// `null` only in tests that don't exercise the auto-backup resume path
  /// (mirrors [refreshController]'s optionality) — production always
  /// supplies the single instance built in [AppBootstrap].
  final AutoBackupController? autoBackupController;

  @override
  ConsumerState<HumanStatusApp> createState() => _HumanStatusAppState();
}

class _HumanStatusAppState extends ConsumerState<HumanStatusApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱을 켜 둔 채 자정을 넘기고 돌아왔을 때도 반복 퀘스트/추천이 오늘
    // 기준으로 맞춰지도록 한다 — 실제로 다시 돌지 여부는 컨트롤러가 날짜
    // 경계로 판단하므로 같은 날 반복 resume는 UI를 막지 않고 그냥 끝난다.
    //
    // nowProvider는 (다른 Provider와 마찬가지로) 무효화 전까지 값을 캐시해
    // 두므로, 앱을 켜 둔 채 자정을 넘기고 돌아와도 여기서 명시적으로
    // invalidate하지 않으면 성장 여정 스냅샷이 어제에 멈춰 있는다 — 퀘스트
    // 데이터가 전혀 안 바뀐 resume라도 마찬가지다.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(nowProvider);
      widget.refreshController?.refreshIfDue();
      widget.autoBackupController?.backupIfDue();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Human Status',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const HomeShell(),
    );
  }
}
