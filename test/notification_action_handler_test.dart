import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/services/notification_action_handler.dart';
import 'package:human_status/services/notification_action_payload.dart';
import 'package:human_status/services/notification_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:human_status/services/xp_service.dart';

/// Keeps its Hive boxes open after [close] (which production calls once done)
/// so a test can still make assertions against the same instance afterward.
/// `addTearDown(Hive.close)` in each test does the real cleanup instead, once
/// the test body itself has finished.
class _NonClosingStorage extends StorageService {
  _NonClosingStorage() : super(inMemory: true);

  @override
  Future<void> close() async {}
}

Future<_NonClosingStorage> _storage() async {
  final storage = _NonClosingStorage();
  await storage.init();
  return storage;
}

class _RecordingNotificationService extends NotificationService {
  final results = <({String title, String body})>[];
  final dailyReminderTargets = <DailyReminderQuestTarget?>[];

  @override
  Future<void> init({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {}

  @override
  Future<void> showQuestCompletionResult({
    required String title,
    required String body,
  }) async {
    results.add((title: title, body: body));
  }

  @override
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
    int activeQuestCount = 0,
    DailyReminderQuestTarget? completionTarget,
  }) async {
    dailyReminderTargets.add(completionTarget);
    return true;
  }

  @override
  Future<bool> scheduleWeeklyReportReminder() async => true;
}

Quest _quest(
  String id, {
  String title = '아침 스트레칭',
  Map<String, double> statRewards = const {'health': 10},
  QuestStatus status = QuestStatus.active,
  String? goalId,
}) => Quest(
  id: id,
  title: title,
  description: '',
  statRewards: statRewards,
  status: status,
  goalId: goalId,
  createdAt: DateTime(2026, 7, 20),
);

NotificationResponse _actionResponse(String? payload) => NotificationResponse(
  notificationResponseType: NotificationResponseType.selectedNotificationAction,
  actionId: NotificationService.completeQuestActionId,
  payload: payload,
);

String _payloadFor(
  StorageService storage, {
  String actionToken = 'tok-1',
  String questId = 'q1',
  String questTitle = '아침 스트레칭',
  DateTime? scheduledAt,
}) => DailyQuestNotificationPayload(
  actionToken: actionToken,
  installationId: storage.installationId,
  questId: questId,
  questTitle: questTitle,
  scheduledAt: scheduledAt ?? DateTime.now().toUtc(),
).toJsonString();

void main() {
  group('빠른 no-op (저장소를 열지 않음)', () {
    test('completeQuestActionId가 아닌 액션은 무시한다', () async {
      var storageOpened = false;
      await dispatchNotificationResponse(
        actionsEnabled: true,
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'some_other_action',
        ),
        createStorage: () async {
          storageOpened = true;
          throw StateError('storage should never be opened');
        },
      );
      expect(storageOpened, isFalse);
    });

    test('일반 알림 탭(actionId 없음)은 무시한다', () async {
      var storageOpened = false;
      await dispatchNotificationResponse(
        actionsEnabled: true,
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
        ),
        createStorage: () async {
          storageOpened = true;
          throw StateError('storage should never be opened');
        },
      );
      expect(storageOpened, isFalse);
    });

    test('payload가 깨져 있으면 무시한다', () async {
      var storageOpened = false;
      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse('{not valid json'),
        createStorage: () async {
          storageOpened = true;
          throw StateError('storage should never be opened');
        },
      );
      expect(storageOpened, isFalse);
    });

    test('payload가 없으면 무시한다', () async {
      var storageOpened = false;
      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(null),
        createStorage: () async {
          storageOpened = true;
          throw StateError('storage should never be opened');
        },
      );
      expect(storageOpened, isFalse);
    });
  });

  group('성공 경로', () {
    test('정상 완료(특별 이벤트 없음): XP만 지급되고 일반 완료 알림이 뜬다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      // first_quest 업적이 이번 완료로 "새로" 잠기지 않도록 미리 잠가 둔다 —
      // 그래야 이 케이스가 진짜 "특별 이벤트 없음"이 된다.
      await storage.unlockAchievement('first_quest', DateTime(2020, 1, 1));
      await storage.saveQuest(_quest('q1', statRewards: {'health': 10}));
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(storage.getQuest('q1')!.status, QuestStatus.completed);
      expect(storage.getStat('health')!.currentXp, 10);
      expect(fake.results, hasLength(1));
      expect(fake.results.single.title, '퀘스트 완료!');
      expect(fake.results.single.body, '"아침 스트레칭"을 완료하고 XP를 받았어요.');
      expect(
        storage.getActionTokenRecord('tok-1')!.status,
        ActionTokenStatus.completed,
      );
    });

    test('레벨업이 발생하면 레벨업 전용 문구를 보여준다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.unlockAchievement('first_quest', DateTime(2020, 1, 1));
      // xpToNextLevel(1) == 100 — 정확히 레벨 2로 오른다.
      await storage.saveQuest(_quest('q1', statRewards: {'health': 100}));
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(fake.results.single.title, '퀘스트 완료 · 레벨업!');
      expect(fake.results.single.body, contains('건강 레벨 2'));
      expect(fake.results.single.body, contains('앱을 열어 확인하세요.'));
    });

    test('새 업적이 잠기면 업적 전용 문구를 보여준다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      // first_quest를 미리 잠그지 않으므로 이 완료가 그 업적을 정확히 하나
      // 새로 해금한다.
      await storage.saveQuest(_quest('q1', statRewards: {'health': 10}));
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(fake.results.single.title, '퀘스트 완료 · 새 업적!');
      expect(fake.results.single.body, contains('첫 걸음'));
    });

    test('연결된 목표가 자동완료되면(레벨업과 함께) 여러 이벤트 요약 문구를 보여준다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.unlockAchievement('first_quest', DateTime(2020, 1, 1));
      await storage.saveGoal(_goal('g1'));
      await storage.saveQuest(
        _quest('q1', statRewards: {'health': 100}, goalId: 'g1'),
      );
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(fake.results.single.title, '퀘스트 완료!');
      expect(fake.results.single.body, contains('레벨업'));
      expect(fake.results.single.body, contains('목표 완료'));
    });

    test('완료 성공 후 일일 리마인더가 변경된 활성 목록으로 재예약된다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      final profile = storage.getProfile();
      profile.reminderMinutesSinceMidnight = 9 * 60;
      await storage.saveProfile(profile);
      await storage.saveQuest(_quest('q1', title: '완료할 퀘스트'));
      await storage.saveQuest(_quest('q2', title: '남은 퀘스트'));
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage, questId: 'q1')),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(fake.dailyReminderTargets, hasLength(1));
      final target = fake.dailyReminderTargets.single;
      expect(target, isNotNull);
      expect(target!.questId, 'q2');
      expect(target.questTitle, '남은 퀘스트');
    });
  });

  group('no-op 결과 (완료되지 않음)', () {
    test('존재하지 않는 퀘스트는 상태 확인 알림만 뜬다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage, questId: 'missing')),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(fake.results.single.title, '퀘스트 상태를 확인했어요');
      expect(fake.results.single.body, '이미 완료되었거나 삭제된 퀘스트예요.');
    });

    test('이미 완료된 퀘스트는 상태 확인 알림만 뜨고 XP가 재지급되지 않는다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.saveQuest(
        _quest('q1', status: QuestStatus.completed, statRewards: {'health': 10}),
      );
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(storage.getStat('health')!.currentXp, 0);
      expect(fake.results.single.title, '퀘스트 상태를 확인했어요');
    });

    test('추천(suggested) 상태 퀘스트는 no-op이다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.saveQuest(_quest('q1', status: QuestStatus.suggested));
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(storage.getQuest('q1')!.status, QuestStatus.suggested);
      expect(fake.results.single.title, '퀘스트 상태를 확인했어요');
    });
  });

  group('설치/토큰 검증', () {
    test('다른 installationId의 payload는 아무 것도 바꾸지 않고 조용히 폐기된다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.saveQuest(_quest('q1'));
      final fake = _RecordingNotificationService();

      final foreignPayload = DailyQuestNotificationPayload(
        actionToken: 'tok-1',
        installationId: 'some-other-install',
        questId: 'q1',
        questTitle: '아침 스트레칭',
        scheduledAt: DateTime.now().toUtc(),
      ).toJsonString();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(foreignPayload),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(storage.getQuest('q1')!.status, QuestStatus.active);
      expect(fake.results, isEmpty);
    });

    test('completed로 기록된 토큰이 재전달되면 즉시 no-op한다 (XP 재지급 없음)', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.saveQuest(_quest('q1', status: QuestStatus.completed));
      await storage.recordActionToken(
        'tok-1',
        ActionTokenStatus.completed,
        DateTime.now().toUtc(),
      );
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(fake.results, isEmpty);
    });

    test('processing 상태가 만료 전이면 중복 전달을 무시한다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.saveQuest(_quest('q1'));
      await storage.recordActionToken(
        'tok-1',
        ActionTokenStatus.processing,
        DateTime.now().toUtc(),
      );
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      // 여전히 active — 중복 배달이 완료 트랜잭션을 실행하지 않았다.
      expect(storage.getQuest('q1')!.status, QuestStatus.active);
      expect(fake.results, isEmpty);
    });

    test('processing 상태가 만료되었으면 현재 상태를 다시 검증해 정상 완료한다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.saveQuest(_quest('q1'));
      await storage.unlockAchievement('first_quest', DateTime(2020, 1, 1));
      await storage.recordActionToken(
        'tok-1',
        ActionTokenStatus.processing,
        DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
      );
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      expect(storage.getQuest('q1')!.status, QuestStatus.completed);
      expect(fake.results.single.title, '퀘스트 완료!');
      expect(
        storage.getActionTokenRecord('tok-1')!.status,
        ActionTokenStatus.completed,
      );
    });
  });

  group('실패 경로', () {
    test('완료 트랜잭션이 실패하면 롤백되고, 실패로 기록되며, 실패 알림이 뜬다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.saveQuest(_quest('q1', statRewards: {'health': 10}));
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
        containerOverrides: [
          statsProvider.overrideWith(
            (ref) => _ThrowingStatsNotifier(ref.watch(storageServiceProvider)),
          ),
        ],
      );

      // 데이터는 임의로 바뀌지 않았다 — 퀘스트는 여전히 active.
      expect(storage.getQuest('q1')!.status, QuestStatus.active);
      expect(storage.getStat('health')!.currentXp, 0);
      expect(fake.results.single.title, '완료 처리하지 못했어요');
      expect(fake.results.single.body, '데이터는 임의로 변경하지 않았습니다. 앱에서 다시 시도해 주세요.');
      expect(
        storage.getActionTokenRecord('tok-1')!.status,
        ActionTokenStatus.failed,
      );
    });

    test('저장소 초기화 자체가 실패해도 예외를 밖으로 던지지 않는다', () async {
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(
          DailyQuestNotificationPayload(
            actionToken: 'tok-1',
            installationId: 'whatever',
            questId: 'q1',
            questTitle: '아침 스트레칭',
            scheduledAt: DateTime.now().toUtc(),
          ).toJsonString(),
        ),
        createStorage: () async => throw StateError('storage init boom'),
        notificationService: fake,
      );

      expect(fake.results.single.title, '완료 처리하지 못했어요');
    });

    test('결과 알림 표시 자체가 실패해도 이미 커밋된 완료를 되돌리지 않는다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.unlockAchievement('first_quest', DateTime(2020, 1, 1));
      await storage.saveQuest(_quest('q1'));

      await dispatchNotificationResponse(
        actionsEnabled: true,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: _AlwaysFailsToShowNotificationService(),
      );

      expect(storage.getQuest('q1')!.status, QuestStatus.completed);
      expect(
        storage.getActionTokenRecord('tok-1')!.status,
        ActionTokenStatus.completed,
      );
    });
  });

  group('actionsEnabled 플래그 (kQuestCompletionNotificationActionEnabled 기본값)', () {
    test('플래그를 명시하지 않으면 기본값(false)이 적용되어 완전히 no-op한다', () async {
      var storageOpened = false;
      final fake = _RecordingNotificationService();

      // actionsEnabled를 일부러 지정하지 않는다 — 프로덕션 기본값
      // (kQuestCompletionNotificationActionEnabled == false)이 실제로
      // 이 진입점을 잠그는지를 검증하는 테스트다.
      await dispatchNotificationResponse(
        _actionResponse(
          DailyQuestNotificationPayload(
            actionToken: 'tok-1',
            installationId: 'whatever',
            questId: 'q1',
            questTitle: '아침 스트레칭',
            scheduledAt: DateTime.now().toUtc(),
          ).toJsonString(),
        ),
        createStorage: () async {
          storageOpened = true;
          throw StateError('storage should never be opened while disabled');
        },
        notificationService: fake,
      );

      expect(storageOpened, isFalse);
      expect(fake.results, isEmpty);
    });

    test('actionsEnabled: false를 명시해도 완전히 no-op한다', () async {
      final storage = await _storage();
      addTearDown(Hive.close);
      await storage.saveQuest(_quest('q1'));
      final fake = _RecordingNotificationService();

      await dispatchNotificationResponse(
        actionsEnabled: false,
        _actionResponse(_payloadFor(storage)),
        createStorage: () async => storage,
        notificationService: fake,
      );

      // 퀘스트는 건드려지지 않았고, 결과 알림도 전혀 뜨지 않았다.
      expect(storage.getQuest('q1')!.status, QuestStatus.active);
      expect(fake.results, isEmpty);
    });
  });

  group('foreground storage 재사용 (closeStorage: false)', () {
    test(
      'closeStorage: false면 dispatcher 종료 후에도 공유 storage의 Hive box가 열려 있다',
      () async {
        final storage = StorageService(inMemory: true);
        await storage.init();
        addTearDown(Hive.close);
        await storage.unlockAchievement('first_quest', DateTime(2020, 1, 1));
        await storage.saveQuest(_quest('q1'));
        final fake = _RecordingNotificationService();

        await dispatchNotificationResponse(
          actionsEnabled: true,
          _actionResponse(_payloadFor(storage)),
          createStorage: () async => storage,
          notificationService: fake,
          closeStorage: false,
        );

        // 완료 자체는 정상적으로 처리됐고...
        expect(storage.getQuest('q1')!.status, QuestStatus.completed);
        // ...그러면서도 같은 isolate의 Hive box가 전혀 닫히지 않았다 — 이게
        // foreground(앱이 이미 실행 중인 상태)에서 반드시 지켜져야 하는
        // 계약이다. main.dart의 foreground 콜백이 실제로 이 매개변수를
        // 쓴다.
        expect(storage.questsBox.isOpen, isTrue);
        expect(storage.settingsBox.isOpen, isTrue);
        // 닫히지 않았으니 계속 정상적으로 읽고 쓸 수 있다.
        await storage.saveQuest(_quest('q2', title: '여전히 동작함'));
        expect(storage.getQuest('q2')!.title, '여전히 동작함');
      },
    );

    test(
      'closeStorage 기본값(true)이면 dispatcher 종료 후 storage의 Hive box가 닫힌다 (배경 경로 회귀 방지)',
      () async {
        final storage = StorageService(inMemory: true);
        await storage.init();
        addTearDown(Hive.close);
        await storage.saveQuest(_quest('q1'));
        final fake = _RecordingNotificationService();

        await dispatchNotificationResponse(
          actionsEnabled: true,
          _actionResponse(_payloadFor(storage)),
          createStorage: () async => storage,
          notificationService: fake,
        );

        expect(storage.questsBox.isOpen, isFalse);
      },
    );
  });
}

/// A goal helper local to this test file (mirrors completion_reward_integrity_test.dart's).
Goal _goal(String id, {String statId = 'health'}) => Goal(
  id: id,
  title: '목표 $id',
  description: '',
  statId: statId,
  createdAt: DateTime(2026, 7, 14),
);

class _ThrowingStatsNotifier extends StatsNotifier {
  _ThrowingStatsNotifier(super.storage);

  @override
  Future<LevelUpResult> applyXp(String statId, double xp) async {
    throw StateError('simulated stat write failure');
  }
}

class _AlwaysFailsToShowNotificationService extends NotificationService {
  @override
  Future<void> init({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {}

  @override
  Future<void> showQuestCompletionResult({
    required String title,
    required String body,
  }) async {
    throw StateError('simulated notification display failure');
  }

  @override
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
    int activeQuestCount = 0,
    DailyReminderQuestTarget? completionTarget,
  }) async => true;

  @override
  Future<bool> scheduleWeeklyReportReminder() async => true;
}
