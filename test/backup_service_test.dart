import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/asset_snapshot.dart';
import 'package:human_status/models/financial_plan.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/models/user_profile.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/onboarding_gate.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/fake_secret_store.dart';
import 'helpers/test_app.dart';

Future<StorageService> _seededStorage() async {
  final storage = await createTestStorage();
  final health = storage.getStat('health')!;
  health.level = 4;
  health.currentXp = 55;
  await storage.saveStat(health);
  await storage.saveQuest(
    Quest(
      id: 'q1',
      title: '아침 운동',
      description: '30분',
      statRewards: {'health': 30},
      status: QuestStatus.completed,
      createdAt: DateTime(2026, 6, 1),
      completedAt: DateTime(2026, 6, 2),
      goalId: 'g1',
    ),
  );
  await storage.saveGoal(
    Goal(
      id: 'g1',
      title: '여름 몸만들기',
      description: '',
      statId: 'health',
      targetDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 6, 1),
    ),
  );
  await storage.saveTransaction(
    Transaction(
      id: 't1',
      type: TransactionType.expense,
      category: '식비',
      memo: '점심',
      amount: 12000,
      date: DateTime(2026, 7, 1),
      createdAt: DateTime(2026, 7, 1),
    ),
  );
  await storage.saveAssetSnapshot(
    AssetSnapshot(
      id: 'a1',
      importedAt: DateTime(2026, 7, 1),
      assetsByCategory: {'예금': 5000000},
      liabilitiesByCategory: {'대출': 1000000},
      totalAssets: 5000000,
      totalLiabilities: 1000000,
    ),
  );
  await storage.unlockAchievement('first_quest', DateTime(2026, 6, 2, 10));
  await storage.saveFinancialPlan(
    FinancialPlan(
      updatedAt: DateTime(2026, 7, 1),
      retirementEnabled: true,
      currentAge: 30,
      retirementAge: 60,
      monthlyLivingCostAfterRetirement: 2500000,
      monthlyBudget: 1500000,
      categoryBudgets: {'식비': 400000},
    ),
  );
  // 기기 설정(API 키·알림)은 restore가 절대 건드리면 안 되는 값이라, 성공·
  // 실패 양쪽에서 그대로인지 검증할 수 있도록 값을 채워둔다. API 키는 이제
  // profileBox가 아니라 보안 저장소를 통해 관리된다.
  await storage.saveClaudeApiKey('device-secret-key');
  final profile = storage.getProfile();
  profile.reminderMinutesSinceMidnight = 480;
  await storage.saveProfile(profile);
  return storage;
}

void main() {
  test('encode → restore 왕복 후 모든 데이터가 그대로 복원된다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final backup = service.encode();

    final decoded = jsonDecode(backup) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], BackupService.currentSchemaVersion);
    // 백업 JSON에는 API 키가 어떤 형태로도 담기면 안 된다.
    expect(backup, isNot(contains('device-secret-key')));
    expect(backup, isNot(contains('claudeApiKey')));

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
    // 기기 설정도 백업 이후 바뀔 수 있다 — restore가 이 값을 건드리지 않고
    // 그대로 둬야 하므로 미리 다른 값으로 바꿔둔다.
    await storage.saveClaudeApiKey('changed-after-backup');
    final deviceProfile = storage.getProfile();
    deviceProfile.reminderMinutesSinceMidnight = 600;
    await storage.saveProfile(deviceProfile);

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

    expect(storage.getUnlockedAchievements(), {
      'first_quest': DateTime(2026, 6, 2, 10),
    });

    // 기기 설정은 백업/복원 대상이 아니므로 복원 이후 값이 바뀌면 안 된다
    // — restore 시점에 있던 값(변경 후 값)이 그대로 남아 있어야 한다.
    expect(storage.claudeApiKey, 'changed-after-backup');
    final restoredProfile = storage.getProfile();
    expect(restoredProfile.reminderMinutesSinceMidnight, 600);
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
    // 업적도 replace-all — 업적 키가 없는 구버전 백업은 기존 업적을 남기지 않는다.
    expect(storage.getUnlockedAchievements(), isEmpty);
  });

  test('망가진 백업은 기존 데이터를 건드리기 전에 예외를 던진다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);

    await expectLater(
      service.restore('{"stats": "oops"}'),
      throwsA(isA<TypeError>()),
    );
    // 파싱 단계에서 실패했으므로 기존 데이터는 그대로다.
    expect(storage.getQuests(), isNotEmpty);
    expect(storage.getGoals(), isNotEmpty);
  });

  test('preferences가 타입이 잘못된 백업은 다른 데이터를 건드리기 전에 예외를 던진다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final malformed = jsonEncode({
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
      'preferences': 'not-an-object',
    });

    await expectLater(
      service.restore(malformed),
      throwsA(isA<FormatException>()),
    );
    // preferences 검증은 다른 섹션들과 마찬가지로 clear보다 먼저 실행돼야
    // 하므로, 기존 퀘스트·목표가 그대로 남아 있어야 한다.
    expect(storage.getQuests(), isNotEmpty);
    expect(storage.getGoals(), isNotEmpty);
  });

  test('preferences.onboardingCompleted 타입이 잘못돼도 clear 전에 예외를 던진다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final malformed = jsonEncode({
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
      'preferences': {'onboardingCompleted': 'yes', 'preferredStatId': null},
    });

    await expectLater(
      service.restore(malformed),
      throwsA(isA<FormatException>()),
    );
    expect(storage.getQuests(), isNotEmpty);
  });

  test('preferences.preferredStatId가 명시적으로 null이면 기존 선호를 지운다', () async {
    final storage = await _seededStorage();
    final profile = storage.getProfile();
    profile.preferredStatId = 'wealth';
    await storage.saveProfile(profile);

    final backupWithExplicitNull = jsonEncode({
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
      'preferences': {'onboardingCompleted': true, 'preferredStatId': null},
    });

    await BackupService(storage: storage).restore(backupWithExplicitNull);

    expect(storage.getProfile().preferredStatId, isNull);
  });

  test('preferences 키 자체가 없는 구버전 백업을 신규 미완료 프로필에 복원해도 온보딩에 갇히지 않는다', () async {
    final storage = await _seededStorage();
    // 방금 설치한 기기처럼 프로필을 신규(미완료) 상태로 되돌린다.
    await storage.saveProfile(UserProfile());
    expect(storage.getProfile().onboardingCompleted, isFalse);

    final legacy = jsonEncode({
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
    });

    await BackupService(storage: storage).restore(legacy);

    // preferences가 없는 백업을 가져온 것 자체가 기존 사용자라는 신호이므로
    // 완료 처리된다 — shouldShowOnboarding 게이트로도 확인한다.
    expect(storage.getProfile().onboardingCompleted, isTrue);
    expect(shouldShowOnboarding(storage), isFalse);
  });

  test('지원하지 않는 미래 schemaVersion은 clear 전에 예외를 던진다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final future = jsonEncode({
      'schemaVersion': 2,
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
    });

    await expectLater(service.restore(future), throwsA(isA<FormatException>()));
    expect(storage.getQuests(), isNotEmpty);
    expect(storage.getGoals(), isNotEmpty);
  });

  test('schemaVersion 키가 명시적으로 null이면(구버전 취급하지 않음) clear 전에 예외를 던진다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final malformed = jsonEncode({
      'schemaVersion': null,
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
    });

    await expectLater(
      service.restore(malformed),
      throwsA(isA<FormatException>()),
    );
    expect(storage.getQuests(), isNotEmpty);
    expect(storage.getGoals(), isNotEmpty);
  });

  test('schemaVersion이 정수가 아니면(문자열) clear 전에 예외를 던진다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final malformed = jsonEncode({
      'schemaVersion': '1',
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
    });

    await expectLater(
      service.restore(malformed),
      throwsA(isA<FormatException>()),
    );
    expect(storage.getQuests(), isNotEmpty);
    expect(storage.getGoals(), isNotEmpty);
  });

  test('schemaVersion이 정수가 아니면(소수) clear 전에 예외를 던진다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final malformed = jsonEncode({
      'schemaVersion': 1.5,
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
    });

    await expectLater(
      service.restore(malformed),
      throwsA(isA<FormatException>()),
    );
    expect(storage.getQuests(), isNotEmpty);
    expect(storage.getGoals(), isNotEmpty);
  });

  test('schemaVersion이 명시적으로 1인 백업도 정상 복원된다', () async {
    final storage = await _seededStorage();
    final versioned = jsonEncode({
      'schemaVersion': 1,
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
    });

    await BackupService(storage: storage).restore(versioned);

    expect(storage.getQuests().single.title, '아침 운동');
  });

  test('mutation 도중 실패하면 모든 도메인과 preferences가 정확히 원상복구되고 '
      '기기 설정은 그대로다', () async {
    final storage = await _seededStorage();
    final originalApiKey = storage.claudeApiKey;
    final originalProfile = storage.getProfile();
    final originalReminder = originalProfile.reminderMinutesSinceMidnight;
    final originalOnboarding = originalProfile.onboardingCompleted;
    final originalPreferredStatId = originalProfile.preferredStatId;
    final originalStats = storage.getStats().map((s) => s.toJson()).toList();
    final originalQuests = storage.getQuests().map((q) => q.toJson()).toList();
    final originalGoals = storage.getGoals().map((g) => g.toJson()).toList();
    final originalTransactions = storage
        .getTransactions()
        .map((t) => t.toJson())
        .toList();
    final originalAssetSnapshots = storage
        .getAssetSnapshots()
        .map((a) => a.toJson())
        .toList();
    final originalPlan = storage.getFinancialPlan().toJson();
    final originalAchievements = storage.getUnlockedAchievements();

    final service = BackupService(storage: storage);
    // 새로운(원본과 다른) 내용으로 가져오기를 시도한다.
    final incoming = jsonEncode({
      'schemaVersion': 1,
      'stats': [Stat(id: 'health', name: '건강', icon: '💪', level: 9).toJson()],
      'quests': <Map<String, dynamic>>[],
      'goals': <Map<String, dynamic>>[],
      'transactions': <Map<String, dynamic>>[],
      'assetSnapshots': <Map<String, dynamic>>[],
      'achievements': <String, dynamic>{},
      'preferences': {'onboardingCompleted': true, 'preferredStatId': 'wealth'},
    });

    // 첫 박스(stats)가 지워지고 다시 쓰인 직후 딱 한 번 실패를 주입한다 —
    // 이미 일부 도메인이 mutate된 상태에서 실패가 나야 rollback을 제대로
    // 검증할 수 있다.
    var injected = false;
    service.debugApplyFaultInjector = () {
      injected = true;
      throw StateError('injected apply failure');
    };

    await expectLater(
      service.restore(incoming),
      throwsA(isA<BackupRestoreException>()),
    );
    expect(injected, isTrue);

    // 모든 도메인이 정확히 원래 값으로 복구됐는지 확인한다.
    expect(storage.getStats().map((s) => s.toJson()).toList(), originalStats);
    expect(storage.getQuests().map((q) => q.toJson()).toList(), originalQuests);
    expect(storage.getGoals().map((g) => g.toJson()).toList(), originalGoals);
    expect(
      storage.getTransactions().map((t) => t.toJson()).toList(),
      originalTransactions,
    );
    expect(
      storage.getAssetSnapshots().map((a) => a.toJson()).toList(),
      originalAssetSnapshots,
    );
    expect(storage.getFinancialPlan().toJson(), originalPlan);
    expect(storage.getUnlockedAchievements(), originalAchievements);

    // preferences(온보딩·우선 스탯)도 원래 값으로 복구된다.
    final restoredProfile = storage.getProfile();
    expect(restoredProfile.onboardingCompleted, originalOnboarding);
    expect(restoredProfile.preferredStatId, originalPreferredStatId);
    // 기기 설정은 애초에 이번 restore 시도가 실패했으니 손도 대지 않은
    // 상태여야 한다.
    expect(storage.claudeApiKey, originalApiKey);
    expect(restoredProfile.reminderMinutesSinceMidnight, originalReminder);

    // 주입한 실패는 한 번만 발동해야 한다 — rollback 자체가 다시 같은
    // 박스들을 쓰는데, 이때 재발동하면 rollback을 방해하게 된다.
    expect(service.debugApplyFaultInjector, isNull);
  });

  test('apply와 rollback이 모두 실패하면 두 원인이 그대로 노출된다', () async {
    final storage = await _seededStorage();
    final service = BackupService(storage: storage);
    final incoming = jsonEncode({
      'schemaVersion': 1,
      'stats': [Stat(id: 'health', name: '건강', icon: '💪', level: 9).toJson()],
      'quests': <Map<String, dynamic>>[],
    });

    final applyFailure = StateError('injected apply failure');
    final rollbackFailure = StateError('injected rollback failure');
    var applyInjected = false;
    var rollbackInjected = false;
    service.debugApplyFaultInjector = () {
      applyInjected = true;
      throw applyFailure;
    };
    service.debugRollbackFaultInjector = () {
      rollbackInjected = true;
      throw rollbackFailure;
    };

    Object? thrown;
    try {
      await service.restore(incoming);
    } catch (e) {
      thrown = e;
    }

    expect(applyInjected, isTrue);
    expect(rollbackInjected, isTrue);
    // 두 실패 모두 발동은 한 번만 되어야 한다 — 재발동하면 나머지 도메인의
    // apply/rollback을 방해하게 된다.
    expect(service.debugApplyFaultInjector, isNull);
    expect(service.debugRollbackFaultInjector, isNull);

    expect(thrown, isA<BackupRestoreRollbackFailedException>());
    final failure = thrown as BackupRestoreRollbackFailedException;
    // 원인과 스택 트레이스 둘 다 그대로 보존되어야 한다 — 어느 쪽도 삼켜지면
    // 안 된다.
    expect(failure.applyError, same(applyFailure));
    expect(failure.rollbackError, same(rollbackFailure));
    expect(failure.applyStackTrace, isNotNull);
    expect(failure.rollbackStackTrace, isNotNull);
    expect(failure.toString(), contains('injected apply failure'));
    expect(failure.toString(), contains('injected rollback failure'));
    expect(failure.toString(), contains('partial'));
  });

  test('보안 저장소가 사용 불가능해 API 키가 프로필의 유일한 복사본인 상태에서, '
      'restore 도중 실패해도 rollback이 그 유일한 복사본을 지우지 않는다', () async {
    final secretStore = FakeSecretStore()..failWrite = true;
    final storage = StorageService(inMemory: true, secretStore: secretStore);
    await storage.init();
    addTearDown(Hive.close);
    final health = storage.getStat('health')!;
    health.level = 4;
    await storage.saveStat(health);
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '아침 운동',
        description: '',
        statRewards: {'health': 30},
        createdAt: DateTime(2026, 6, 1),
      ),
    );
    final profile = storage.getProfile();
    profile.claudeApiKey = 'sk-legacy-only-copy';
    await storage.saveProfile(profile);
    // 마이그레이션이 실패한 채로 유지되도록 재초기화한다.
    await storage.init();
    expect(storage.claudeApiKey, 'sk-legacy-only-copy');

    final service = BackupService(storage: storage);
    final incoming = jsonEncode({
      'schemaVersion': 1,
      'stats': [Stat(id: 'health', name: '건강', icon: '💪', level: 9).toJson()],
      'quests': <Map<String, dynamic>>[],
    });
    service.debugApplyFaultInjector = () {
      throw StateError('injected apply failure');
    };

    await expectLater(
      service.restore(incoming),
      throwsA(isA<BackupRestoreException>()),
    );

    // rollback 이후에도 유일한 복사본(레거시 필드)과 유효 키가 그대로다.
    expect(storage.claudeApiKey, 'sk-legacy-only-copy');
    expect(storage.getProfile().claudeApiKey, 'sk-legacy-only-copy');

    // 재초기화해도 사라지지 않는다.
    await storage.init();
    expect(storage.claudeApiKey, 'sk-legacy-only-copy');
  });

  test('보안 저장소가 사용 불가능해 API 키가 프로필의 유일한 복사본인 상태에서, '
      '성공적인 restore도 그 유일한 복사본을 보존한다', () async {
    final secretStore = FakeSecretStore()..failWrite = true;
    final storage = StorageService(inMemory: true, secretStore: secretStore);
    await storage.init();
    addTearDown(Hive.close);
    await storage.saveQuest(
      Quest(
        id: 'q1',
        title: '아침 운동',
        description: '',
        statRewards: {'health': 30},
        createdAt: DateTime(2026, 6, 1),
      ),
    );
    final profile = storage.getProfile();
    profile.claudeApiKey = 'sk-legacy-only-copy';
    await storage.saveProfile(profile);
    await storage.init();
    expect(storage.claudeApiKey, 'sk-legacy-only-copy');

    final service = BackupService(storage: storage);
    final backup = service.encode();
    expect(backup, isNot(contains('sk-legacy-only-copy')));

    await service.restore(backup);

    expect(storage.claudeApiKey, 'sk-legacy-only-copy');
    expect(storage.getProfile().claudeApiKey, 'sk-legacy-only-copy');
  });

  group('inspect (미리보기, mutation 없음)', () {
    test('유효한 백업의 정확한 개수와 financialPlan 여부를 반환하고 storage를 바꾸지 않는다', () async {
      final storage = await _seededStorage();
      final service = BackupService(storage: storage);
      final backup = service.encode();

      final originalStats = storage.getStats().map((s) => s.toJson()).toList();
      final originalQuests = storage
          .getQuests()
          .map((q) => q.toJson())
          .toList();

      final preview = service.inspect(backup);

      expect(preview.statsCount, storage.getStats().length);
      expect(preview.questsCount, 1);
      expect(preview.goalsCount, 1);
      expect(preview.transactionsCount, 1);
      expect(preview.assetSnapshotsCount, 1);
      expect(preview.achievementsCount, 1);
      expect(preview.hasFinancialPlan, isTrue);

      // 검사만으로는 아무것도 바뀌지 않는다.
      expect(storage.getStats().map((s) => s.toJson()).toList(), originalStats);
      expect(
        storage.getQuests().map((q) => q.toJson()).toList(),
        originalQuests,
      );
    });

    test('financialPlan이 없는 백업은 hasFinancialPlan이 false다', () async {
      final storage = await _seededStorage();
      final legacy = jsonEncode({
        'stats': storage.getStats().map((s) => s.toJson()).toList(),
        'quests': storage.getQuests().map((q) => q.toJson()).toList(),
      });

      final preview = BackupService(storage: storage).inspect(legacy);

      expect(preview.hasFinancialPlan, isFalse);
      expect(preview.goalsCount, 0);
      expect(preview.transactionsCount, 0);
      expect(preview.achievementsCount, 0);
    });

    test('malformed 백업은 storage를 건드리기 전에 예외를 던진다', () async {
      final storage = await _seededStorage();
      final service = BackupService(storage: storage);

      expect(
        () => service.inspect('{"stats": "oops"}'),
        throwsA(isA<TypeError>()),
      );
      expect(storage.getQuests(), isNotEmpty);
    });

    test('지원하지 않는 schemaVersion은 storage를 건드리기 전에 예외를 던진다', () async {
      final storage = await _seededStorage();
      final service = BackupService(storage: storage);
      final future = jsonEncode({
        'schemaVersion': 2,
        'stats': storage.getStats().map((s) => s.toJson()).toList(),
        'quests': storage.getQuests().map((q) => q.toJson()).toList(),
      });

      expect(() => service.inspect(future), throwsA(isA<FormatException>()));
      expect(storage.getQuests(), isNotEmpty);
    });

    test('preferences 타입이 잘못된 백업은 storage를 건드리기 전에 예외를 던진다', () async {
      final storage = await _seededStorage();
      final service = BackupService(storage: storage);
      final malformed = jsonEncode({
        'stats': storage.getStats().map((s) => s.toJson()).toList(),
        'quests': storage.getQuests().map((q) => q.toJson()).toList(),
        'preferences': 'not-an-object',
      });

      expect(() => service.inspect(malformed), throwsA(isA<FormatException>()));
      expect(storage.getQuests(), isNotEmpty);
    });

    test('inspect와 restore는 같은 백업에 대해 동일한 판정을 내린다', () async {
      final storage = await _seededStorage();
      final service = BackupService(storage: storage);
      final backup = service.encode();

      // inspect가 통과시킨 백업은 restore도 성공해야 한다.
      final preview = service.inspect(backup);
      await service.restore(backup);
      expect(storage.getQuests().length, preview.questsCount);

      const badVersion = '{"schemaVersion": 99, "stats": [], "quests": []}';
      // inspect가 거부한 백업은 restore도 거부해야 한다(같은 파서 사용).
      expect(
        () => service.inspect(badVersion),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        service.restore(badVersion),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
