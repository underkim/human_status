import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/quest.dart';
import 'providers/financial_advisor_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/progression_provider.dart';
import 'providers/quest_provider.dart';
import 'screens/home_shell.dart';
import 'services/daily_refresh_controller.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // runApp fires immediately with a mounted bootstrap widget — storage init
  // (which can fail, e.g. a corrupt Hive file) happens behind it, so a
  // failure surfaces as a recovery screen instead of a blank pre-runApp
  // crash.
  runApp(const AppBootstrap());
}

/// Creates and initializes the [StorageService] used by the real app.
/// Injectable on [AppBootstrap] so widget tests can substitute a pending or
/// failing initializer without touching real disk/plugin state.
typedef StorageInitializer = Future<StorageService> Function();

Future<StorageService> _defaultCreateStorage() async {
  final storage = StorageService();
  await storage.init();
  return storage;
}

/// Runs the startup refresh/notification sequence for a freshly-initialized
/// storage attempt. Injectable on [AppBootstrap] so tests can count/observe
/// invocations instead of hitting the real notification plugin.
typedef StartupSequenceRunner =
    Future<void> Function(
      DailyRefreshController refreshController,
      StorageService storage,
    );

/// Bootstraps the app: mounts immediately (so `main()` can call `runApp`
/// synchronously), then runs [createStorage] asynchronously behind a themed
/// loading state. On success it builds the exact same
/// `ProviderContainer` + `DailyRefreshController` + [HumanStatusApp] path the
/// app always has, and schedules [startupSequenceRunner] exactly once, after
/// the first frame in which that content is mounted. On failure it shows a
/// Korean recovery screen with a retry button — local data is never touched,
/// let alone cleared, on a failed open.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    this.createStorage = _defaultCreateStorage,
    this.startupSequenceRunner = runStartupSequence,
  });

  final StorageInitializer createStorage;
  final StartupSequenceRunner startupSequenceRunner;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

enum _BootstrapStatus { loading, ready, error }

class _AppBootstrapState extends State<AppBootstrap> {
  _BootstrapStatus _status = _BootstrapStatus.loading;
  ProviderContainer? _container;
  DailyRefreshController? _refreshController;

  // Bumped on every attempt so a still-in-flight initializer from a
  // superseded attempt (e.g. rapid retry taps) can recognize it's stale and
  // avoid clobbering newer state or double-scheduling the startup sequence.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // _status already defaults to loading, so the first attempt doesn't
    // need a setState to enter it — only retries (which may be resetting
    // from the error state) do.
    unawaited(_initialize(++_generation));
  }

  @override
  void dispose() {
    _container?.dispose();
    super.dispose();
  }

  void _retry() {
    final generation = ++_generation;
    _container?.dispose();
    _container = null;
    _refreshController = null;
    setState(() {
      _status = _BootstrapStatus.loading;
    });
    unawaited(_initialize(generation));
  }

  Future<void> _initialize(int generation) async {
    final StorageService storage;
    try {
      storage = await widget.createStorage();
    } catch (e) {
      // The raw error is deliberately not surfaced to the UI — initializer
      // failures (e.g. a Hive exception) can embed on-disk file paths or
      // other diagnostics that shouldn't be shown to the user.
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = _BootstrapStatus.error;
      });
      return;
    }

    if (!mounted || generation != _generation) return;

    // A manual container (instead of a plain ProviderScope) so the daily
    // refresh below can poke the affected notifiers to reload once it
    // finishes.
    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );

    // 최초 시작과, 자정을 넘긴 뒤의 resume 모두 이 컨트롤러 하나를 거친다 —
    // 같은 날짜 안에서는 반복 호출돼도 한 번만 실제로 갱신한다.
    final refreshController = DailyRefreshController(
      storage: storage,
      onQuestsChanged: () => container.read(questsProvider.notifier).reload(),
      onAdviceChanged: () =>
          container.read(financialAdviceProvider.notifier).reload(),
    );

    // AI refreshes and notification scheduling run AFTER the first frame in
    // which HumanStatusApp is actually mounted — a slow or absent network
    // must never delay opening the app. Scheduled exactly once per
    // successful attempt (not in build(), so rebuilds never re-trigger it).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      unawaited(widget.startupSequenceRunner(refreshController, storage));
    });

    setState(() {
      _container = container;
      _refreshController = refreshController;
      _status = _BootstrapStatus.ready;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _BootstrapStatus.loading:
        return const _BootstrapLoadingScreen();
      case _BootstrapStatus.error:
        return _BootstrapErrorScreen(onRetry: _retry);
      case _BootstrapStatus.ready:
        return UncontrolledProviderScope(
          container: _container!,
          child: HumanStatusApp(refreshController: _refreshController),
        );
    }
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Human Status',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Human Status',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Human Status',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '로컬 데이터를 열 수 없습니다',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '기기에 저장된 데이터를 불러오는 중 문제가 발생했습니다. '
                    '기존 데이터는 삭제되지 않고 그대로 남아 있습니다. 다시 시도해 주세요.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs the startup refresh to completion before scheduling notifications,
/// so the reminder's active-quest count reflects post-respawn state rather
/// than a stale pre-refresh snapshot. [notificationService] is injectable
/// so tests can substitute a fake instead of hitting the real platform
/// plugin (mirrors [DailyRefreshController]'s pattern for its own steps).
Future<void> runStartupSequence(
  DailyRefreshController refreshController,
  StorageService storage, {
  NotificationService? notificationService,
}) async {
  await refreshController.refreshIfDue();
  await scheduleNotifications(
    storage,
    notificationService: notificationService,
  );
}

Future<void> scheduleNotifications(
  StorageService storage, {
  NotificationService? notificationService,
}) async {
  try {
    final service = notificationService ?? NotificationService();
    await service.init();
    final profile = storage.getProfile();
    final reminderMinutes = profile.reminderMinutesSinceMidnight;
    if (reminderMinutes != null) {
      final activeQuestCount = storage
          .getQuests()
          .where((q) => q.status == QuestStatus.active)
          .length;
      await service.scheduleDailyReminder(
        hour: reminderMinutes ~/ 60,
        minute: reminderMinutes % 60,
        activeQuestCount: activeQuestCount,
      );
    }
    if (profile.weeklyReportReminderEnabled) {
      await service.scheduleWeeklyReportReminder();
    }
  } catch (_) {}
}

class HumanStatusApp extends ConsumerStatefulWidget {
  const HumanStatusApp({super.key, this.refreshController});

  final DailyRefreshController? refreshController;

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
