import 'dart:convert';

import '../models/asset_snapshot.dart';
import '../models/financial_plan.dart';
import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import '../models/transaction.dart';
import 'storage_service.dart';

/// Serializes user data to a JSON backup and restores it back. UserProfile
/// is intentionally excluded: the API key and reminder settings are
/// device-specific and must not travel to another device via a backup file.
class BackupService {
  final StorageService storage;

  BackupService({required this.storage});

  String encode() {
    final data = {
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
      'goals': storage.getGoals().map((g) => g.toJson()).toList(),
      'transactions': storage.getTransactions().map((t) => t.toJson()).toList(),
      'assetSnapshots': storage.getAssetSnapshots().map((a) => a.toJson()).toList(),
      'financialPlan': storage.getFinancialPlan().toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Replaces all stored data with the contents of [jsonStr]. Parsing happens
  /// before anything is cleared, so a malformed backup throws without
  /// touching existing data. Keys beyond stats/quests are optional to stay
  /// compatible with backups from older app versions.
  Future<void> restore(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final stats = (data['stats'] as List).map((e) => Stat.fromJson(e as Map<String, dynamic>)).toList();
    final quests = (data['quests'] as List).map((e) => Quest.fromJson(e as Map<String, dynamic>)).toList();
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
  }
}
