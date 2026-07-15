import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/quest.dart';
import 'providers/financial_advisor_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/progression_provider.dart';
import 'providers/quest_provider.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/daily_refresh_controller.dart';
import 'services/notification_service.dart';
import 'services/onboarding_gate.dart';
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
  Object? _error;
  ProviderContainer? _container;
  DailyRefreshController? _refreshController;

  // Bumped on every attempt so a still-in-flight initializer from a
  // superseded attempt (e.g. rapid retry taps) can recognize it's stale and
  // avoid clobbering newer state or double-scheduling the startup sequence.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _container?.dispose();
    super.dispose();
  }

  void _start() {
    final generation = ++_generation;
    _container?.dispose();
    _container = null;
    _refreshController = null;
    setState(() {
      _status = _BootstrapStatus.loading;
      _error = null;
    });
    unawaited(_initialize(generation));
  }

  Future<void> _initialize(int generation) async {
    final StorageService storage;
    try {
      storage = await widget.createStorage();
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = _BootstrapStatus.error;
        _error = e;
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
        return _BootstrapErrorScreen(error: _error, onRetry: _start);
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
  const _BootstrapErrorScreen({required this.error, required this.onRetry});

  final Object? error;
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
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
    // profileProvider를 watch해 온보딩 게이트를 매 빌드마다 다시 평가한다
    // (시작 시 한 번만 계산하는 flag가 아님) — 온보딩 완료/건너뛰기는 물론
    // 데이터 초기화로 onboardingCompleted가 다시 false가 되는 경우에도,
    // 같은 실행 중에 즉시 반영되어 알맞은 화면으로 전환된다.
    ref.watch(profileProvider);
    final showOnboarding = shouldShowOnboarding(
      ref.read(storageServiceProvider),
    );
    return MaterialApp(
      // Navigator는 그 자체로 상태를 갖는 위젯이라, 예를 들어 설정 화면이
      // 몇 단계 push된 채로 온보딩 게이트가 바뀌면 `home`만 바꿔서는 이미
      // push된 화면들이 그대로 남는다 — showOnboarding이 바뀔 때마다 키를
      // 바꿔 앱 전체(그 안의 Navigator와 push 스택 포함)를 처음부터 다시
      // 마운트해, 항상 깨끗한 화면에서 시작하게 한다.
      key: ValueKey(showOnboarding),
      title: 'Human Status',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: showOnboarding ? const OnboardingScreen() : const HomeShell(),
    );
  }
}
