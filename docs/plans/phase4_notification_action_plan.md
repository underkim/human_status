# Phase 4 — 알림 액션으로 퀘스트 즉시 완료 구현 계획

## 0. 결론

이 기능은 `flutter_local_notifications: ^22.0.1`로 구현할 수 있다. 다만 **Dart 코드만으로 끝나지는 않는다.**

- Android: `AndroidNotificationAction`과 `onDidReceiveBackgroundNotificationResponse`를 지원한다. 앱 프로세스가 없을 때도 UI를 띄우지 않는 액션이 별도 Flutter 엔진/백그라운드 isolate를 시작할 수 있다. `android/app/src/main/AndroidManifest.xml`에 플러그인의 `ActionBroadcastReceiver` 등록이 필수다.
- iOS: `DarwinNotificationAction`/`DarwinNotificationCategory`와 백그라운드 응답을 지원한다. `ios/Runner/AppDelegate.swift`에 `UNUserNotificationCenterDelegate` 지정 및 백그라운드 엔진용 `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` 설정이 필요하다. 이 기능만을 위한 `Info.plist` 키는 없다.
- 현재 리마인더는 `activeQuestCount`만 본문에 넣고, 퀘스트 ID/제목이나 `payload`는 넣지 않는다. 그대로는 어느 퀘스트를 완료할지 알 수 없다.
- 옵션 A(기존 일일 리마인더 개선)를 선택한다. 예약 시 활성 퀘스트가 **정확히 1개일 때만** 그 퀘스트의 ID와 제목을 담고 `오늘의 퀘스트 완료` 액션을 노출한다. 0개 또는 2개 이상이면 완료 액션을 노출하지 않고 앱에서 선택하도록 안내한다. 별도 알림 종류(옵션 B)는 같은 시간에 알림이 중복되고 설정·취소·권한·채널 관리가 이원화되므로 선택하지 않는다.
- 1차 제품 지원 범위는 Android/iOS다. macOS/Linux/Windows/Web에는 완료 액션을 노출하지 않는다. 아래 플랫폼 표의 제한이 해소되고 종료 상태 통합 검증이 가능할 때 별도 Phase로 확장한다.
- `QuestsNotifier.completeQuest(String id)`는 UI 다이얼로그를 직접 띄우지 않으므로 계산 자체는 headless 실행이 가능하지만, 현재는 Riverpod `Ref`, 여러 notifier, isolate-local `rewardLockProvider`, 이미 열린 Hive box를 전제로 한다. 따라서 백그라운드 콜백에서 단순히 호출해서는 안 된다. 저장소 초기화, 중복 방지, main/background isolate 간 배타 실행, 결과 피드백을 담당하는 별도 실행 경계를 먼저 만든다.

공식 근거:

- [flutter_local_notifications 22.0.1 — Notification Actions 및 플랫폼 설정](https://pub.dev/packages/flutter_local_notifications/versions/22.0.1)
- [22.0.1 API — AndroidNotificationDetails.actions](https://pub.dev/documentation/flutter_local_notifications/22.0.1/flutter_local_notifications/AndroidNotificationDetails/actions.html)
- [22.0.1 API — DarwinNotificationAction](https://pub.dev/documentation/flutter_local_notifications/22.0.1/flutter_local_notifications/DarwinNotificationAction-class.html)
- [플러그인 예제 AndroidManifest — ActionBroadcastReceiver](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/example/android/app/src/main/AndroidManifest.xml)
- [플러그인 예제 iOS AppDelegate](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/example/ios/Runner/AppDelegate.swift)

## 1. 현재 저장소 조사 결과

### 1.1 알림 예약

`lib/services/notification_service.dart`의 `NotificationService`는 다음 ID를 사용한다.

- `_dailyReminderId = 1`
- `_weeklyReportId = 2`
- `_budgetExceededId = 3`
- `_autoBackupFailedId = 4`

대상인 `scheduleDailyReminder()` → `scheduleDailyReminderCall()`은:

1. `activeQuestCount`만 받는다.
2. `activeQuestCount > 0`이면 “진행중인 퀘스트가 N개”라는 본문을 만든다.
3. `NotificationDetails`에 Android/iOS/macOS/Linux 상세만 넣는다.
4. `payload`, Android `actions`, Darwin `categoryIdentifier`를 넣지 않는다.
5. `DateTimeComponents.time`으로 같은 내용을 매일 반복 예약한다.

즉 본문은 개수에 따라 동적이지만 **대상 퀘스트 관점에서는 고정 스냅샷**이다. 앱이 다시 `scheduleNotifications()`를 실행하기 전에는 개수도 갱신되지 않는다.

`lib/main.dart`의 `scheduleNotifications()`는 `StorageService.getQuests()`에서 `QuestStatus.active` 개수만 계산해 `scheduleDailyReminder(activeQuestCount: ...)`에 넘긴다. `runStartupSequence()`가 `DailyRefreshController.refreshIfDue()` 뒤에 이를 호출하므로 시작 시점의 반복 퀘스트 재생성 결과는 반영하지만, 앱이 실행되지 않은 동안의 미래 상태를 알 수는 없다.

### 1.2 완료 트랜잭션

`lib/providers/quest_provider.dart`의 `QuestsNotifier.completeQuest(String id)`는 `rewardLockProvider.synchronized()` 안에서 `_completeQuestLocked()`를 실행한다. 주요 동작은 다음과 같다.

- 저장소에서 ID를 다시 읽고, 없거나 `QuestStatus.active`가 아니면 `QuestCompletionResult(didComplete: false, ...)`를 반환한다.
- `nowProvider`를 갱신하고 완료 시각을 구한다.
- `XpService.effectiveRewards(quest)`와 `statsProvider.notifier.applyXp()`로 스탯별 XP/레벨을 갱신한다.
- 퀘스트를 `QuestStatus.completed`로 바꾸고 `completedAt`을 저장한다.
- 연결된 목표가 마지막 미완료 퀘스트라면 `GoalsNotifier.completeGoalLocked()`를 호출한다.
- `AchievementService.checkAndUnlock()`로 업적을 판정한다.
- `RollbackScope`로 스탯, 퀘스트, 목표, 업적 쓰기 중 실패를 되돌린다.
- 결과로 `levelUps`, `newAchievements`, `goalCompletion`을 반환한다.

다이얼로그나 `BuildContext` 의존은 없으므로 핵심 동작은 headless 실행 가능하다. 그러나 `Ref`와 여러 provider/notifier에 의존하며, `rewardLockProvider`의 락은 Dart isolate 사이에서 공유되지 않는다. 따라서 별도 isolate에서 새 `ProviderContainer`만 만들면 “기능은 호출되지만 동시성 안전성은 보장되지 않는” 상태가 된다.

### 1.3 저장소와 앱 초기화

`lib/services/storage_service.dart`의 `StorageService.init()`은:

- 디스크 모드에서 `Hive.initFlutter()`를 실행한다.
- `StatAdapter`, `QuestAdapter`, `UserProfileAdapter`, `GoalAdapter`, `TransactionAdapter`, `AssetSnapshotAdapter`, `FinancialPlanAdapter`를 등록한다.
- `stats`, `quests`, `profile`, `achievements`, `goals`, `transactions`, `assetSnapshots`, `financialPlan`, `settings` box를 모두 연다.
- 기본 스탯/프로필을 생성하고 secure storage 마이그레이션도 시도한다.

`late Box<T>` 필드이므로 `init()` 전에 `getQuests()` 등을 호출할 수 없다. 앱이 완전히 종료되어 백그라운드 엔진만 뜬 경우 main isolate에서 열어 둔 box는 존재하지 않으므로 콜백이 반드시 바인딩/플러그인 등록 후 새 `StorageService`를 초기화해야 한다.

반대로 앱 프로세스가 살아 있는 상태에서 백그라운드 엔진이 별도 isolate로 뜨면 main isolate와 background isolate가 서로 다른 Hive box 캐시와 isolate-local 락을 갖는다. Hive 2.2.3 box를 양쪽에서 동시에 갱신하는 것을 현재 구조의 `rewardLockProvider`만으로 보호할 수 없다. 이 문제를 해결하지 않은 구현은 XP 중복 지급 또는 foreground의 오래된 캐시 표시 위험이 있으므로 출시 불가다.

`lib/main.dart`의 `main()`은 `WidgetsFlutterBinding.ensureInitialized()` 후 즉시 `runApp(AppBootstrap(...))`을 호출하고, `AppBootstrap._initialize()`가 `StorageService.init()`과 `ProviderContainer` 구성을 담당한다. 백그라운드 엔트리포인트는 `AppBootstrap`/`runApp()`을 거치지 않으므로 이 초기화를 명시적으로 재구성해야 한다.

## 2. 범위와 사용자 동작

### 2.1 포함

- 기존 `_dailyReminderId` 일일 리마인더의 문구, payload, Android 액션, iOS category 연결 개선
- 활성 퀘스트가 정확히 1개일 때 `오늘의 퀘스트 완료` 액션 제공
- 앱 UI를 열지 않는 Android/iOS 백그라운드 완료
- 성공, 이미 처리됨, 실패, 레벨업/업적/목표 완료에 대한 후속 확인 알림
- 앱 시작/퀘스트 상태 변경/백그라운드 완료 후 리마인더 재예약
- Android manifest 및 iOS AppDelegate의 플러그인 필수 설정

### 2.2 제외

- Android `AppWidgetProvider`, iOS WidgetKit 및 모든 홈 화면 위젯
- Kotlin/Swift로 퀘스트 도메인 로직 구현
- 알림에서 여러 퀘스트 목록을 펼치거나 각 퀘스트별 여러 완료 버튼 제공
- 텍스트 입력 액션, 원격 푸시, 서버 동기화
- macOS/Linux/Windows/Web의 종료 상태 즉시 완료

### 2.3 대상 선택 규칙

예약 직전 `StorageService.getQuests()`에서 `QuestStatus.active`를 다시 구한다.

- 0개: “오늘의 퀘스트를 확인해보세요” 문구, 액션 없음, payload에는 대상 없음.
- 1개: 제목을 포함한 문구(예: `아침 스트레칭을 완료했나요?`), 해당 `quest.id`를 payload에 기록, 완료 액션 노출.
- 2개 이상: “진행 중인 퀘스트가 N개 있어요. 앱에서 완료할 퀘스트를 선택하세요.” 문구, 완료 액션 없음.

여러 개 중 `nextQuestProvider`/`selectNextQuest()`가 고른 하나를 암묵적으로 완료시키지는 않는다. 추천 순위는 “먼저 보여줄 대상”이지 사용자 대신 완료할 권한이 아니며, 알림의 짧은 액션에서 오완료를 되돌리는 UX도 없다.

### 2.4 옵션 A 선택 및 반복 예약 보정

옵션 A인 기존 리마인더 개선을 선택한다. 별도 알림(옵션 B)은 같은 사용자 설정에서 리마인더와 완료 알림이 중복되고 `_dailyReminderId` 취소만으로 기능이 꺼지지 않는 문제가 생긴다.

현재 `DateTimeComponents.time` 반복 예약의 payload는 예약 시점 스냅샷이라는 한계가 있다. 다음 보정이 필수다.

1. 앱 시작 시 기존처럼 재예약한다.
2. 앱 내 퀘스트 추가/수정/삭제/채택/완료 및 일일 반복 재생성 뒤 활성 목록이 달라지면 같은 `_dailyReminderId`로 재예약한다.
3. 알림 액션 완료가 성공하면 기존 반복 예약을 취소하고, 변경된 활성 목록으로 다음 일일 리마인더를 즉시 재예약한다.
4. payload의 퀘스트가 알림 표시 전 앱에서 삭제/완료되었어도 콜백은 저장소의 현재 상태를 재검증해 no-op 처리한다.

이 보정 후에도 “앱을 열지 않은 채 다른 외부 경로가 로컬 Hive를 바꾸는 경우”는 현재 제품에 존재하지 않는다. 향후 동기화 기능이 생기면 반복 예약 대신 서버/작업 스케줄러 기반 재평가가 필요하다.

## 3. 알림 계약

### 3.1 상수

`lib/services/notification_service.dart`에 외부 테스트와 handler가 공유할 공개 또는 library-visible 상수를 둔다.

- `dailyReminderNotificationId = 1`
- `questCompletionConfirmationNotificationId`: 기존 1~4와 충돌하지 않는 새 ID
- `completeQuestActionId = 'complete_quest'`
- `dailyQuestCategoryId = 'daily_quest_single'`
- payload schema version `1`

문자열 리터럴을 콜백, 스케줄러, 테스트에 중복하지 않는다.

### 3.2 payload

JSON 객체로 직렬화한다.

```json
{
  "v": 1,
  "type": "dailyQuest",
  "actionToken": "<UUID>",
  "installationId": "<설치 식별자>",
  "questId": "<Quest.id>",
  "questTitle": "<표시용 스냅샷>",
  "scheduledAt": "<UTC ISO-8601>"
}
```

- 신뢰하는 값은 `questId`와 현재 Hive 상태뿐이다.
- `questTitle`은 후속 알림의 fallback 표시용이며 저장소 갱신 키로 사용하지 않는다.
- `actionToken`은 동일 알림 액션의 재전달/중복 탭을 식별한다.
- `installationId`는 `settingsBox`에 생성·보관하며 재설치 후 새 값이 된다. 일치하지 않는 payload는 폐기한다.
- 잘못된 JSON, 알 수 없는 버전/type, 빈 ID는 상태를 변경하지 않고 일반 실패 후속 알림만 선택적으로 표시한다.
- payload에는 XP, 보상값, 완료 여부를 담지 않는다. 모두 현재 저장소에서 재계산한다.

### 3.3 플랫폼 상세

- Android `AndroidNotificationDetails.actions`에 `AndroidNotificationAction(completeQuestActionId, '오늘의 퀘스트 완료', showsUserInterface: false, cancelNotification: true)`를 단일 대상일 때만 넣는다.
- iOS `DarwinInitializationSettings.notificationCategories`에 `DarwinNotificationCategory(dailyQuestCategoryId, actions: [DarwinNotificationAction.plain(...)])`를 등록한다. `DarwinNotificationActionOption.foreground`를 넣지 않아 UI를 열지 않는다.
- 단일 대상 알림의 `DarwinNotificationDetails.categoryIdentifier`를 `dailyQuestCategoryId`로 설정한다.
- macOS에는 같은 category를 연결하지 않는다. 현재 요구의 종료 상태 무UI 처리를 보장하지 못하기 때문이다.

## 4. 백그라운드 완료 처리

### 4.1 엔트리포인트

신규 `lib/services/notification_action_handler.dart`에 top-level 함수를 둔다.

- `@pragma('vm:entry-point') Future<void> notificationTapBackground(NotificationResponse response)`
- top-level 또는 static이어야 하며 익명 함수/인스턴스 메서드를 전달하지 않는다.
- `response.actionId == completeQuestActionId`인 경우만 처리한다.
- 예외는 플랫폼 콜백 밖으로 내보내지 않고, 가능한 경우 실패 확인 알림을 남긴다.

`NotificationService.init()`의 `_plugin.initialize()`에 이 함수를 `onDidReceiveBackgroundNotificationResponse`로 전달한다. foreground 콜백도 등록하되 일반 알림 본문 탭은 기존 앱 열기 동작을 유지하고, 완료 액션은 동일 dispatcher를 거치게 해 테스트 가능한 단일 분기점으로 만든다.

### 4.2 저장소 초기화

handler는 다음 순서로 동작한다.

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. payload 구문/액션 ID의 빠른 검증.
3. background용 `StorageService` 생성 및 `await init()`.
4. `installationId`, 현재 퀘스트 존재 여부와 `QuestStatus.active` 검증.
5. 완료 실행.
6. 결과 확인 알림 및 일일 리마인더 재예약.
7. background에서 연 box/리소스를 `finally`에서 닫는다.

`StorageService.init()`은 모든 box와 secure storage까지 여는 무거운 경로다. 첫 구현은 기존 어댑터/box 초기화 순서를 재사용해 정확성을 우선한다. 후속 최적화로 `initForQuestCompletion()`을 만들려면 완료 트랜잭션이 실제 사용하는 `stats`, `quests`, `profile`, `achievements`, `goals`, `settings`를 빠뜨리지 않아야 하며, `transactions` 등 미사용 box 제외는 테스트로 증명한 뒤 별도 커밋으로 한다.

### 4.3 완료 로직 재사용

권장 1차 구현은 `QuestsNotifier.completeQuest()`의 트랜잭션을 복제하지 않고 headless `ProviderContainer`에서 그대로 재사용하는 것이다.

- `storageServiceProvider.overrideWithValue(backgroundStorage)`로 container 생성
- `container.read(questsProvider.notifier).completeQuest(questId)` 호출
- 결과를 복사한 뒤 container dispose

이 방식은 `XpService.effectiveRewards`, `StatsNotifier.applyXp`, `GoalsNotifier.completeGoalLocked`, `AchievementService.checkAndUnlock`, `RollbackScope`의 기존 의미와 테스트를 보존한다. 장기적으로 UI state notifier에서 도메인 트랜잭션을 분리하는 것이 더 깔끔하지만, Phase 4에서 로직을 대규모 재작성하면 보상 무결성 회귀 위험이 커진다.

단, 아래 4.4의 cross-isolate 잠금이 선행되지 않으면 이 호출을 활성화하지 않는다.

### 4.4 isolate 간 무결성

`rewardLockProvider`는 같은 `ProviderContainer`/isolate 내 호출만 직렬화한다. 백그라운드 완료와 foreground 완료가 겹치는 경우를 막기 위해 **프로세스/엔진 간 공유되는 배타 경계**가 필요하다.

구현 단계:

1. 신규 `lib/services/quest_completion_execution_lock.dart`에 파일 기반 exclusive lock 추상화를 둔다. 앱 documents/support 디렉터리 아래 전용 lock 파일 하나를 사용하고 `RandomAccessFile.lock(FileLock.exclusive)`/`unlock()`을 `try/finally`로 감싼다.
2. 잠금 경로는 명시적인 파일 하나로 제한하며 사용자 데이터 파일 자체를 잠그지 않는다.
3. 알림 handler뿐 아니라 UI의 `QuestsNotifier.completeQuest()` 진입도 같은 execution lock을 먼저 획득한 뒤 기존 `rewardLockProvider`를 획득한다. 락 순서는 항상 “execution lock → reward lock”으로 고정한다.
4. 타임아웃을 둔다. 획득 실패/시간 초과 시 완료하지 않고 “처리하지 못했습니다. 앱에서 확인해 주세요.” 알림을 표시한다.
5. 잠금 획득 뒤 퀘스트 상태를 다시 읽는다. 사전 검증 결과를 신뢰하지 않는다.
6. background write 후 foreground가 다시 활성화될 때 Hive 캐시를 디스크 최신 상태로 재동기화하는 API를 마련한다. Hive 2.2.3에서 열린 box의 타 isolate 변경 관찰이 보장되는지 spike 테스트로 확인하고, 보장되지 않으면 `StorageService.reopenForExternalChanges()`로 관련 box를 안전하게 닫고 다시 열어 모든 provider notifier를 `reload()`한다.

Go/No-Go 조건:

- 두 Flutter 엔진이 같은 Hive 파일을 연 상태의 동시 쓰기/캐시 갱신 통합 테스트가 통과하지 않으면, 백그라운드 직접 완료를 출시하지 않는다.
- box reopen 중 UI 접근을 완전히 차단할 수 없다면 `AppBootstrap` 수준의 storage session 교체가 필요하다. 이를 생략하고 “대개 앱은 종료 상태일 것”이라고 가정하지 않는다.

### 4.5 중복·재시도

- `didComplete == false`는 성공으로 가장하지 않는다. 이미 완료/삭제된 경우 “이미 처리되었거나 더 이상 존재하지 않는 퀘스트예요.” 확인 알림을 사용한다.
- `actionToken`별 상태(`processing`, `completed`, `failed`)를 `settingsBox`에 저장한다.
- 같은 token의 `completed` 재수신은 즉시 no-op 한다.
- `processing`이 비정상 종료로 남을 수 있으므로 timestamp와 만료 시간을 둔다. 만료 전 중복은 무시하고, 만료 후에는 퀘스트 현재 상태를 다시 확인한다.
- token 기록만으로 원자성을 보장한다고 가정하지 않는다. 실제 XP 중복 방지는 execution lock과 `QuestStatus.active` 재검증이 담당한다.

## 5. 사용자 피드백

완료 액션은 앱 UI를 열지 않으므로 `QuestCompletionResult`를 다음 확인 알림으로 변환한다.

- 정상 완료, 특별 이벤트 없음: `퀘스트 완료!` / `“{현재 quest.title}”을 완료하고 XP를 받았어요.`
- 레벨업: `퀘스트 완료 · 레벨업!` / 레벨업한 스탯 이름과 새 레벨을 요약하고 “앱을 열어 확인하세요.”
- 새 업적: `퀘스트 완료 · 새 업적!` / 업적 1개 이름 또는 `새 업적 N개`와 “앱을 열어 확인하세요.”
- 연결 목표 자동 완료: 본문에 목표 완료도 포함한다.
- 여러 이벤트 동시 발생: 제목은 `퀘스트 완료!`, 본문은 `레벨업 N개 · 새 업적 N개 · 목표 완료`처럼 길이를 제한한다.
- stale/no-op: `퀘스트 상태를 확인했어요` / `이미 완료되었거나 삭제된 퀘스트예요.`
- 저장소/처리 실패: `완료 처리하지 못했어요` / `데이터는 임의로 변경하지 않았습니다. 앱에서 다시 시도해 주세요.`

후속 알림은 기존 일일 리마인더와 다른 ID/채널을 사용한다. Android 채널 예시는 `quest_action_result`, Darwin에는 일반 category(완료 액션 없음)를 사용해 확인 알림에서 다시 완료 버튼이 생기지 않게 한다. 민감 정보 노출을 줄이기 위해 잠금 화면 제목 표시 정책은 기존 앱 정책을 따르고, 오류 원문/파일 경로/stack trace를 본문에 넣지 않는다.

다이얼로그는 표시하지 않는다. 앱이 다음에 열릴 때 이미 저장된 레벨/업적/목표 상태를 정상 화면에서 보여 주며, Phase 4는 “놓친 축하 다이얼로그 큐”까지 추가하지 않는다.

## 6. 네이티브 및 플랫폼별 실현 가능성

| 플랫폼 | 액션 UI | 앱 종료/수면 상태의 무UI Dart 처리 | Phase 4 판단 |
|---|---|---|---|
| Android | `AndroidNotificationAction` 지원 | 지원. `showsUserInterface: false`, top-level/static `@pragma('vm:entry-point')` callback과 `ActionBroadcastReceiver` 필요. background isolate에는 `Activity` context가 없음 | 구현 |
| iOS | `DarwinNotificationAction`을 category로 등록 | 지원. foreground 옵션 없는 액션, `UNUserNotificationCenterDelegate`, plugin registrant callback 필요 | 구현 |
| macOS | Darwin category/action 지원(10.14+) | 플러그인 문서상 background isolate 미지원, main isolate callback만 사용 | 액션 미노출 |
| Linux | `LinuxNotificationAction` 지원 여부가 notification server capability에 의존 | callback은 main isolate. 앱 종료 후에는 DBus activatable 앱 설정 등이 필요하고 플러그인 초기화 시점 제약이 있음. 현재 플러그인은 scheduled/pending notification도 미지원 | 액션 미노출 |
| Windows | `WindowsAction`/toast 버튼 지원 | 버튼과 launch behavior는 지원하지만 Android/iOS와 같은 종료 상태 background-isolate 완료 경로를 이번 저장소에서 검증하지 못함. 반복 알림도 지원하지 않으며 package identity/MSIX 여부에 따른 제한이 있음 | 액션 미노출 |
| Web | Chrome/Edge는 notification action 지원, Firefox/Safari는 미지원 | 브라우저는 현재 플러그인의 scheduled/repeating notification을 지원하지 않으며 service worker 기반 background Hive 완료 계약도 없음 | 대상 아님 |

Android 변경:

```xml
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
```

이를 `android/app/src/main/AndroidManifest.xml`의 `<application>` 안에 추가한다. 새 runtime permission은 없다. 기존 `RECEIVE_BOOT_COMPLETED`와 `ScheduledNotificationBootReceiver`는 유지한다. 현재 manifest에 `ScheduledNotificationReceiver`가 명시적으로 없는 점은 22.0.1 manifest merge 결과를 `processDebugMainManifest` 산출물에서 함께 확인한다.

iOS 변경:

- `ios/Runner/AppDelegate.swift`에 `import UserNotifications`, `import flutter_local_notifications`.
- `application(_:didFinishLaunchingWithOptions:)`에서 `UNUserNotificationCenter.current().delegate` 설정.
- 이 프로젝트는 `FlutterImplicitEngineDelegate`/`didInitializeImplicitFlutterEngine`을 사용하므로 22.0.1의 UIScene 지침에 맞춰 그 메서드에서 `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback`을 등록한다.
- `GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)` 기존 호출을 유지한다.
- `Info.plist` 추가 키는 없다.

이는 위젯 네이티브 구현이 아니라 플러그인의 필수 연결 설정이다. Kotlin 도메인 코드나 Swift 도메인 코드는 추가하지 않는다.

## 7. 엣지 케이스

| 상황 | 처리 |
|---|---|
| 삭제 후 재설치, 오래된 알림 | OS가 일반적으로 앱 알림을 제거하더라도 이를 보안 경계로 삼지 않는다. 새 `installationId`와 payload가 다르면 no-op. iOS 구버전의 주기 알림 잔존 가능성도 방어한다. |
| Hive box 손상/열기 실패 | `StorageService.init()` 예외를 잡고 데이터 삭제/box 재생성을 하지 않는다. 일반 실패 확인 알림만 시도하고 앱의 기존 `AppBootstrap` 복구 화면으로 넘긴다. |
| 이미 완료된 퀘스트 | `completeQuest()`의 `didComplete: false`; XP/업적 재지급 없음. |
| 삭제된 퀘스트 | 동일하게 no-op. payload 제목만으로 레코드를 재생성하지 않는다. |
| suggested 상태로 바뀐 퀘스트 | active가 아니므로 no-op. |
| 알림 후 퀘스트 제목/보상 수정 | ID로 현재 레코드를 읽고 현재 제목/보상으로 완료한다. 후속 알림도 가능하면 현재 제목 사용. |
| 액션 연속 탭/OS 재전달 | `actionToken` dedupe + execution lock + 잠금 안 상태 재검증. |
| 서로 다른 퀘스트 액션 동시 탭 | 하나의 전역 execution lock으로 직렬화. 각 payload의 현재 상태를 차례로 검증. |
| foreground 완료와 background 액션 경합 | 같은 execution lock을 양쪽 진입점에서 사용. 기존 `rewardLockProvider`만 믿지 않는다. |
| 완료 도중 일부 Hive 쓰기 실패 | 기존 `RollbackScope`가 되돌림. rollback 자체 실패도 성공 알림을 내지 않고 오류로 기록. |
| 후속 알림 표시 실패/권한 철회 | 완료 트랜잭션은 되돌리지 않는다. 피드백 전달 실패와 완료 성공을 분리한다. |
| payload 변조/알 수 없는 schema | no-op; 예외 원문이나 payload 전체를 로그/알림에 노출하지 않는다. |
| 날짜 경계/DST | 완료 시각은 기존 `nowProvider` 경로를 유지. 재예약은 기존 `tz.local`/`NotificationTimezoneException` 정책을 유지. |
| 액션 후 다음 활성 퀘스트가 1개 | 기존 반복 예약을 새 단일 대상 payload로 교체. |
| 액션 후 활성 퀘스트가 여러 개/0개 | 같은 시각의 리마인더를 액션 없는 문구로 교체. |

## 8. 파일 및 함수 단위 작업

### 신규

1. `lib/services/notification_action_handler.dart`
   - `notificationTapBackground(NotificationResponse)`
   - `dispatchNotificationResponse(NotificationResponse, ...)`
   - payload decode/validate
   - storage/container lifecycle
   - 결과 알림 및 재예약 orchestration

2. `lib/services/notification_action_payload.dart`
   - `DailyQuestNotificationPayload`
   - `toJsonString()`, `tryParse()`
   - schema/type/install ID 검증

3. `lib/services/quest_completion_execution_lock.dart`
   - `QuestCompletionExecutionLock`
   - `synchronized<T>()`
   - 파일 lock 획득/타임아웃/해제
   - 테스트용 in-memory fake 주입점

4. `test/notification_action_payload_test.dart`
   - schema 직렬화/역직렬화/오염 입력

5. `test/notification_action_handler_test.dart`
   - dispatcher의 성공/no-op/실패/dedupe/재예약/후속 알림

6. `test/quest_completion_execution_lock_test.dart`
   - 직렬화, 타임아웃, 예외 시 unlock

7. `integration_test/notification_action_storage_isolate_test.dart`
   - 두 isolate/두 storage session의 Hive 경합 및 최신 상태 확인

### 수정

1. `lib/services/notification_service.dart`
   - 알림/action/category/결과 알림 ID 상수 정리
   - `init()`에 Darwin category와 foreground/background response callback 등록
   - `scheduleDailyReminder()`/`scheduleDailyReminderCall()` 인자를 `activeQuestCount` 대신 또는 이에 더해 `Quest? completionTarget`을 받을 수 있는 명시적 snapshot 타입으로 변경
   - 단일 대상에만 title/payload/action/category 적용
   - `showQuestCompletionResult(...)` 추가
   - 재예약 helper 추가
   - 테스트 주입용 `show`/`initialize` 경계 제공

2. `lib/main.dart`
   - `scheduleNotifications()`에서 활성 퀘스트 목록을 한 번 snapshot하고 정확히 1개일 때 target 전달
   - `AppBootstrap`의 정상 startup 흐름과 background 엔트리포인트가 초기화 책임을 중복 실행하지 않도록 주석/경계 명확화
   - `AppLifecycleState.resumed`에서 외부 Hive 변경 재동기화 후 관련 notifier reload

3. `lib/providers/quest_provider.dart`
   - `QuestsNotifier.completeQuest()` 진입에 `QuestCompletionExecutionLock` 적용
   - 기존 `rewardLockProvider` 및 `_completeQuestLocked()`/`RollbackScope` 의미 유지
   - 성공한 퀘스트 mutation 뒤 알림 재예약을 직접 플랫폼 호출로 흩뿌리지 말고 별도 coordinator/provider에 알림

4. `lib/services/storage_service.dart`
   - `installationId` 읽기/최초 생성
   - action token 처리 상태 저장 API
   - 필요 시 `reopenForExternalChanges()` 및 `close()` 추가
   - background 초기화/종료의 idempotency 보강

5. `android/app/src/main/AndroidManifest.xml`
   - `ActionBroadcastReceiver` 등록

6. `ios/Runner/AppDelegate.swift`
   - notification center delegate 및 plugin registrant callback 설정

7. 기존 테스트
   - `test/notification_schedule_mode_test.dart`: action/payload/category와 기존 `androidNotificationScheduleMode` 유지 검증
   - `test/startup_sequence_test.dart`: 0/1/복수 활성 퀘스트 target 전달 검증
   - `test/daily_reminder_toggle_test.dart`: 변경된 scheduling signature 반영
   - `test/completion_reward_integrity_test.dart`: execution lock 도입 뒤 기존 원자성/rollback/동시 완료 계약 유지

`pubspec.yaml`은 22.0.1 기능만 사용하므로 의존성 추가/버전 변경이 필요 없다. 파일 lock 경로를 얻기 위해 새 패키지를 넣기 전에 `Hive`가 사용하는 앱 경로를 안전하게 재사용할 수 있는지 확인하고, 불가능할 때만 `path_provider` 직접 의존을 별도 검토한다(현재 `hive_flutter`의 transitive dependency에 기대어 직접 import하지 않는다).

## 9. 테스트 계획

### 9.1 단위 테스트로 보장

- payload round-trip, 버전/type/action/install ID 거부
- 활성 퀘스트 0/1/N개별 문구, action 개수, Android `showsUserInterface: false`, iOS categoryIdentifier
- action ID가 다르면 저장소를 열지 않는 빠른 no-op
- missing/completed/deleted/suggested quest의 no-op
- 정상 완료 결과에서 XP, 레벨업, 업적, 목표 완료 결과 알림 mapping
- token 중복 처리와 processing 만료
- storage init 실패, completion 실패, rollback 실패, result notification 실패의 분리
- 성공 후 일일 리마인더가 현재 활성 목록으로 재예약됨
- lock 직렬화/타임아웃/예외 시 해제
- 기존 `completion_reward_integrity_test.dart` 전부 유지

플랫폼 채널은 fake/injected call로 인자를 검증한다. OS가 실제로 버튼을 렌더링하거나 종료 앱을 깨우는지는 단위 테스트가 증명할 수 없다.

### 9.2 위젯 테스트로 보장

- background 완료 후 앱 resume 시 dashboard/quest/profile/progression provider가 최신 Hive 상태를 표시
- 완료 다이얼로그를 억지로 띄우지 않고 앱이 정상 화면으로 복귀
- storage resync 중 loading/error UX가 기존 `AppBootstrap` 정책을 깨지 않음

### 9.3 통합/실기기 필수

Android 실기기 또는 에뮬레이터:

1. debug와 release 각각에서 앱 foreground/background/최근 앱에서 제거/강제 종료 상태.
2. 활성 퀘스트 0/1/3개에서 알림 펼침 및 버튼 노출 규칙.
3. 버튼 탭 시 Activity가 열리지 않는지, XP/레벨/업적/목표가 정확히 1회 반영되는지.
4. 빠른 중복 탭, UI 완료와 액션 동시 실행.
5. 재부팅 후 예약 복원과 action receiver 동작.
6. Android 13+ 권한 허용/거부, OEM 배터리 제한은 별도 관찰.
7. merged manifest에 `ActionBroadcastReceiver`, 예약 receiver, boot receiver 존재 확인.

iOS 실기기:

1. Xcode debug와 archive/release에서 foreground/background/사용자 종료 후 알림 액션.
2. 잠금 화면/Notification Center에서 category action 노출.
3. 액션 탭 시 앱 UI가 foreground로 오지 않는지.
4. background engine에서 Hive 및 notification plugin 등록이 실제로 되는지.
5. 중복 탭, 권한 철회, 기기 재부팅.
6. `FlutterImplicitEngineDelegate`/UIScene 경로에서 registrant callback이 실행되는지 Xcode 로그로 확인.

시뮬레이터만으로 종료 상태 delivery/백그라운드 실행 시간을 최종 승인하지 않는다. 특히 iOS는 실기기 검증을 출시 gate로 둔다.

데스크톱/Web:

- 이번 Phase에서는 액션이 생성되지 않는 것만 단위 테스트한다.
- macOS/Linux/Windows의 버튼 데모가 가능하다는 사실을 “종료 상태 무UI 완료 지원”으로 오해하지 않는다.

## 10. 리스크와 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| Hive 2.2.3 다중 isolate box 쓰기/캐시 | 중복 XP, 오래된 UI, 파일 손상 | execution lock, 상태 재검증, resume resync, 두 엔진 통합 테스트를 출시 gate로 지정 |
| iOS background 실행 시간 제한 | 완료 또는 후속 알림이 중간 종료 | 네트워크 작업 금지, storage/transaction만 수행, 초기화 최소화는 측정 후 적용 |
| 반복 알림 payload 노후화 | 이미 완료된 대상 버튼 재등장 | 성공 즉시 취소/재예약, 모든 앱 mutation 후 재예약, callback 현재 상태 검증 |
| OS/OEM이 background 실행 제한 | 버튼을 눌러도 늦거나 실패 | 결과 알림 부재를 성공으로 표시하지 않음, 수동 검증 matrix, 앱에서 상태 확인 유도 |
| AppDelegate/manifest 누락 | callback 미호출 | release merged manifest/Xcode archive 검증 및 체크리스트 |
| handler tree shaking | release에서만 callback 소실 | top-level + `@pragma('vm:entry-point')`, release 실기기 테스트 |
| 알림 권한 철회 | 완료 피드백 불가 | 완료 자체는 유지, 다음 앱 진입에서 저장 상태 표시 |
| 기존 완료 로직 대규모 변경 | 보상/rollback 회귀 | headless container로 기존 `completeQuest()` 재사용, 기존 무결성 테스트 유지 |
| 파일 lock 교착 | UI/액션 멈춤 | 고정 락 순서, timeout, `finally` unlock, lock 내부 네트워크 금지 |

## 11. 롤백

기능 플래그 `notificationQuestCompletionActionEnabled`를 코드 상수 또는 settings 기본값으로 둔다.

1. 긴급 롤백은 action/category/payload 생성을 끄고 기존 개수 기반 리마인더만 예약한다.
2. handler와 manifest/AppDelegate 연결은 남아 있어도 action이 생성되지 않으면 mutation 진입점이 없다.
3. 이미 표시된 알림을 제거하기 위해 업그레이드 후 최초 실행에서 `_dailyReminderId`를 취소하고 액션 없는 버전으로 재예약한다.
4. 저장된 `installationId`/action token ledger는 무해한 내부 데이터이므로 긴급 롤백에서 삭제하지 않는다.
5. 완료 트랜잭션의 execution lock이 문제라면 action 플래그를 먼저 끈 뒤, UI 경로의 lock 제거는 별도 회귀 테스트 후 수행한다.
6. 롤백은 이미 정상 완료된 퀘스트/XP를 되돌리지 않는다.

## 12. 순차 커밋 제안

1. `test: define notification action payload and selection contracts`
   - payload/0·1·N 선택/결과 mapping 실패 테스트부터 추가.

2. `feat: add typed daily quest notification payload`
   - payload 타입, 상수, installation ID 저장 API.

3. `feat: add cross-isolate quest completion execution lock`
   - UI 완료 경로 포함, 기존 reward integrity 테스트 통과.

4. `test: verify Hive completion across isolated storage sessions`
   - 다중 isolate spike와 Go/No-Go 결과. 실패 시 다음 커밋으로 진행하지 않는다.

5. `feat: add headless notification action dispatcher`
   - background storage/container lifecycle, dedupe, 기존 `completeQuest()` 재사용.

6. `feat: add single-quest action to daily reminders`
   - Android action, Darwin category, payload, 0/1/N 문구 및 재예약.

7. `feat(android): register notification action receiver`
   - manifest 최소 변경과 merged manifest 검증.

8. `feat(ios): register notification delegate and background plugins`
   - AppDelegate 최소 변경과 Xcode build 검증.

9. `feat: show completion result notifications and resync on resume`
   - 레벨업/업적/목표 요약, Hive 최신 상태 UI 반영.

10. `test: cover notification action failures and stale deliveries`
    - 손상 payload, 재설치 token, 완료/삭제, lock timeout, notification failure.

11. `docs: record Android and iOS manual verification results`
    - 기기/OS/build mode별 결과와 알려진 OEM 제한.

각 커밋은 `flutter analyze`와 관련 테스트를 통과해야 한다. 6번 이후에는 Android release 실기기, 8번 이후에는 iOS archive 실기기 검증을 각각 merge gate로 둔다.

## 13. 완료 기준

- 단일 활성 퀘스트 알림에만 완료 액션이 보인다.
- Android/iOS에서 앱 UI를 열지 않고 종료/수면 상태 완료가 된다.
- XP, 레벨, 업적, 연결 목표가 `QuestsNotifier.completeQuest()`와 동일하게 정확히 한 번 반영된다.
- 중복/오래된/변조된 액션이 보상을 중복 지급하지 않는다.
- 성공/특별 이벤트/no-op/실패가 후속 알림으로 구분된다.
- background write 후 앱 화면은 재시작 없이 최신 상태를 보인다.
- 기존 일일 리마인더 on/off, 주간 리포트, 예산/백업 알림은 회귀하지 않는다.
- Android release 및 iOS archive 실기기 matrix가 통과한다.
- 홈 화면 위젯 및 네이티브 도메인 구현은 포함되지 않는다.
