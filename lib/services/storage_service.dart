import 'package:hive_flutter/hive_flutter.dart';

import '../models/asset_snapshot.dart';
import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import '../models/transaction.dart';
import '../models/user_profile.dart';

class StorageService {
  static const statsBoxName = 'stats';
  static const questsBoxName = 'quests';
  static const profileBoxName = 'profile';
  static const achievementsBoxName = 'achievements';
  static const goalsBoxName = 'goals';
  static const transactionsBoxName = 'transactions';
  static const assetSnapshotsBoxName = 'assetSnapshots';

  late Box<Stat> statsBox;
  late Box<Quest> questsBox;
  late Box<UserProfile> profileBox;
  late Box<DateTime> achievementsBox;
  late Box<Goal> goalsBox;
  late Box<Transaction> transactionsBox;
  late Box<AssetSnapshot> assetSnapshotsBox;

  static const defaultStats = [
    (id: 'health', name: '건강', icon: '💪'),
    (id: 'intelligence', name: '성장', icon: '📈'),
    (id: 'wealth', name: '재정', icon: '💰'),
    (id: 'relationships', name: '관계', icon: '🤝'),
    (id: 'mental', name: '마음', icon: '🧘'),
  ];

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(StatAdapter());
    Hive.registerAdapter(QuestAdapter());
    Hive.registerAdapter(UserProfileAdapter());
    Hive.registerAdapter(GoalAdapter());
    Hive.registerAdapter(TransactionAdapter());
    Hive.registerAdapter(AssetSnapshotAdapter());

    statsBox = await Hive.openBox<Stat>(statsBoxName);
    questsBox = await Hive.openBox<Quest>(questsBoxName);
    profileBox = await Hive.openBox<UserProfile>(profileBoxName);
    achievementsBox = await Hive.openBox<DateTime>(achievementsBoxName);
    goalsBox = await Hive.openBox<Goal>(goalsBoxName);
    transactionsBox = await Hive.openBox<Transaction>(transactionsBoxName);
    assetSnapshotsBox = await Hive.openBox<AssetSnapshot>(assetSnapshotsBoxName);

    if (statsBox.isEmpty) {
      for (final s in defaultStats) {
        await statsBox.put(
          s.id,
          Stat(id: s.id, name: s.name, icon: s.icon),
        );
      }
    }
    if (profileBox.get('profile') == null) {
      await profileBox.put('profile', UserProfile());
    }
  }

  List<Stat> getStats() => statsBox.values.toList();

  Stat? getStat(String id) => statsBox.get(id);

  Future<void> saveStat(Stat stat) => statsBox.put(stat.id, stat);

  List<Quest> getQuests() => questsBox.values.toList();

  Future<void> saveQuest(Quest quest) => questsBox.put(quest.id, quest);

  Future<void> deleteQuest(String id) => questsBox.delete(id);

  UserProfile getProfile() => profileBox.get('profile') ?? UserProfile();

  Future<void> saveProfile(UserProfile profile) =>
      profileBox.put('profile', profile);

  Map<String, DateTime> getUnlockedAchievements() =>
      Map.fromEntries(achievementsBox.keys.map((k) => MapEntry(k as String, achievementsBox.get(k)!)));

  Future<void> unlockAchievement(String id, DateTime unlockedAt) =>
      achievementsBox.put(id, unlockedAt);

  List<Goal> getGoals() => goalsBox.values.toList();

  Goal? getGoal(String id) => goalsBox.get(id);

  Future<void> saveGoal(Goal goal) => goalsBox.put(goal.id, goal);

  Future<void> deleteGoal(String id) => goalsBox.delete(id);

  List<Transaction> getTransactions() => transactionsBox.values.toList();

  Future<void> saveTransaction(Transaction transaction) =>
      transactionsBox.put(transaction.id, transaction);

  /// Persists many transactions in a single batched write (e.g. CSV import),
  /// avoiding a sequential await per row.
  Future<void> saveTransactions(List<Transaction> transactions) =>
      transactionsBox.putAll({for (final t in transactions) t.id: t});

  Future<void> deleteTransaction(String id) => transactionsBox.delete(id);

  List<AssetSnapshot> getAssetSnapshots() => assetSnapshotsBox.values.toList();

  Future<void> saveAssetSnapshot(AssetSnapshot snapshot) =>
      assetSnapshotsBox.put(snapshot.id, snapshot);

  Future<void> deleteAssetSnapshot(String id) => assetSnapshotsBox.delete(id);
}
