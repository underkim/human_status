# Phase 2 자동 백업 구현 계획

## 0. 결론과 설계 원칙

Phase 2의 자동 백업은 앱이 직접 Google Drive API나 iCloud API에 접속하는 기능이
아니다. 사용자가 OS 폴더 선택기로 지정한 폴더에 Human Status JSON 백업을
주기적으로 저장하고, Google Drive for desktop·OneDrive·iCloud Drive 같은 OS
동기화 클라이언트가 그 폴더를 동기화하도록 맡긴다. 따라서 계정·OAuth·클라이언트
시크릿·Human Status 서버가 필요 없고, README의 “로컬 데이터는 Hive에 저장되며
서버가 없다”는 로컬 우선 원칙도 유지한다.

현재 의존성인 `file_selector: ^1.1.0`은 폴더 선택 API
`getDirectoryPath()`를 제공하지만 모든 플랫폼에서 같은 수준으로 동작하지 않는다.
공식 지원표와 실제 잠금 버전의 플랫폼 구현을 기준으로 Phase 2의 제품 지원 범위를
다음처럼 정한다.

- **1차 완전 지원:** Windows, Linux
- **선행 작업을 마친 뒤 지원:** macOS
- **자동 백업 미지원, 기존 수동 내보내기/가져오기 유지:** Android, iOS, Web

“앱이 종료된 상태에서 정해진 시각마다 실행되는 백그라운드 작업”은 이번 Phase의
범위가 아니다. 자동 백업은 앱 시작 및 포그라운드 복귀 시 만료 여부를 검사하는
**기회 기반 주기 실행**이다. 이 제약은 UI 설명에도 명시한다.

## 1. 범위

### 1.1 만드는 것

- 지원 플랫폼에서 OS 폴더 선택기로 백업 대상 폴더 지정
- 자동 백업 켜기/끄기
- 백업 주기 선택: `매일`, `매주`(기본값 `매일`)
- 앱 시작 및 `AppLifecycleState.resumed`에서 기한이 지난 백업 실행
- `BackupService.encode()`로 생성한 기존 스키마의 JSON을 선택 폴더에 안전하게 저장
- 마지막 성공 시각, 최근 실패 상태와 실패 시각 표시
- 실패를 설정 화면의 지속 상태와 인앱 `SnackBar`로 알리고, 가능한 플랫폼에서는
  기존 로컬 알림 기반의 보조 알림 제공
- 폴더 재선택 및 “지금 백업” 동작
- 자동 생성 파일의 제한된 보관 정책(기본 최근 7개)과 임시 파일 정리
- 관련 단위·위젯·플랫폼 통합 테스트

### 1.2 만들지 않는 것

- Google Drive API, iCloud API, OneDrive API 등 OAuth 기반 직접 연동
- 개발자 콘솔 프로젝트, OAuth 동의 화면, 클라이언트 ID/시크릿 관리
- 양방향 동기화, 충돌 병합, 다른 기기 변경의 자동 가져오기
- 앱 서버 업로드, 계정 생성, 원격 백업 목록
- 앱이 종료된 상태에서 OS 백그라운드 작업으로 정확한 시각에 실행하는 백업
- 자동 복원 또는 자동 백업 파일의 무인 가져오기
- Android/iOS/Web에서 별도 파일 플러그인이나 대규모 네이티브 계층을 도입해
  기능 격차를 억지로 메우는 작업

직접 클라우드 API 연동은 실제 배포에 개발자 콘솔 등록, 플랫폼별 OAuth 설정,
리디렉션 URI, 키/시크릿의 안전한 운영과 제공자 심사가 필요해 이 세션과 로컬 우선
제품 범위에서 완결할 수 없다. 반면 OS 동기화 폴더 방식은 자격 증명을 앱이 취급하지
않고도 실제 배포할 수 있다.

## 2. 사전 조사와 플랫폼별 실현 가능성

### 2.1 `file_selector` 확인 결과

`pubspec.yaml`은 `file_selector: ^1.1.0`을 선언하고, `pubspec.lock`은
`file_selector 1.1.0` 및 Android `0.5.2+8`, iOS `0.5.3+5`, Linux `0.9.4`,
macOS `0.9.5`, Web `0.9.5`, Windows `0.9.3+5`를 잠근다.

공식 [`file_selector 1.1.0` 지원표](https://pub.dev/packages/file_selector)는
“Choose a directory”를 Android/Linux/macOS/Windows에서 지원하고 iOS/Web에서는
지원하지 않는다고 명시한다. [`getDirectoryPath()` API 문서](https://pub.dev/documentation/file_selector/latest/file_selector/getDirectoryPath.html)는
Web에서 항상 `null`을 반환한다고 명시한다.

저장소에 설치된 `file_selector_android-0.5.2+8` 구현도 함께 확인했다.
`FileSelectorApiImpl.getDirectoryPath()`는 `ACTION_OPEN_DOCUMENT_TREE` 결과 URI를
`FileUtils.getPathFromUri()`로 일반 경로로 변환하지만, 해당 유틸리티는 기본
`primary` 저장소만 처리하고 외장 볼륨 및 다른 authority를
`UnsupportedOperationException`으로 거절한다. 또한
`takePersistableUriPermission()`을 호출하지 않는다. 즉 Android에서 선택 UI가
뜬다는 사실과 “Google Drive 등 문서 제공자 폴더에 다음 실행에서도 자동 쓰기
가능”은 전혀 같은 보장이 아니다.

### 2.2 플랫폼 결정표

| 플랫폼 | 폴더 선택 | 재실행 후 자동 쓰기 | Phase 2 결정 | 대체 UX |
|---|---|---|---|---|
| Windows | `getDirectoryPath()` 지원, 일반 절대 경로 반환 | 일반 파일 권한 범위에서 가능 | **지원** | 폴더가 사라지거나 권한이 바뀌면 실패 표시 후 재선택 |
| Linux | `getDirectoryPath()` 지원, 일반 경로 반환 | 일반 파일 권한 범위에서 가능. Flatpak/Snap 포털 패키징은 별도 실기기 검증 필요 | **지원** | 포털/샌드박스 패키지에서 영속 접근 실패 시 재선택 안내 |
| macOS | 지원 | App Sandbox에서는 선택 당시 접근만으로 재실행 후 접근이 보장되지 않음 | **조건부 지원**: 보안 범위 북마크 구현·검증 완료 후 노출 | 선행 작업 미완료 빌드에서는 기존 수동 백업만 표시 |
| Android | 선택 UI는 지원하나 잠금 버전은 기본 내부 공유 저장소 경로만 변환하고 클라우드 provider/외장 볼륨/영속 URI 권한 미지원 | 목표 폴더에 대해 신뢰할 수 없음 | **미지원** | 기존 `_exportBackup()`/`_importBackup()` 유지, 자동 백업 섹션에 “이 플랫폼에서는 지원되지 않아요” |
| iOS | `file_selector` 폴더 선택 미지원 | 네이티브 `UIDocumentPickerViewController`와 security-scoped bookmark가 별도로 필요 | **미지원** | 기존 수동 백업 유지 |
| Web | `getDirectoryPath()`가 항상 `null` | 브라우저 샌드박스 및 사용자 활성화 제약으로 무인 임의 폴더 쓰기 불가 | **미지원** | 기존 JSON 표시·클립보드 복사 수동 내보내기 유지 |

Android의 SAF 자체는 `ACTION_OPEN_DOCUMENT_TREE`와 영속 URI 권한을 제공하지만,
현재 플러그인이 그 권한과 URI 기반 파일 생성을 노출하지 않는다. Android 공식
[공유 저장소 문서](https://developer.android.com/training/data-storage/shared/documents-files)는
이동·삭제된 문서는 영속 권한을 얻었더라도 접근이 유지되지 않는다고도 경고한다.
따라서 이번 Phase에서 단순 경로 저장만으로 Android 지원을 선언하지 않는다.

iOS 13 이상은 네이티브 API 자체로 폴더 선택과 북마크가 가능하지만, Apple의
[디렉터리 접근 문서](https://developer.apple.com/documentation/uikit/providing-access-to-directories)에
따르면 security-scoped URL의 시작/종료, file coordination, 북마크 저장·복원이
필요하다. `file_selector 1.1.0`이 폴더 선택을 지원하지 않으므로 Phase 2 범위
밖이다.

macOS는 `macos/Runner/Release.entitlements`에 이미
`com.apple.security.files.user-selected.read-write`가 있지만, 재실행 후 접근에는
Apple의 [security-scoped bookmark 절차](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)가
필요하다. 경로 문자열만 Hive에 저장하는 구현은 출시하지 않는다.

## 3. UI/UX 설계

`SettingsScreen.build()`의 기존 알림 및 `SwitchListTile` 흐름 안에서, 수동
`백업 내보내기`/`백업 가져오기` 바로 위에 `자동 백업` 섹션을 둔다. 별도 화면으로
숨기지 않고 현재 백업 기능과 한곳에서 이해할 수 있게 한다.

### 3.1 지원 플랫폼

다음 위젯을 한 묶음으로 표시한다.

1. `SwitchListTile`
   - 아이콘: `Icons.backup_outlined`
   - 제목: `자동 백업`
   - 꺼짐 부제: `꺼짐 · 폴더를 선택하면 앱을 열 때 주기적으로 백업해요`
   - 켜짐/정상 부제: `켜짐 · 매일` 또는 `켜짐 · 매주`
   - 켜짐/실패 부제: `백업 실패 · 폴더 접근을 확인해주세요`
   - Phase 1의 `익명 크래시 리포팅`과 같이 저장/처리 중에는
     `onChanged: null`로 중복 조작을 막고, 저장 실패 시 기존 문구
     `설정을 저장하지 못했어요. 잠시 후 다시 시도해주세요.`를 사용한다.
2. `ListTile` `백업 폴더`
   - 미지정: `선택되지 않음`
   - 지정: 전체 절대 경로 대신 마지막 1~2개 경로 구성요소만 화면에 표시한다.
     전체 경로는 탭 후 상세 대화상자에서 확인해 작은 화면과 개인정보 노출을 줄인다.
   - 탭하면 `getDirectoryPath(initialDirectory: 현재 경로)` 호출.
   - 선택 취소(`null`)는 기존 설정을 바꾸지 않는다.
   - 선택 직후 쓰기 가능성 검사를 하고, 성공한 경우에만 설정을 저장한다.
3. `ListTile` `백업 주기`
   - 탭하면 `매일`/`매주` 단일 선택 대화상자 또는 `RadioListTile` 표시.
   - `자동 백업`이 꺼져 있어도 미리 선택할 수 있고 기본은 `매일`.
4. `ListTile` `마지막 백업`
   - 성공 이력 없음: `아직 자동 백업하지 않았어요`
   - 성공: 로컬 시간으로 `2026. 7. 23. 오후 3:20`처럼 `intl`을 이용해 표시.
   - 최근 시도 실패 시 마지막 성공은 보존하고 `마지막 성공 … · 최근 시도 실패`로
     함께 표시한다.
   - trailing action `지금 백업`을 제공하며 실행 중에는 비활성화하고
     `백업하는 중...`을 표시한다.

토글을 켤 때 폴더가 없으면 즉시 폴더 선택기를 연다. 취소하면 토글은 꺼진 채로
유지한다. 선택 후 첫 쓰기 검증에 성공해야 켜며, 이때 설명 대화상자에 다음을
명시한다.

> 앱을 시작하거나 다시 열었을 때 선택한 주기가 지났으면 백업해요. 앱이 완전히
> 종료된 동안에는 실행되지 않아요. 동기화 폴더를 선택하면 해당 서비스의 정책에
> 따라 백업 파일이 외부로 전송될 수 있어요.

토글을 끄면 이후 실행만 중단한다. 기존 백업 파일은 사용자가 선택한 폴더에
남아 있으므로 자동 삭제하지 않는다.

### 3.2 미지원 플랫폼

`SwitchListTile`은 값을 `false`, `onChanged: null`로 표시하고 부제를
`이 플랫폼에서는 폴더 자동 백업을 지원하지 않아요. 아래 수동 백업을 사용해주세요.`
로 둔다. 폴더/주기/마지막 백업 하위 타일은 숨겨 화면을 복잡하게 만들지 않는다.
기존 수동 `백업 내보내기`와 `백업 가져오기`는 그대로 유지한다.

### 3.3 실패 알림

실패는 한 가지 채널에만 의존하지 않는다.

- 설정 화면: 최근 실패 상태를 성공할 때까지 지속 표시하고 경고 색상을 사용한다.
- 앱이 열린 상태: 한 번만 `SnackBar`로
  `자동 백업에 실패했어요. 설정에서 백업 폴더를 확인해주세요.` 표시.
- 로컬 알림: `NotificationService.showAutoBackupFailed()`를 추가하되 알림 권한이
  없거나 Web/미지원 플랫폼이면 조용히 생략한다. 이는 실패를 감지한 시점의 즉시
  알림일 뿐, `zonedSchedule()`로 백업 작업 자체를 실행하는 장치가 아니다.
- 같은 실패가 매 resume마다 알림 폭탄이 되지 않도록
  `lastFailureNotifiedAt` 또는 실패 fingerprint를 저장하고, 같은 실패는 24시간에
  한 번 이하로 알린다.

## 4. 상태 관리와 저장 설계

### 4.1 Hive 저장 위치

Phase 1에서 추가한 `StorageService.settingsBox`(`Box<dynamic>`, 이름
`StorageService.settingsBoxName == 'settings'`)를 재사용한다. 자동 백업은
기기·OS별 폴더 권한에 묶인 설정이므로 `UserProfile` 및
`BackupService.encode()`의 `preferences`에 넣지 않는다. 즉 백업/복원으로 다른
기기에 복제되지 않는다. 이 결정은 기존 `_crashReportingEnabledKey`가 백업에서
제외되는 패턴과 일치한다.

`StorageService`에 다음 private key와 타입 안전 getter/setter를 추가할 계획이다.

- `_autoBackupEnabledKey` → `bool`, 기본 `false`, 손상/타입 불일치 시 fail-closed
- `_autoBackupDirectoryPathKey` → `String?`
- `_autoBackupFrequencyKey` → enum 이름 문자열 `daily|weekly`, 잘못된 값은 `daily`
- `_autoBackupLastSuccessAtKey` → ISO-8601 UTC 문자열 또는 Hive `DateTime`
- `_autoBackupLastAttemptAtKey` → ISO-8601 UTC 문자열 또는 Hive `DateTime`
- `_autoBackupLastFailureCodeKey` → 개인정보 없는 enum 이름 문자열
- `_autoBackupLastFailureAtKey` → `DateTime?`
- `_autoBackupLastFailureNotifiedAtKey` → `DateTime?`
- macOS 조건부 지원용 `_autoBackupDirectoryBookmarkKey` → bookmark bytes

관련 값은 개별 `put()` 중 일부만 성공하는 상태를 피하도록
`settingsBox.putAll()`로 함께 갱신한다. 읽기 오류나 잘못된 타입은 앱 시작 실패로
확대하지 않고 자동 백업을 비활성화하되, 설정 화면에서 재설정을 유도한다.

### 4.2 Riverpod 모델

신규 `lib/providers/auto_backup_provider.dart`에 다음을 둔다.

- `enum AutoBackupFrequency { daily, weekly }`
- `enum AutoBackupFailureCode { directoryMissing, permissionDenied, noSpace, writeFailed, invalidConfiguration, unsupportedPlatform }`
- immutable `AutoBackupState`
  - `enabled`, `directoryDisplayPath`, `frequency`
  - `lastSuccessAt`, `lastAttemptAt`, `lastFailureCode`, `lastFailureAt`
  - `isChangingSettings`, `isBackingUp`, `isSupported`
- `AutoBackupNotifier extends StateNotifier<AutoBackupState>`
  - `selectDirectory()`
  - `setEnabled(bool)`
  - `setFrequency(AutoBackupFrequency)`
  - `backupNow()`
  - `reload()`
- `autoBackupProvider`

파일 선택 UI 호출은 테스트 가능하도록 `DirectoryPicker` typedef
(`Future<String?> Function({String? initialDirectory})`)를 주입한다.
실제 파일 쓰기와 시각도 각각 서비스 및 `Clock` 성격의 콜백으로 주입해 위젯
테스트가 플랫폼 채널과 실제 시간에 의존하지 않게 한다.

`SettingsScreen`은 `ref.watch(autoBackupProvider)`로 상태를 렌더링한다.
Phase 1의 `crashReportingConsentProvider`처럼 저장/실행 로직을 화면의 여러
`setState` 필드에 분산시키지 않는다. 기존 `_exportInProgress`,
`_importInProgress`는 수동 백업 전용으로 그대로 둔다.

## 5. 스케줄링 설계

### 5.1 실행 시점

신규 `AutoBackupController`가 다음 두 시점에서 `backupIfDue()`를 호출한다.

1. `runStartupSequence()`에서 `refreshController.refreshIfDue()` 이후
2. `_HumanStatusAppState.didChangeAppLifecycleState()`의
   `AppLifecycleState.resumed`

`runStartupSequence()`에 `AutoBackupController` 또는 테스트용 콜백을 주입하고,
`AppBootstrap._initialize()`에서 이미 만든 `StorageService`와
`ProviderContainer`를 이용해 한 인스턴스만 구성한다. `HumanStatusApp`에는 기존
`refreshController`와 함께 `autoBackupController`를 전달한다.

첫 프레임을 막지 않도록 현재 startup 후처리와 마찬가지로 UI 마운트 후 실행한다.
resume에서도 `unawaited()`로 호출하되 컨트롤러 내부의 in-flight guard로 중복
실행을 막는다. 앱 시작이 백업 실패 때문에 실패해서는 안 된다.

### 5.2 만료 계산

- 비활성, 미지원 플랫폼, 폴더 미지정이면 실행하지 않는다.
- 성공 이력이 없으면 설정 완료 직후의 쓰기 검증/첫 백업을 성공 이력으로 삼는다.
- `daily`: 마지막 성공 후 24시간 이상
- `weekly`: 마지막 성공 후 7일 이상
- 시계가 뒤로 이동한 경우 음수 duration을 “기한 전”으로 취급하되, 24시간 이상
  미래인 비정상 timestamp는 구성 오류로 정규화해 다음 시작에 한 번 실행한다.
- 실패 후에는 매 resume마다 재시도하지 않고 마지막 시도로부터 최소 1시간의
  backoff를 둔다. 사용자의 `지금 백업`은 backoff를 무시한다.

정확한 벽시계 시각보다 “마지막 성공 이후 경과 시간”을 사용해 DST와 시간대 변경의
중복/누락을 줄인다. 표시만 현지 시간으로 변환한다.

### 5.3 `NotificationService` 재사용 여부

`NotificationService.scheduleDailyReminder()`와
`scheduleWeeklyReportReminder()`는 `flutter_local_notifications`로 OS 알림을
등록할 뿐 앱의 Dart 파일 쓰기 코드를 실행하지 않는다. 따라서 이 스케줄링을 자동
백업 트리거로 재사용하지 않는다.

재사용할 부분은 플랫폼 초기화와 즉시 알림 패턴이다.
`showBudgetExceeded()`와 유사한 `showAutoBackupFailed()` 및 별도 notification
ID/channel을 추가한다. Android의 `androidNotificationScheduleMode`나
`zonedSchedule()`은 자동 백업 실행에는 사용하지 않는다.

## 6. 파일 쓰기와 실패 처리

### 6.1 안전한 저장 순서

신규 `AutoBackupService`의 한 번 실행은 다음 순서다.

1. 설정 snapshot과 실행 시각을 캡처하고 in-flight guard 획득
2. 폴더 존재 및 쓰기 가능성 확인
3. `BackupService.encode()` 호출
4. 파일명 생성:
   `human_status_auto_backup_YYYYMMDD_HHmmss_SSS.json`
5. 같은 폴더의 고유 임시 파일
   `.human_status_auto_backup_<uuid>.tmp`에 UTF-8 bytes 쓰기
6. flush 후 최종 파일명으로 rename
7. 최종 파일을 다시 읽거나 크기/JSON `BackupService.inspect()` 검증
8. 마지막 성공/시도/실패 초기화 상태를 `settingsBox.putAll()`로 기록
9. 성공 이후에만 오래된 **자동 백업 파일 패턴**을 최근 7개까지 정리

기존 사용자 파일이나 수동 백업 파일은 삭제하지 않는다. rename이 원자적이지 않은
파일 시스템/동기화 provider도 있으므로 임시 확장자는 `.json`이 아니게 하고,
최종 검증 실패 시 성공 시각을 갱신하지 않는다.

### 6.2 실패 분류와 조치

| 상황 | 기록/동작 | 사용자 안내 |
|---|---|---|
| 폴더 삭제·이동 | `directoryMissing`, 자동 백업 설정은 보존 | 폴더 재선택 버튼 강조 |
| 권한 회수·샌드박스 bookmark stale | `permissionDenied`; macOS stale bookmark는 한 번 갱신 시도 | 폴더를 다시 선택하도록 안내 |
| 읽기 전용 폴더 | 설정 시 probe 실패 또는 실행 시 `permissionDenied` | 쓰기 가능한 폴더 선택 안내 |
| 디스크 공간 부족 | 가능한 OS 오류를 `noSpace`, 그 외 `writeFailed` | 공간 확보 후 `지금 백업` 안내 |
| 폴더 선택 취소 | 상태 변경 없음, 오류 표시 없음 | 없음 |
| `BackupService.encode()` 실패 | `writeFailed`; 파일 생성 전 종료 | 기존 데이터는 건드리지 않고 재시도 안내 |
| 임시 쓰기/flush/rename 실패 | 성공 시각 미갱신, 임시 파일 best-effort 삭제 | 일반 실패 + 폴더 확인 |
| 앱 강제 종료 중 쓰기 | 다음 실행에서 오래된 `.tmp` 정리 | 최종 `.json`만 정상 백업으로 취급 |
| 같은 초 동시 실행 | mutex/in-flight guard와 millisecond/UUID로 충돌 방지 | 중복 요청은 기존 Future 공유 또는 무시 |
| 동기화 클라이언트가 파일 잠금 | `writeFailed`, backoff 후 재시도 | 잠시 후 다시 시도 안내 |
| 설정 Hive 기록 실패 | 백업 파일이 생성됐더라도 상태 저장 실패로 취급하고 사용자에게 알림 | 설정 저장 실패 문구 |

오류 원문, 절대 경로, 백업 JSON을 Sentry breadcrumb/exception message에 넣지 않는다.
필요하면 정규화한 `AutoBackupFailureCode`와 플랫폼명만 기록한다.

## 7. 기존 `BackupService` 통합

기존 `BackupService`의 책임은 JSON 직렬화/검증/복원이고 파일 시스템은
`SettingsScreen._exportBackup()`가 직접 다룬다. 이 경계를 유지한다.

### 그대로 재사용

- `BackupService.encode()` — 자동 백업 JSON 생성
- `BackupService.inspect(String jsonStr)` — 저장 후 검증에 재사용 가능
- `BackupService.currentSchemaVersion` — 파일 내용 호환성
- `BackupService.restore(String jsonStr)` — 기존 수동 가져오기만 사용
- `backupServiceProvider` — `AutoBackupService` 구성 시 동일 인스턴스 주입

### 추가하지 않을 것

- `restore()`의 자동 호출
- 자동 백업 설정을 `encode()`의 `preferences`에 포함
- 폴더 선택이나 OS 권한 코드를 `BackupService`에 혼합

### 신규 서비스 API 초안

`lib/services/auto_backup_service.dart`:

- `Future<AutoBackupResult> backupToDirectory(AutoBackupTarget target)`
- `Future<DirectoryProbeResult> probeDirectory(AutoBackupTarget target)`
- `Future<void> pruneOldBackups(AutoBackupTarget target, {int keep = 7})`
- `bool isDue({required DateTime now, required DateTime? lastSuccessAt, required AutoBackupFrequency frequency})`

`AutoBackupResult`는 성공 경로를 UI에 노출하기보다 `completedAt`,
`failureCode` 같은 최소 상태만 반환한다.

macOS 지원 시 `lib/services/auto_backup_target_access.dart`의 추상화 아래에서
보안 범위 bookmark resolve/start/stop을 처리한다. Windows/Linux 구현은 저장된
경로를 사용한다. 플랫폼별 접근 토큰의 생명주기를 파일 쓰기 `try/finally`와
묶는다.

## 8. 신규/수정 파일과 함수·위젯 단위 작업

실제 구현 단계에서 예상되는 변경이다. 이번 계획 작성 작업에서는 아래 파일을
수정하지 않는다.

### 신규

- `lib/services/auto_backup_service.dart`
  - `AutoBackupFrequency`, `AutoBackupFailureCode`, `AutoBackupResult`
  - `AutoBackupService.backupToDirectory()`, `probeDirectory()`,
    `pruneOldBackups()`, `isDue()`
- `lib/services/auto_backup_controller.dart`
  - `backupIfDue()`, `backupNow()`, in-flight guard, retry backoff
- `lib/services/auto_backup_target_access.dart`
  - 지원 플랫폼 판정 및 경로/권한 접근 추상화
- `lib/providers/auto_backup_provider.dart`
  - `AutoBackupState`, `AutoBackupNotifier`, `autoBackupProvider`
- `test/auto_backup_service_test.dart`
- `test/auto_backup_controller_test.dart`
- `test/auto_backup_provider_test.dart`
- `test/auto_backup_settings_test.dart`
- macOS 조건부 지원 시 Runner 네이티브 bridge 및 해당 통합 테스트 파일

### 수정

- `lib/services/storage_service.dart`
  - 위 자동 백업 settings key, fail-closed getter, `putAll()` 기반 저장 메서드
- `lib/services/backup_service.dart`
  - 원칙적으로 수정 없음. 저장 후 `inspect()`가 충분한지 테스트로 확인
- `lib/providers/backup_provider.dart`
  - `AutoBackupService`/controller 조립에 필요한 Provider 추가 또는 신규 provider
    파일로 위임
- `lib/screens/settings_screen.dart`
  - `_AutoBackupSection` 추출 또는 동등한 private 위젯
  - 토글, 폴더 선택, 주기 선택, 마지막 상태, 지금 백업
  - 기존 `_exportBackup()`/`_importBackup()` 동작은 유지
- `lib/main.dart`
  - `AppBootstrap._initialize()`에서 controller 구성
  - `runStartupSequence()` 및 `HumanStatusApp`에 controller 주입
  - resume 시 `backupIfDue()` 호출
- `lib/services/notification_service.dart`
  - `_autoBackupFailureId`, `showAutoBackupFailed()`
- `macos/Runner/DebugProfile.entitlements`
  - 현재 `user-selected.read-only`를 자동 백업 검증 빌드에서는
    `user-selected.read-write`로 맞춤
- `macos/Runner/Release.entitlements`
  - 기존 `user-selected.read-write` 유지
  - security-scoped bookmark용 app-scope entitlement 필요 여부를 서명/샌드박스
    실기기에서 검증 후 최소 권한만 추가
- `docs/privacy_policy.md`
  - 아래 11절의 문구 추가
- `README.md`
  - 플랫폼별 지원표와 “앱 시작/resume 기반” 제약 추가

`pubspec.yaml`의 `file_selector`는 이미 필요한 버전이므로 변경하지 않는다.
새 dependency는 Windows/Linux 구현에 필요하지 않다. macOS bookmark를 소규모
MethodChannel로 구현할지 검증된 전용 패키지를 쓸지는 별도 기술 spike 후 결정하며,
검증 없이 의존성을 추가하지 않는다.

## 9. 테스트 계획

### 9.1 단위 테스트

`AutoBackupService`:

- `BackupService.encode()` 결과가 지정 폴더에 UTF-8 JSON으로 저장된다.
- 파일명이 millisecond까지 고유하고 자동 백업 패턴을 따른다.
- 임시 파일을 쓴 뒤 최종 파일로 rename하며 성공 후 `.tmp`가 남지 않는다.
- encode, write, flush, rename, inspect 각 단계 실패 시 마지막 성공 시각을
  갱신하지 않는다.
- 디렉터리 없음/읽기 전용/공간 부족 mock 오류가 올바른
  `AutoBackupFailureCode`로 정규화된다.
- 보관 정리는 최근 7개 자동 백업만 남기고 수동 백업 및 다른 JSON은 건드리지 않는다.
- 정리 실패는 이미 완료된 새 백업 성공을 실패로 뒤집지 않고 별도 비치명 경고로
  처리한다.

`AutoBackupController`:

- disabled/unsupported/폴더 미지정이면 실행하지 않는다.
- 마지막 성공이 24시간/7일 미만이면 실행하지 않고 경계를 넘으면 한 번 실행한다.
- 성공 이력 없음, 시간대 변경, DST, 시계 역행을 정의한 정책대로 처리한다.
- 동시 startup/resume 호출에도 한 번만 쓴다.
- 실패 1시간 내 자동 재시도는 막고 `backupNow()`는 허용한다.
- 성공 시 실패 상태를 지우고, 실패 시 기존 마지막 성공은 보존한다.
- 실패 알림 throttle이 동일 실패를 24시간에 한 번 이하로 제한한다.

`StorageService`:

- fresh `settingsBox` 기본값은 비활성/매일/이력 없음이다.
- 값 round-trip 및 `putAll()` 저장이 된다.
- 잘못된 타입/enum 문자열/읽기 예외에서 자동 백업을 fail-closed한다.
- 자동 백업 설정이 `BackupService.encode()` 결과에 포함되지 않고
  `restore()`에도 변경되지 않는다.

### 9.2 위젯 테스트

- Windows/Linux 지원 상태에서 자동 백업 섹션의 토글·폴더·주기·마지막 백업·
  지금 백업 문구가 표시된다.
- 폴더 없이 토글을 켜면 picker를 호출하고 취소 시 꺼짐을 유지한다.
- probe 성공 후에만 토글이 켜지고 저장 실패 시 원래 상태로 되돌아간다.
- `isChangingSettings`/`isBackingUp` 중 중복 탭이 차단된다.
- 폴더 경로는 기본 화면에서 축약되고 상세 대화상자에서만 전체 표시된다.
- 마지막 성공과 최근 실패가 동시에 올바르게 표시된다.
- 성공/실패 `SnackBar` 문구가 정확하다.
- Android/iOS/Web에서는 토글이 비활성화되고 수동 내보내기/가져오기는 계속
  사용 가능하다.
- 기존 `settings_screen_test.dart`, `weekly_report_toggle_test.dart`,
  `settings_data_privacy_dialog_test.dart`가 회귀 없이 통과한다.

### 9.3 플랫폼 통합·수동 검증

- Windows: 로컬 폴더, OneDrive 폴더, 재실행, 폴더 이동/삭제, 파일 잠금
- Linux: 일반 배포와 가능한 경우 Flatpak/Snap, Google Drive 마운트/동기화 폴더,
  권한 변경
- macOS: Debug/Release 서명 빌드에서 iCloud Drive 폴더 선택, 앱 완전 종료 후
  bookmark 복원, 권한 회수, stale bookmark, read/write entitlement
- Android/iOS/Web: 자동 백업 UI가 미지원으로 정확히 노출되고 기존 수동 백업이
  깨지지 않는지 확인
- 각 지원 플랫폼에서 앱을 닫아 둔 동안에는 실행되지 않고 다음 시작/resume 때
  한 번 실행되는지 확인

macOS는 위 재실행 테스트가 통과하기 전까지 제품 feature flag를 켜지 않는다.

## 10. 개인정보처리방침 판단

`docs/privacy_policy.md`에는 자동 백업 관련 조항을 **추가해야 한다**. 앱 운영자가
백업을 수집하는 것은 아니지만, 사용자가 동기화 폴더를 선택하면 백업 JSON에 담긴
퀘스트·목표·거래 등 원문 데이터가 Google/Microsoft/Apple 또는 사용자가 고른
동기화 제공자에게 전송될 수 있기 때문이다.

추가 문구에는 다음을 포함한다.

- 자동 백업은 기본 꺼짐이며 사용자가 폴더와 주기를 직접 선택한다.
- 앱은 선택한 폴더에 JSON 파일을 쓰며 Human Status 서버로 보내지 않는다.
- 폴더가 제3자 동기화 서비스에 연결됐는지 앱은 알 수 없고, 실제 외부 전송·보관·
  삭제는 해당 OS/서비스 정책과 사용자 설정을 따른다.
- 백업에는 `BackupService.encode()`가 담는 퀘스트·목표·거래·자산 스냅샷·재무
  계획·업적·일부 제품 선호가 포함된다.
- Claude API 키, 알림 설정, 크래시 리포팅 동의, 자동 백업 폴더/설정은 백업에서
  제외된다.
- 자동 백업을 끄거나 앱을 삭제해도 이미 생성된 파일과 클라우드 사본은 자동
  삭제되지 않으며 사용자가 해당 폴더/서비스에서 삭제해야 한다.

## 11. 엣지 케이스와 리스크

- **“자동” 기대 차이:** 종료 중 정확한 주기 실행이 아니다. 설정 설명과 README에
  앱 시작/resume 기반임을 반복 명시한다.
- **클라우드 동기화 완료 오인:** 파일 쓰기 성공은 Google Drive/OneDrive/iCloud의
  업로드 성공을 뜻하지 않는다. UI는 `백업 파일 저장됨`이라고 표현하고
  `클라우드 동기화 완료`라고 표현하지 않는다.
- **macOS 권한 영속성:** path만 저장하면 재실행 후 실패할 수 있다. bookmark
  구현 전 기능 노출 금지.
- **Android의 거짓 지원:** picker가 뜨더라도 클라우드 provider 경로 변환과 영속
  접근이 안 된다. 현 잠금 버전에서 지원으로 표시하지 않는다.
- **Linux 패키징 차이:** 네이티브 개발 실행과 포털 기반 sandbox 패키지의 권한
  생명주기가 다를 수 있어 배포 형식별 검증이 필요하다.
- **Web File System Access API:** 일부 브라우저의 비표준 API가 있더라도 현재
  `file_selector`가 폴더 handle을 제공하지 않고 무인 쓰기 보장도 없어 범위에
  포함하지 않는다.
- **민감 데이터 평문:** JSON 백업은 암호화되지 않는다. 선택 전 설명 및
  개인정보처리방침에서 이를 알리고 공용 폴더 선택을 경고한다.
- **동기화 중 부분 파일:** 임시 확장자 + rename + 최종 검증으로 줄인다.
- **보관 정리와 원격 삭제 전파:** 오래된 파일 삭제가 클라우드에도 전파될 수 있다.
  자동 생성 패턴만 대상으로 하고 기본 7개 정책을 UI/문서에 명시한다.
- **절대 경로 유출:** UI, 로그, Sentry에 전체 경로를 기본 노출하지 않는다.
- **Hive 설정 손상:** fail-closed하고 도메인 데이터 및 앱 부팅에 영향을 주지 않는다.
- **복원과 동시 실행:** 수동 `_importBackup()`/데이터 초기화 중 자동 백업을
  실행하지 않도록 앱 범위 mutex를 공유한다. 가져오기 직전/중간 상태가 자동
  백업되지 않게 하고 성공 후 다음 정상 트리거를 기다린다.
- **큰 데이터/메모리:** 현재 `BackupService.encode()`는 전체 JSON 문자열을
  메모리에 만든다. 기존 수동 백업과 동일한 한계이며 Phase 2에서는 재사용하되,
  성능 테스트에서 UI jank가 확인되면 별도 streaming 백업 Phase로 분리한다.

## 12. 구현 순서와 순차 커밋 제안

1. **`feat(storage): add device-local auto backup settings`**
   - `StorageService.settingsBox` key/getter/setter, enum, fail-closed 테스트
2. **`feat(backup): add atomic automatic backup writer`**
   - `AutoBackupService`, 임시 쓰기/rename/검증/보관 정리와 단위 테스트
3. **`feat(backup): schedule due backups on startup and resume`**
   - `AutoBackupController`, `main.dart` 주입, due/backoff/concurrency 테스트
4. **`feat(settings): add automatic backup controls`**
   - Provider/state, 폴더 선택, 토글/주기/상태/지금 백업, 미지원 플랫폼 UX,
     위젯 테스트
5. **`feat(notifications): surface automatic backup failures`**
   - `NotificationService.showAutoBackupFailed()`, throttle, 설정 경고 UI 테스트
6. **`feat(macos): persist selected backup folder access`**
   - security-scoped bookmark bridge, entitlements 정합화, 서명 빌드 실기기 검증
   - 이 커밋의 검증이 끝나기 전 macOS 지원 flag는 꺼진 상태 유지
7. **`docs: document automatic backup privacy and platform limits`**
   - `README.md`, `docs/privacy_policy.md`, 지원표와 종료 중 미실행 제약
8. **`test(backup): add six-platform regression matrix`**
   - 기존 수동 백업 회귀, 지원/미지원 분기, Windows/Linux/macOS 수동 체크리스트

각 커밋은 `flutter analyze`와 관련 테스트를 통과한 뒤 다음 단계로 진행한다.
Windows/Linux 지원을 먼저 출시할 수 있도록 macOS bookmark 작업을 독립 커밋과
feature gate로 분리한다.

## 13. 완료 기준

- Windows/Linux에서 사용자가 선택한 로컬 또는 OS 동기화 폴더에 앱 시작/resume
  기준으로 만료된 JSON 백업이 안전하게 생성된다.
- macOS는 security-scoped bookmark 재실행 검증을 통과한 빌드에서만 지원된다.
- Android/iOS/Web은 지원된다고 오인시키지 않으며 기존 수동 백업이 유지된다.
- 자동 백업 설정은 device-local `settingsBox`에만 저장되고 백업 JSON으로
  이동하지 않는다.
- 실패가 앱 부팅이나 사용자 데이터에 영향을 주지 않고, 설정 화면에서 지속적으로
  발견 가능하며 중복 알림이 제한된다.
- 자동 백업 성공을 클라우드 업로드 성공으로 표현하지 않는다.
- 개인정보처리방침과 README가 실제 데이터 흐름 및 플랫폼 제약을 정확히 설명한다.
