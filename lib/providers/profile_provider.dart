import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stat.dart';
import '../models/user_profile.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/xp_service.dart';

/// Overridden in main() once StorageService.init() has completed.
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError(
    'storageServiceProvider must be overridden in main()',
  );
});

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final statsProvider = StateNotifierProvider<StatsNotifier, List<Stat>>((ref) {
  return StatsNotifier(ref.watch(storageServiceProvider));
});

/// Reactive access to the (single) UserProfile record, so screens rebuild on
/// change instead of relying on a manual read + setState.
final profileProvider = StateNotifierProvider<ProfileNotifier, UserProfile>((
  ref,
) {
  return ProfileNotifier(ref.watch(storageServiceProvider));
});

/// Reactive access to unlocked achievement ids, so screens rebuild when a
/// new achievement is unlocked instead of relying on an incidental rebuild
/// from an unrelated provider.
final unlockedAchievementsProvider =
    StateNotifierProvider<AchievementsNotifier, Map<String, DateTime>>((ref) {
      return AchievementsNotifier(ref.watch(storageServiceProvider));
    });

class ProfileNotifier extends StateNotifier<UserProfile> {
  final StorageService storage;

  ProfileNotifier(this.storage) : super(storage.getProfile());

  /// 프로필은 단일 레코드라 hive가 항상 같은 인스턴스를 돌려준다 — 제자리에서
  /// 수정된 뒤 reload()하면 old/new가 identical이라 기본 구현은 리스너에
  /// 알리지 않으므로, 무조건 알리도록 바꾼다.
  @override
  bool updateShouldNotify(UserProfile old, UserProfile current) => true;

  void reload() => state = storage.getProfile();
}

class AchievementsNotifier extends StateNotifier<Map<String, DateTime>> {
  final StorageService storage;

  AchievementsNotifier(this.storage) : super(storage.getUnlockedAchievements());

  void reload() => state = storage.getUnlockedAchievements();
}

final overallLevelProvider = Provider<int>((ref) {
  final stats = ref.watch(statsProvider);
  return XpService.overallLevel(stats);
});

class StatsNotifier extends StateNotifier<List<Stat>> {
  final StorageService storage;

  StatsNotifier(this.storage) : super(storage.getStats());

  void reload() => state = storage.getStats();

  /// Applies [xp] to the stat identified by [statId]. If no stat with that
  /// id exists (e.g. a quest imported from a malformed backup references an
  /// unknown stat), this is a no-op rather than throwing.
  Future<LevelUpResult> applyXp(String statId, double xp) async {
    Stat? stat;
    for (final s in state) {
      if (s.id == statId) {
        stat = s;
        break;
      }
    }
    if (stat == null) {
      return const LevelUpResult(levelsGained: 0, newLevel: 0);
    }
    final result = XpService.applyXp(stat, xp);
    await storage.saveStat(stat);
    reload();
    return result;
  }

  /// Restores the stat identified by [statId] to an exact prior
  /// (level, currentXp) snapshot. Used to undo [applyXp] when a later step
  /// in the same reward transaction fails, so a rolled-back completion
  /// leaves no residual XP behind.
  Future<void> restore(String statId, int level, double currentXp) async {
    Stat? stat;
    for (final s in state) {
      if (s.id == statId) {
        stat = s;
        break;
      }
    }
    if (stat == null) return;
    stat.level = level;
    stat.currentXp = currentXp;
    await storage.saveStat(stat);
    reload();
  }
}
