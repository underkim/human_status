import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/asset_snapshot.dart';
import 'package:human_status/models/financial_plan.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

Future<StorageService> _seededStorage() async {
  final storage = await createTestStorage();
  final health = storage.getStat('health')!;
  health.level = 4;
  health.currentXp = 55;
  await storage.saveStat(health);
  await storage.saveQuest(Quest(
    id: 'q1',
    title: '아침 운동',
    description: '30분',
    statRewards: {'health': 30},
    status: QuestStatus.completed,
    createdAt: DateTime(2026, 6, 1),
    completedAt: DateTime(2026, 6, 2),
    goalId: 'g1',
  ));
  await storage.saveGoal(Goal(
    id: 'g1',
    title: '여름 몸만들기',
    description: '',
    statId: 'health',
    targetDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 6, 1),
  ));
  await storage.saveTransaction(Transaction(
    id: 't1',
    type: TransactionType.expense,
    category: '식비',
    memo: '점심',
    amount: 12000,
    date: DateTime(2026, 7, 1),
    createdAt: DateTime(2026, 7, 1),
  ));
  await storage.saveAssetSnapshot(AssetSnapshot(
    id: 'a1',
    importedAt: DateTime(2026, 7, 1),
    assetsByCategory: {'예금': 5000000},
    liabilitiesByCategory: {'대출': 1000000},
    totalAssets: 5000000,
    totalLiabilities: 1000000,
  ));
  await storage.unlockAchievement('first_quest', DateTime(2026, 6, 2, 10));
  await storage.saveFinancialPlan(FinancialPlan(
    updatedAt: DateTime(2026, 7, 1),
    retirementEnabled: true,
    currentAge: 30,
    retirementAge: 60,
    monthlyLivingCostAfterRetirement: 2500000,
    monthlyBudget: 1500000,
    categoryBudgets: {'식비': 400000},
  ));
  return storage;
}

void main() {
  test('encode → restore 왕복 후 모든 데이터가 그대로 복원된다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final backup = service.encode();

    // 백업 후 데이터를 전부 바꿔놓고 복원이 원상태로 되돌리는지 본다.
    await storage.questsBox.clear();
    await storage.goalsBox.clear();
    await storage.transactionsBox.clear();
    await storage.assetSnapshotsBox.clear();
    await storage.financialPlanBox.clear();
    await storage.achievementsBox.clear();
    final health = storage.getStat('health')!;
    health.level = 1;
    health.currentXp = 0;
    await storage.saveStat(health);

    await service.restore(backup);

    final restoredStat = storage.getStat('health')!;
    expect(restoredStat.level, 4);
    expect(restoredStat.currentXp, 55);

    final quest = storage.getQuests().single;
    expect(quest.title, '아침 운동');
    expect(quest.status, QuestStatus.completed);
    expect(quest.goalId, 'g1');
    expect(quest.statRewards, {'health': 30});

    final goal = storage.getGoals().single;
    expect(goal.title, '여름 몸만들기');
    expect(goal.targetDate, DateTime(2026, 9, 1));

    final tx = storage.getTransactions().single;
    expect(tx.category, '식비');
    expect(tx.amount, 12000);

    final snapshot = storage.getAssetSnapshots().single;
    expect(snapshot.netWorth, 4000000);
    expect(snapshot.assetsByCategory, {'예금': 5000000});

    final plan = storage.getFinancialPlan();
    expect(plan.retirementEnabled, isTrue);
    expect(plan.retirementAge, 60);
    expect(plan.monthlyBudget, 1500000);
    expect(plan.categoryBudgets, {'식비': 400000});

    expect(storage.getUnlockedAchievements(), {'first_quest': DateTime(2026, 6, 2, 10)});
  });

  test('구버전 백업(스텟·퀘스트만 있는 파일)도 복원된다', () async {
    final storage = await _seededStorage();
    final legacy = jsonEncode({
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
    });

    await BackupService(storage: storage).restore(legacy);

    expect(storage.getQuests().single.title, '아침 운동');
    // 구버전에 없던 데이터는 교체 시맨틱에 따라 비워진다.
    expect(storage.getGoals(), isEmpty);
    expect(storage.getTransactions(), isEmpty);
    // 단, 업적 키가 아예 없는 구버전 백업은 기존 업적을 지우지 않는다.
    expect(storage.getUnlockedAchievements(), isNotEmpty);
  });

  test('망가진 백업은 기존 데이터를 건드리기 전에 예외를 던진다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);

    await expectLater(service.restore('{"stats": "oops"}'), throwsA(isA<TypeError>()));
    // 파싱 단계에서 실패했으므로 기존 데이터는 그대로다.
    expect(storage.getQuests(), isNotEmpty);
    expect(storage.getGoals(), isNotEmpty);
  });
}
