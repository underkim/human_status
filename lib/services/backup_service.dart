import 'dart:convert';

import 'package:meta/meta.dart';

import '../models/asset_snapshot.dart';
import '../models/financial_plan.dart';
import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import '../models/transaction.dart';
import '../models/user_profile.dart';
import 'storage_service.dart';

/// Thrown when [BackupService.restore] fails after mutation has begun. The
/// pre-import snapshot has already been restored by the time this is
/// thrown; [cause] carries the original error that triggered the rollback.
class BackupRestoreException implements Exception {
  final Object cause;
  final StackTrace causeStackTrace;

  BackupRestoreException(this.cause, this.causeStackTrace);

  @override
  String toString() =>
      'BackupRestoreException: restore failed and was rolled back to the '
      'pre-import state. Cause: $cause';
}

/// Thrown when a restore fails AND the subsequent rollback also fails.
/// Storage may be left partially replaced — both failures are surfaced so
/// neither is silently swallowed.
class BackupRestoreRollbackFailedException implements Exception {
  final Object applyError;
  final StackTrace applyStackTrace;
  final Object rollbackError;
  final StackTrace rollbackStackTrace;

  BackupRestoreRollbackFailedException(
    this.applyError,
    this.applyStackTrace,
    this.rollbackError,
    this.rollbackStackTrace,
  );

  @override
  String toString() =>
      'BackupRestoreRollbackFailedException: restore failed (cause: '
      '$applyError) AND rollback also failed (cause: $rollbackError). '
      'Storage may be left partially replaced.';
}

/// In-memory copy of every domain the restore replaces, captured
/// immediately before mutation so it can be written back verbatim if
/// anything fails partway through.
class _RestoreSnapshot {
  final List<Stat> stats;
  final List<Quest> quests;
  final List<Goal> goals;
  final List<Transaction> transactions;
  final List<AssetSnapshot> assetSnapshots;
  final FinancialPlan? financialPlan;
  final Map<String, DateTime> achievements;
  final UserProfile profile;

  _RestoreSnapshot({
    required this.stats,
    required this.quests,
    required this.goals,
    required this.transactions,
    required this.assetSnapshots,
    required this.financialPlan,
    required this.achievements,
    required this.profile,
  });
}

/// Serializes user data to a JSON backup and restores it back. Most of
/// UserProfile is intentionally excluded: the API key and reminder settings
/// are device-specific and must not travel to another device via a backup
/// file. Product preferences (onboarding completion, preferred stat) are the
/// exception — those are safe to round-trip and live under a dedicated
/// `preferences` key so they never get confused with device settings.
class BackupService {
  /// Bump when the on-disk backup shape changes in a way older app
  /// versions can't parse. Backups without a `schemaVersion` key predate
  /// this field and are treated as version 1 for compatibility.
  static const currentSchemaVersion = 1;

  final StorageService storage;

  /// Test-only fault injection point. When set, it fires exactly once,
  /// immediately after the first domain has been cleared/written during
  /// [restore]'s apply phase, then clears itself so neither a later apply
  /// step nor the rollback that follows (which reuses the same storage
  /// writes) is sabotaged by firing again. Left `null` in production, so it
  /// can never fire unless a test explicitly sets it.
  @visibleForTesting
  void Function()? debugApplyFaultInjector;

  /// Test-only fault injection point for the rollback path itself. When
  /// set, it fires exactly once, immediately after the first domain has
  /// been restored during [restore]'s rollback phase, then clears itself
  /// so it can't sabotage the rest of that same rollback attempt. Left
  /// `null` in production, so it can never fire unless a test explicitly
  /// sets it.
  @visibleForTesting
  void Function()? debugRollbackFaultInjector;

  BackupService({required this.storage});

  String encode() {
    final profile = storage.getProfile();
    final data = {
      'schemaVersion': currentSchemaVersion,
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
      'goals': storage.getGoals().map((g) => g.toJson()).toList(),
      'transactions': storage.getTransactions().map((t) => t.toJson()).toList(),
      'assetSnapshots': storage
          .getAssetSnapshots()
          .map((a) => a.toJson())
          .toList(),
      'financialPlan': storage.getFinancialPlan().toJson(),
      'achievements': storage.getUnlockedAchievements().map(
        (id, unlockedAt) => MapEntry(id, unlockedAt.toIso8601String()),
      ),
      'preferences': {
        'onboardingCompleted': profile.onboardingCompleted,
        'preferredStatId': profile.preferredStatId,
      },
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Replaces all stored data with the contents of [jsonStr]. Parsing (and
  /// validation — including `schemaVersion` and the `preferences` block
  /// below) happens before anything is cleared, so a malformed backup
  /// throws without touching existing data. Keys beyond stats/quests are
  /// optional to stay compatible with backups from older app versions.
  ///
  /// If any storage operation fails once mutation has begun, the exact
  /// pre-import state of every affected domain (and the product-preference
  /// fields on the profile) is restored before a [BackupRestoreException]
  /// is thrown; device-specific profile fields (API key, reminder
  /// settings) are never touched, on success or failure.
  Future<void> restore(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    // 키가 아예 없는(구버전) 백업만 레거시로 취급한다 — 키는 있는데 값이
    // null/문자열/실수 등 정수가 아니면 명시적으로 잘못된 백업이므로,
    // "없으니 구버전"으로 관대하게 봐주지 않고 clear 전에 예외를 던진다.
    if (data.containsKey('schemaVersion')) {
      final schemaVersionRaw = data['schemaVersion'];
      if (schemaVersionRaw is! int) {
        throw FormatException(
          'schemaVersion must be an integer, got: $schemaVersionRaw',
        );
      }
      if (schemaVersionRaw != currentSchemaVersion) {
        throw FormatException(
          'Unsupported backup schemaVersion: $schemaVersionRaw '
          '(this app supports version $currentSchemaVersion)',
        );
      }
    }

    final stats = (data['stats'] as List)
        .map((e) => Stat.fromJson(e as Map<String, dynamic>))
        .toList();
    final quests = (data['quests'] as List)
        .map((e) => Quest.fromJson(e as Map<String, dynamic>))
        .toList();
    final goals = (data['goals'] as List? ?? [])
        .map((e) => Goal.fromJson(e as Map<String, dynamic>))
        .toList();
    final transactions = (data['transactions'] as List? ?? [])
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList();
    final assetSnapshots = (data['assetSnapshots'] as List? ?? [])
        .map((e) => AssetSnapshot.fromJson(e as Map<String, dynamic>))
        .toList();
    final financialPlan = data['financialPlan'] != null
        ? FinancialPlan.fromJson(data['financialPlan'] as Map<String, dynamic>)
        : null;
    // 구버전 백업엔 이 키가 없어 빈 맵으로 취급 — restore는 '전체 교체'라
    // 기존 업적을 남기지 않는다(교체 후에도 조건을 만족하면 다음 완료
    // 시점에 checkAndUnlock이 다시 해금한다).
    final achievements = (data['achievements'] as Map? ?? const {}).map(
      (k, v) => MapEntry(k as String, DateTime.parse(v as String)),
    );

    // preferences는 API 키/알림 같은 기기 설정과 분리된 제품 선호(온보딩
    // 완료 여부·우선 스탯)만 담는다. 다른 섹션과 동일하게, 타입이 잘못된
    // preferences도 아래 clear가 실행되기 전에 여기서 걸러낸다.
    final preferencesRaw = data['preferences'];
    if (preferencesRaw != null && preferencesRaw is! Map) {
      throw const FormatException('preferences must be a JSON object');
    }
    final preferences = preferencesRaw as Map<String, dynamic>?;
    bool? restoredOnboardingCompleted;
    var hasPreferredStatId = false;
    String? restoredPreferredStatId;
    if (preferences != null) {
      final onboardingCompletedRaw = preferences['onboardingCompleted'];
      if (onboardingCompletedRaw != null && onboardingCompletedRaw is! bool) {
        throw const FormatException(
          'preferences.onboardingCompleted must be a bool',
        );
      }
      restoredOnboardingCompleted = onboardingCompletedRaw as bool?;

      // 키가 아예 없는(구버전) 것과 명시적으로 null인 것을 구분한다 — 후자는
      // "선호를 지운다"는 뜻이라 기존 preferredStatId를 실제로 비워야 한다.
      hasPreferredStatId = preferences.containsKey('preferredStatId');
      final preferredStatIdRaw = preferences['preferredStatId'];
      if (preferredStatIdRaw != null && preferredStatIdRaw is! String) {
        throw const FormatException(
          'preferences.preferredStatId must be a string',
        );
      }
      restoredPreferredStatId = preferredStatIdRaw as String?;
    }

    // 파싱·검증이 전부 끝난 지금이 마지막으로 안전한 지점이다 — 이제부터는
    // 실제 박스를 건드리므로, 실패 시 되돌릴 수 있도록 현재 상태를 깊은
    // 복사로 떠 둔다(참조를 그대로 들고 있으면 아래에서 같은 객체를 다시
    // 저장할 때 스냅샷도 같이 바뀌어버린다).
    final snapshot = _captureSnapshot();

    try {
      await _apply(
        stats: stats,
        quests: quests,
        goals: goals,
        transactions: transactions,
        assetSnapshots: assetSnapshots,
        financialPlan: financialPlan,
        achievements: achievements,
        preferences: preferences,
        restoredOnboardingCompleted: restoredOnboardingCompleted,
        hasPreferredStatId: hasPreferredStatId,
        restoredPreferredStatId: restoredPreferredStatId,
      );
    } catch (applyError, applyStackTrace) {
      try {
        await _rollback(snapshot);
      } catch (rollbackError, rollbackStackTrace) {
        throw BackupRestoreRollbackFailedException(
          applyError,
          applyStackTrace,
          rollbackError,
          rollbackStackTrace,
        );
      }
      throw BackupRestoreException(applyError, applyStackTrace);
    }
  }

  _RestoreSnapshot _captureSnapshot() {
    final financialPlanRaw = storage.financialPlanBox.get('plan');
    return _RestoreSnapshot(
      stats: storage.getStats().map((s) => Stat.fromJson(s.toJson())).toList(),
      quests: storage
          .getQuests()
          .map((q) => Quest.fromJson(q.toJson()))
          .toList(),
      goals: storage.getGoals().map((g) => Goal.fromJson(g.toJson())).toList(),
      transactions: storage
          .getTransactions()
          .map((t) => Transaction.fromJson(t.toJson()))
          .toList(),
      assetSnapshots: storage
          .getAssetSnapshots()
          .map((a) => AssetSnapshot.fromJson(a.toJson()))
          .toList(),
      financialPlan: financialPlanRaw == null
          ? null
          : FinancialPlan.fromJson(financialPlanRaw.toJson()),
      achievements: Map.of(storage.getUnlockedAchievements()),
      profile: _copyProfile(storage.getProfile()),
    );
  }

  UserProfile _copyProfile(UserProfile p) => UserProfile(
    lastQuestRefresh: p.lastQuestRefresh,
    // claudeApiKey는 마이그레이션 후 사실상 항상 null인 레거시 필드이고,
    // 실제 키는 보안 저장소에 있어 이 스냅샷/롤백의 영향을 받지 않는다 —
    // 여기서 값을 복사해도 최종 진실은 secure storage이므로 오해를 막기
    // 위해 그대로 옮기지 않는다.
    reminderMinutesSinceMidnight: p.reminderMinutesSinceMidnight,
    lastAdviceRefresh: p.lastAdviceRefresh,
    cachedAdvice: p.cachedAdvice
        .map((m) => Map<String, dynamic>.from(m))
        .toList(),
    weeklyReportReminderEnabled: p.weeklyReportReminderEnabled,
    onboardingCompleted: p.onboardingCompleted,
    preferredStatId: p.preferredStatId,
  );

  void _maybeInjectApplyFault() {
    final injector = debugApplyFaultInjector;
    if (injector == null) return;
    // 한 번만 발동시키고 스스로를 해제한다 — 그래야 실패 후 rollback이
    // 같은 박스들에 다시 쓸 때 또 걸려 넘어지지 않는다.
    debugApplyFaultInjector = null;
    injector();
  }

  void _maybeInjectRollbackFault() {
    final injector = debugRollbackFaultInjector;
    if (injector == null) return;
    // apply 주입과 마찬가지로 한 번만 발동시키고 스스로를 해제해, 같은
    // rollback 시도 안에서 남은 박스들을 계속 복구하는 것을 막지 않는다.
    debugRollbackFaultInjector = null;
    injector();
  }

  Future<void> _apply({
    required List<Stat> stats,
    required List<Quest> quests,
    required List<Goal> goals,
    required List<Transaction> transactions,
    required List<AssetSnapshot> assetSnapshots,
    required FinancialPlan? financialPlan,
    required Map<String, DateTime> achievements,
    required Map<String, dynamic>? preferences,
    required bool? restoredOnboardingCompleted,
    required bool hasPreferredStatId,
    required String? restoredPreferredStatId,
  }) async {
    await storage.statsBox.clear();
    await storage.questsBox.clear();
    await storage.goalsBox.clear();
    await storage.transactionsBox.clear();
    await storage.assetSnapshotsBox.clear();
    await storage.financialPlanBox.clear();
    for (final s in stats) {
      await storage.saveStat(s);
    }
    _maybeInjectApplyFault();
    for (final q in quests) {
      await storage.saveQuest(q);
    }
    for (final g in goals) {
      await storage.saveGoal(g);
    }
    await storage.saveTransactions(transactions);
    for (final a in assetSnapshots) {
      await storage.saveAssetSnapshot(a);
    }
    if (financialPlan != null) {
      await storage.saveFinancialPlan(financialPlan);
    }
    await storage.achievementsBox.clear();
    for (final e in achievements.entries) {
      await storage.unlockAchievement(e.key, e.value);
    }

    // preferences는 API 키/알림 같은 기기 설정과 분리된 제품 선호라 프로필의
    // 나머지 필드는 그대로 두고 이 두 값만 덮어쓴다.
    final profile = storage.getProfile();
    if (preferences != null) {
      if (restoredOnboardingCompleted != null) {
        profile.onboardingCompleted = restoredOnboardingCompleted;
      }
      // 키가 있었다면 값이 null이더라도 그대로 반영해 기존 선호를 지운다.
      if (hasPreferredStatId) {
        profile.preferredStatId = restoredPreferredStatId;
      }
    } else {
      // 구버전 백업엔 이 키 자체가 없다. 하지만 백업을 가져오는 행위 자체가
      // 이미 이 앱을 써본 사용자라는 신호이므로, 방금 설치한 기기의 미완료
      // 프로필이 복원 후에도 온보딩에 갇히지 않도록 완료 처리한다.
      // preferredStatId는 이 백업에 아무 정보가 없으므로 건드리지 않는다.
      profile.onboardingCompleted = true;
    }
    await storage.saveProfile(profile);
  }

  Future<void> _rollback(_RestoreSnapshot snapshot) async {
    await storage.statsBox.clear();
    for (final s in snapshot.stats) {
      await storage.saveStat(s);
    }
    _maybeInjectRollbackFault();
    await storage.questsBox.clear();
    for (final q in snapshot.quests) {
      await storage.saveQuest(q);
    }
    await storage.goalsBox.clear();
    for (final g in snapshot.goals) {
      await storage.saveGoal(g);
    }
    await storage.transactionsBox.clear();
    await storage.saveTransactions(snapshot.transactions);
    await storage.assetSnapshotsBox.clear();
    for (final a in snapshot.assetSnapshots) {
      await storage.saveAssetSnapshot(a);
    }
    await storage.financialPlanBox.clear();
    if (snapshot.financialPlan != null) {
      await storage.saveFinancialPlan(snapshot.financialPlan!);
    }
    await storage.achievementsBox.clear();
    for (final e in snapshot.achievements.entries) {
      await storage.unlockAchievement(e.key, e.value);
    }
    // 스냅샷 프로필 객체로 통째로 덮어쓰지 않는다 — 그 객체는 claudeApiKey를
    // 애초에 복사하지 않았으므로(_copyProfile 참고), 그대로 saveProfile하면
    // 아직 보안 저장소로 마이그레이션되지 못한 레거시 키(그 상태에서는
    // 유일한 복사본)를 지워버린다. 대신 현재 프로필 객체에 비-시크릿
    // 필드만 되돌려 써서 claudeApiKey는 항상 손대지 않는다.
    final currentProfile = storage.getProfile();
    currentProfile.lastQuestRefresh = snapshot.profile.lastQuestRefresh;
    currentProfile.reminderMinutesSinceMidnight =
        snapshot.profile.reminderMinutesSinceMidnight;
    currentProfile.lastAdviceRefresh = snapshot.profile.lastAdviceRefresh;
    currentProfile.cachedAdvice = snapshot.profile.cachedAdvice;
    currentProfile.weeklyReportReminderEnabled =
        snapshot.profile.weeklyReportReminderEnabled;
    currentProfile.onboardingCompleted = snapshot.profile.onboardingCompleted;
    currentProfile.preferredStatId = snapshot.profile.preferredStatId;
    await storage.saveProfile(currentProfile);
  }
}
