import 'dart:convert';

import '../models/asset_snapshot.dart';
import '../models/financial_plan.dart';
import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import '../models/transaction.dart';
import 'storage_service.dart';

/// Serializes user data to a JSON backup and restores it back. Most of
/// UserProfile is intentionally excluded: the API key and reminder settings
/// are device-specific and must not travel to another device via a backup
/// file. Product preferences (onboarding completion, preferred stat) are the
/// exception — those are safe to round-trip and live under a dedicated
/// `preferences` key so they never get confused with device settings.
class BackupService {
  final StorageService storage;

  BackupService({required this.storage});

  String encode() {
    final profile = storage.getProfile();
    final data = {
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
  /// validation — including the `preferences` block below) happens before
  /// anything is cleared, so a malformed backup throws without touching
  /// existing data. Keys beyond stats/quests are optional to stay compatible
  /// with backups from older app versions.
  Future<void> restore(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
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

    await storage.statsBox.clear();
    await storage.questsBox.clear();
    await storage.goalsBox.clear();
    await storage.transactionsBox.clear();
    await storage.assetSnapshotsBox.clear();
    await storage.financialPlanBox.clear();
    for (final s in stats) {
      await storage.saveStat(s);
    }
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
}
