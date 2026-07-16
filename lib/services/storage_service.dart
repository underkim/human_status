import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/asset_snapshot.dart';
import '../models/financial_plan.dart';
import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import '../models/transaction.dart';
import '../models/user_profile.dart';
import 'secret_store.dart';

class StorageService {
  static const _claudeApiKeySecretKey = 'claude_api_key';

  static const statsBoxName = 'stats';
  static const questsBoxName = 'quests';
  static const profileBoxName = 'profile';
  static const achievementsBoxName = 'achievements';
  static const goalsBoxName = 'goals';
  static const transactionsBoxName = 'transactions';
  static const assetSnapshotsBoxName = 'assetSnapshots';
  static const financialPlanBoxName = 'financialPlan';

  late Box<Stat> statsBox;
  late Box<Quest> questsBox;
  late Box<UserProfile> profileBox;
  late Box<DateTime> achievementsBox;
  late Box<Goal> goalsBox;
  late Box<Transaction> transactionsBox;
  late Box<AssetSnapshot> assetSnapshotsBox;
  late Box<FinancialPlan> financialPlanBox;

  static const defaultStats = [
    (id: 'health', name: '건강', icon: '💪'),
    (id: 'intelligence', name: '성장', icon: '📈'),
    (id: 'wealth', name: '재정', icon: '💰'),
    (id: 'relationships', name: '관계', icon: '🤝'),
    (id: 'mental', name: '마음', icon: '🧘'),
  ];

  /// Adapter registration is global to the Hive singleton, so it must happen
  /// exactly once per process even if init() runs again (e.g. once per test).
  static bool _adaptersRegistered = false;

  /// Whether boxes live only in memory (no disk writes). Tests use this:
  /// Hive.initFlutter() needs the path_provider plugin, and real file IO
  /// deadlocks under the widget-test FakeAsync zone.
  final bool inMemory;

  final SecretStore secretStore;

  /// Cached Claude API key, kept in sync with [secretStore] and readable
  /// synchronously once [init] has completed.
  String? _claudeApiKey;

  /// True when [_claudeApiKey] is sourced only from the legacy [UserProfile]
  /// field because secure storage has never durably accepted it this
  /// session (a read or write failed). While true, the legacy field is the
  /// *only* copy of the key, so delete/save must not clear it until the
  /// secure store has actually taken over.
  bool _usingLegacyFallback = false;

  /// Effective Claude API key. `null` when none is configured.
  String? get claudeApiKey => _claudeApiKey;

  StorageService({this.inMemory = false, SecretStore? secretStore})
    : secretStore =
          secretStore ??
          (inMemory
              ? InMemorySecretStore()
              : FlutterSecureStorageSecretStore());

  Future<void> init() async {
    if (!inMemory) {
      await Hive.initFlutter();
    }
    if (!_adaptersRegistered) {
      Hive.registerAdapter(StatAdapter());
      Hive.registerAdapter(QuestAdapter());
      Hive.registerAdapter(UserProfileAdapter());
      Hive.registerAdapter(GoalAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(AssetSnapshotAdapter());
      Hive.registerAdapter(FinancialPlanAdapter());
      _adaptersRegistered = true;
    }

    // Passing `bytes` makes hive use its in-memory backend for the box.
    Future<Box<T>> open<T>(String name) => inMemory
        ? Hive.openBox<T>(name, bytes: Uint8List(0))
        : Hive.openBox<T>(name);

    statsBox = await open<Stat>(statsBoxName);
    questsBox = await open<Quest>(questsBoxName);
    profileBox = await open<UserProfile>(profileBoxName);
    achievementsBox = await open<DateTime>(achievementsBoxName);
    goalsBox = await open<Goal>(goalsBoxName);
    transactionsBox = await open<Transaction>(transactionsBoxName);
    assetSnapshotsBox = await open<AssetSnapshot>(assetSnapshotsBoxName);
    financialPlanBox = await open<FinancialPlan>(financialPlanBoxName);

    if (statsBox.isEmpty) {
      for (final s in defaultStats) {
        await statsBox.put(s.id, Stat(id: s.id, name: s.name, icon: s.icon));
      }
    }
    if (profileBox.get('profile') == null) {
      await profileBox.put('profile', UserProfile());
    }

    await _loadOrMigrateClaudeApiKey();
  }

  /// Loads the Claude API key from secure storage, migrating a legacy
  /// plaintext key out of [UserProfile] the first time it succeeds.
  ///
  /// Never throws — secure storage being unavailable must not fail app
  /// bootstrap. If secure storage can't be read this run, the legacy value
  /// (if any) is used as a temporary fallback so the app stays usable, and
  /// migration is retried on the next [init]. If migration's write fails,
  /// the legacy value is left in place (never erased) so it isn't lost.
  Future<void> _loadOrMigrateClaudeApiKey() async {
    String? secureValue;
    var secureReadOk = true;
    try {
      secureValue = await secretStore.read(_claudeApiKeySecretKey);
    } catch (_) {
      secureReadOk = false;
    }

    final profile = getProfile();
    final legacyValue = profile.claudeApiKey;
    final hasLegacyValue = legacyValue != null && legacyValue.isNotEmpty;

    if (!secureReadOk) {
      // Secure storage unavailable this run: fall back to the legacy value
      // (if any) without touching the profile, so a later init can retry.
      _claudeApiKey = hasLegacyValue ? legacyValue : null;
      _usingLegacyFallback = hasLegacyValue;
      return;
    }

    if (secureValue != null && secureValue.isNotEmpty) {
      // Secure storage already holds the current key; it wins over any
      // stale legacy duplicate, which is scrubbed now that it's redundant.
      _claudeApiKey = secureValue;
      _usingLegacyFallback = false;
      if (hasLegacyValue) {
        profile.claudeApiKey = null;
        try {
          await saveProfile(profile);
        } catch (_) {
          // Best-effort scrub; the secure value already governs behavior.
        }
      }
      return;
    }

    if (!hasLegacyValue) {
      _claudeApiKey = null;
      _usingLegacyFallback = false;
      return;
    }

    // No secure key yet, but a legacy plaintext key exists: migrate it.
    try {
      await secretStore.write(_claudeApiKeySecretKey, legacyValue);
      profile.claudeApiKey = null;
      await saveProfile(profile);
      _claudeApiKey = legacyValue;
      _usingLegacyFallback = false;
    } catch (_) {
      // Migration failed — keep the only copy (the legacy field) intact and
      // usable; the next init() will retry the migration.
      _claudeApiKey = legacyValue;
      _usingLegacyFallback = true;
    }
  }

  /// Persists [key] to secure storage and updates the cached value. Throws
  /// on failure without changing the cached value, so callers can show an
  /// error while leaving the previously effective key in place.
  Future<void> saveClaudeApiKey(String key) async {
    await secretStore.write(_claudeApiKeySecretKey, key);
    _claudeApiKey = key;
    _usingLegacyFallback = false;
    // Best-effort: scrub any stale legacy duplicate now that secure storage
    // is authoritative for the new value. A failure here is harmless —
    // secure storage already holds the current key and always wins over any
    // leftover legacy value on the next init.
    try {
      final profile = getProfile();
      if (profile.claudeApiKey != null) {
        profile.claudeApiKey = null;
        await saveProfile(profile);
      }
    } catch (_) {
      // Not fatal; see comment above.
    }
  }

  /// Removes the Claude API key from secure storage and clears the cached
  /// value. Throws on failure without changing the cached value, and never
  /// erases the only remaining copy of the key.
  Future<void> deleteClaudeApiKey() async {
    if (_usingLegacyFallback) {
      // The legacy profile field is currently the *only* copy (secure
      // storage has never durably accepted a write this session). Delete
      // from secure storage first — usually a no-op there — and only clear
      // the legacy field once that succeeds, so a failure leaves the only
      // copy completely untouched.
      await secretStore.delete(_claudeApiKeySecretKey);
      final profile = getProfile();
      profile.claudeApiKey = null;
      await saveProfile(profile);
      _claudeApiKey = null;
      _usingLegacyFallback = false;
      return;
    }

    // Secure storage is (or should already be) authoritative. Scrub any
    // stale legacy duplicate first: if that fails, abort before touching
    // secure storage at all, so the old key stays fully effective
    // everywhere. If it succeeds but the secure delete that follows fails,
    // the still-intact secure copy remains authoritative on the next read,
    // so nothing is lost either way.
    final profile = getProfile();
    if (profile.claudeApiKey != null) {
      profile.claudeApiKey = null;
      await saveProfile(profile);
    }
    await secretStore.delete(_claudeApiKeySecretKey);
    _claudeApiKey = null;
  }

  List<Stat> getStats() => statsBox.values.toList();

  Stat? getStat(String id) => statsBox.get(id);

  Future<void> saveStat(Stat stat) => statsBox.put(stat.id, stat);

  List<Quest> getQuests() => questsBox.values.toList();

  Quest? getQuest(String id) => questsBox.get(id);

  Future<void> saveQuest(Quest quest) => questsBox.put(quest.id, quest);

  Future<void> deleteQuest(String id) => questsBox.delete(id);

  UserProfile getProfile() => profileBox.get('profile') ?? UserProfile();

  Future<void> saveProfile(UserProfile profile) =>
      profileBox.put('profile', profile);

  Map<String, DateTime> getUnlockedAchievements() => Map.fromEntries(
    achievementsBox.keys.map(
      (k) => MapEntry(k as String, achievementsBox.get(k)!),
    ),
  );

  Future<void> unlockAchievement(String id, DateTime unlockedAt) =>
      achievementsBox.put(id, unlockedAt);

  Future<void> deleteUnlockedAchievement(String id) =>
      achievementsBox.delete(id);

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

  FinancialPlan getFinancialPlan() =>
      financialPlanBox.get('plan') ?? FinancialPlan(updatedAt: DateTime.now());

  Future<void> saveFinancialPlan(FinancialPlan plan) =>
      financialPlanBox.put('plan', plan);
}
