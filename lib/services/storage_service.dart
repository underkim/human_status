import 'package:hive_flutter/hive_flutter.dart';

import '../models/quest.dart';
import '../models/stat.dart';
import '../models/user_profile.dart';

class StorageService {
  static const statsBoxName = 'stats';
  static const questsBoxName = 'quests';
  static const profileBoxName = 'profile';
  static const achievementsBoxName = 'achievements';

  late Box<Stat> statsBox;
  late Box<Quest> questsBox;
  late Box<UserProfile> profileBox;
  late Box<DateTime> achievementsBox;

  static const defaultStats = [
    (id: 'health', name: '체력', icon: '💪'),
    (id: 'intelligence', name: '지식', icon: '📚'),
    (id: 'wealth', name: '재정', icon: '💰'),
    (id: 'relationships', name: '관계', icon: '🤝'),
    (id: 'mental', name: '멘탈', icon: '🧘'),
  ];

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(StatAdapter());
    Hive.registerAdapter(QuestAdapter());
    Hive.registerAdapter(UserProfileAdapter());

    statsBox = await Hive.openBox<Stat>(statsBoxName);
    questsBox = await Hive.openBox<Quest>(questsBoxName);
    profileBox = await Hive.openBox<UserProfile>(profileBoxName);
    achievementsBox = await Hive.openBox<DateTime>(achievementsBoxName);

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
}
