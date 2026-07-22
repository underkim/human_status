# Phase 1 관측성 기반(Observability Foundation) 구현 계획

## 0. 목표와 비목표

이 단계의 목표는 Human Status의 기존 local-first 원칙과 `AppBootstrap`의 저장소 복구 흐름을 유지하면서, 사용자가 명시적으로 동의한 경우에만 처리되지 않은 오류를 외부 크래시 리포팅 서비스로 보내는 기반을 만드는 것이다. 기본값은 반드시 꺼짐(`false`)이며, 동의 전에는 SDK 초기화와 네트워크 전송을 모두 하지 않는다.

이 계획은 구현 순서와 검증 기준만 정의한다. 성능 추적, 세션 리플레이, 사용자 행동 분석, 사용자 ID 설정, 앱 데이터(퀘스트·목표·거래·Claude API 키)의 breadcrumb/custom context 첨부는 Phase 1 범위에서 제외한다. 특히 “에러를 잡는다”는 것은 진단 이벤트를 안전하게 기록하고 기존 Flutter 오류 표시/부트스트랩 복구를 보존한다는 뜻이지, 모든 치명적 오류 뒤에도 손상된 실행을 계속한다는 뜻은 아니다.

## 1. SDK 결정: Sentry 권고

### 비교

| 판단 항목 | Sentry (`sentry_flutter`) | Firebase Crashlytics (`firebase_crashlytics`) |
| --- | --- | --- |
| pub.dev 선언 플랫폼 | Android, iOS, Linux, macOS, Web, Windows 6개 모두 | Android, iOS, macOS |
| Windows/Linux | Dart/Flutter 오류 보고 경로를 패키지 수준에서 지원한다. 다만 패키지 설명상 네이티브 크래시 지원은 Android/iOS에 한정되므로 Windows/Linux의 C/C++ runner 네이티브 크래시까지 모바일과 동등하다고 간주하면 안 된다. | 현재 pub.dev 패키지 플랫폼에 Windows/Linux가 없다. Firebase의 Flutter 지원표도 Crashlytics의 Windows 지원을 표시하지 않는다. Linux 역시 공식 대상이 아니다.
| Web | 공식 패키지 대상이다. 브라우저 오류 보고가 가능하나, 비웹의 current-isolate 자동 포착과 차이가 있고 읽을 수 있는 릴리즈 스택에는 source map 업로드가 필요하다. | 현재 `firebase_crashlytics` pub.dev 대상에 Web이 없다.
| 프로젝트 부담 | 한 서비스/한 Flutter 패키지로 6개 빌드 타깃에 동일한 추상화를 적용할 수 있다. DSN 및 심볼 업로드 설정은 필요하다. | Firebase 프로젝트, `firebase_core`, FlutterFire 설정, 플랫폼별 설정 파일 및 Android Gradle 플러그인이 추가된다. 그런데 이 앱의 Windows/Linux/Web 관측 공백은 해결하지 못한다.
| local-first/개인 프로젝트 적합성 | SDK를 동의 후에만 초기화하고 `sendDefaultPii = false`, tracing/profiling/replay 비활성화, `beforeSend` 삭제 정책을 적용할 수 있다. 비교적 작은 도입 범위로 유지 가능하다. | 수집 자체를 opt-in으로 바꿀 수 있지만 기본 자동 수집을 플랫폼 설정에서도 확실히 차단해야 하며, 지원 플랫폼 공백 대비 설정 부담이 크다.

근거: 2026-07-23 확인 기준 [sentry_flutter pub.dev](https://pub.dev/packages/sentry_flutter)는 6개 플랫폼을 모두 표시하고 네이티브 크래시 지원을 Android/iOS로 명시한다. 반면 [firebase_crashlytics pub.dev](https://pub.dev/packages/firebase_crashlytics)는 Android/iOS/macOS만 표시하며, [Firebase Flutter 플러그인 지원표](https://firebase.google.com/docs/flutter/setup#available-plugins)에서도 Crashlytics의 Windows 지원은 제공되지 않는다. Crashlytics의 공식 Flutter 설정은 Firebase 초기화와 Android Gradle 설정도 요구한다([공식 시작 문서](https://firebase.google.com/docs/crashlytics/flutter/get-started)).

### 결론과 보안 기본값

`sentry_flutter`의 구현 시점 안정 버전을 `pubspec.yaml`에 명시적으로 고정해 채택한다. 실제 구현 직전 Dart 3.12.2/Flutter 3.44.6 제약과 changelog를 다시 확인하고 `flutter pub add sentry_flutter`가 제안한 호환 버전을 그대로 검토한다. prerelease는 사용하지 않는다.

초기 옵션은 다음처럼 제한한다.

- DSN은 `--dart-define=SENTRY_DSN=...`로 주입하고 저장소에 운영 DSN을 하드코딩하지 않는다. DSN은 인증 비밀과 같지는 않지만 환경 분리와 오남용 억제를 위해 소스 밖에서 관리한다.
- `sendDefaultPii = false`; 사용자 ID/e-mail/IP를 직접 설정하지 않는다.
- `tracesSampleRate = 0`, profiling과 Session Replay를 끄고 오류 이벤트만 수집한다.
- `attachScreenshot`, view hierarchy, local variables 등 추가 첨부 기능은 끈다.
- `beforeSend`에서 URL query, 로컬 절대 경로, Claude 키 형태(`sk-ant-`), 백업/가져오기 원문 등 잠재적 민감 문자열을 제거한다. 앱의 도메인 객체나 금융 값을 custom context/breadcrumb로 넣지 않는다.
- debug/test 빌드는 기본적으로 외부 전송하지 않는다. 실제 수신 검증만 별도의 opt-in QA 빌드와 테스트 Sentry 프로젝트에서 수행한다.

## 2. 전역 오류 처리와 부트스트랩 통합

### 책임 분리

신규 `lib/services/crash_reporting_service.dart`에 제안 이름 `CrashReportingService`를 만든다. 이는 SDK 호출을 감싸며 `initialize()`, `captureFlutterError(FlutterErrorDetails)`, `captureError(Object, StackTrace)`, `setConsent(bool)`, `close()`를 제공한다. 테스트 대역을 위해 동일 파일에 최소 인터페이스(제안 이름 `CrashReporter`)를 두고, 비동의/초기화 전에는 모든 capture가 즉시 끝나는 no-op 게이트가 되게 한다. 이 이름들은 신규 타입의 제안 이름이며 현재 저장소에 이미 있다고 가정하지 않는다.

`main.dart`의 기존 타입과 흐름은 유지한다.

1. `main()`은 가장 바깥에서 `runZonedGuarded`를 호출한다.
2. zone body 안에서 `WidgetsFlutterBinding.ensureInitialized()`를 호출하고 `FlutterError.onError`를 설치한 뒤 현재와 동일하게 `runApp(const AppBootstrap())`를 즉시 호출한다.
3. `FlutterError.onError`는 원래 핸들러를 보관한다. 오류를 reporter에 넘긴 뒤 `FlutterError.presentError(details)` 또는 보관한 원래 핸들러를 정확히 한 번 호출하여 debug 콘솔/Flutter 동작을 숨기지 않는다. reporter 실패는 별도 `try/catch`로 삼켜 재귀 보고를 막는다.
4. `runZonedGuarded`의 `onError`는 Flutter framework 밖의 처리되지 않은 async 오류를 `captureError`로 넘긴다. 이 콜백 자체는 절대 다시 throw하지 않고 reporter 실패도 삼킨다. 동기적인 framework build/layout 오류는 `FlutterError.onError`, zone 내 future/timer 오류는 zone handler가 담당한다.
5. 같은 오류가 두 경로로 들어오는 SDK 자동 계측 중복을 피하기 위해 Sentry의 자동 Flutter integration과 수동 handler 조합을 구현 시 확인한다. 한 경로만 Sentry에 보내고 기존 `FlutterError` 표시는 유지한다. 이벤트 ID/오류 객체 identity 기반의 임시 중복 제거를 앱에 새로 만들기보다 SDK 권장 통합 방식을 우선한다.

구조 수준의 의사 코드는 다음과 같다.

```dart
Future<void> main() async {
  final reporter = /* 아직 초기화되지 않은 CrashReportingService */;
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      reporter.captureFlutterError(details); // 초기화 전/비동의면 no-op
      (previousFlutterError ?? FlutterError.presentError)(details);
    };
    runApp(AppBootstrap(/* 기존 주입점 + reporter 주입 */));
  }, (error, stack) {
    reporter.captureError(error, stack); // 초기화 전/비동의면 no-op
  });
}
```

실제 Dart 타입상 `runZonedGuarded` 반환값과 sync/async 콜백을 맞추고, capture Future는 `unawaited`하되 내부에서 실패를 모두 처리한다. `PlatformDispatcher.instance.onError`는 `runZonedGuarded`와 중복 포착 가능성이 있으므로 Phase 1에서는 동시에 설치하지 않는다. 웹/플랫폼 검증에서 zone 밖 엔진 오류 공백이 확인될 때만, 단일 전달 경로와 중복 방지 테스트를 추가한 뒤 채택한다.

### `AppBootstrap`과의 접점

`AppBootstrap.createStorage`, `_AppBootstrapState._initialize`, `_BootstrapStatus`, `_BootstrapErrorScreen`, `_retry()`를 그대로 보존한다.

- `_initialize(int generation)`의 `widget.createStorage()` 예외는 지금처럼 catch하여 `_BootstrapStatus.error`로 전환한다. 이 오류를 zone까지 다시 던지지 않으므로 복구 화면이 사라지거나 blank screen이 되지 않는다.
- 저장소가 성공적으로 열린 직후, 신규 설정 값 `storage.crashReportingEnabled`가 `true`일 때만 `CrashReportingService.initialize()`를 호출한다. `false`이면 Sentry 초기화 함수를 호출하지 않는다.
- SDK 초기화 실패는 저장소 초기화 실패로 취급하지 않는다. reporter가 no-op 상태로 되돌아가고 앱은 기존 `ProviderContainer` → `UncontrolledProviderScope` → `HumanStatusApp` 경로로 계속 열린다. 선택 기능의 네트워크/설정 실패 때문에 `_BootstrapErrorScreen`을 보여주지 않는다.
- SDK 초기화가 느려 첫 콘텐츠 표시를 막지 않도록 제한된 시간 안에 best-effort로 수행하거나 ready 전환 뒤 비동기로 수행한다. 단, enabled 상태에서 초기화가 완료되기 전 발생한 오류는 로컬 no-op이라는 명시적 일관성을 지키며 큐에 앱 데이터를 쌓지 않는다.
- storage open 자체의 실패는 동의 값을 안전하게 읽을 수 없으므로 외부 전송하지 않는다. 현재 복구 화면만 보여준다. 이는 “동의 확인 전 전송 금지”가 “앱 시작 직후 오류도 무조건 원격 수집”보다 우선한다는 의도적 제한이다.

`AppBootstrap`에는 테스트용 reporter 주입점만 추가하고 기본값은 production reporter로 둔다. 기존 `StorageInitializer`와 `StartupSequenceRunner`를 바꾸거나 제거하지 않는다.

## 3. opt-in 상태와 설정 UI

### 저장 위치

신규 Hive box `settings`를 `StorageService`가 관리하도록 한다. `StorageService`에 공개 상수 `settingsBoxName = 'settings'`, `late Box<dynamic> settingsBox`, 키 상수(예: 내부 키 `'crashReportingEnabled'`), 동기 getter `bool get crashReportingEnabled => settingsBox.get(key, defaultValue: false) == true`, 비동기 setter `Future<void> setCrashReportingEnabled(bool value)`를 추가한다.

이 선택의 이유는 다음과 같다.

- 동의 여부는 비밀이 아니므로 `flutter_secure_storage`에 둘 이유가 없다. 보안 저장소 장애/키링 요구사항을 새 기능의 부팅 의존성으로 만들지 않는다.
- 이미 앱의 일반 설정과 로컬 데이터는 `StorageService`/Hive가 책임진다. `shared_preferences`라는 세 번째 저장 계층과 의존성을 추가하지 않는다.
- `UserProfile`에 넣지 않아 `UserProfileAdapter`의 필드 수/하위 호환, `_copyProfile()` 누락, 백업에 동의 값이 섞이는 문제를 피한다. 동의는 백업/가져오기 대상이 아니며 새 기기에서 다시 기본값 `false`여야 한다.
- `StorageService.init()`가 다른 box들과 함께 `settings`를 연다. 키가 없거나 타입이 잘못됐거나 읽기 실패 시 false로 fail-closed한다.

신규 `lib/providers/observability_provider.dart`에 제안 이름 `crashReportingConsentProvider`를 `StateNotifierProvider`로 만들고, `storageServiceProvider`와 reporter provider를 주입받는다. notifier의 초기 상태는 `storage.crashReportingEnabled`; `setEnabled(bool)`은 중복 탭을 막고 다음 순서를 지킨다.

- 켜기: 개인정보 안내/명시적 확인 → Hive에 `true` 저장 성공 → SDK 초기화. 저장 실패 시 UI 상태를 false로 유지한다. 초기화 실패 시 동의 값은 유지하되 “현재 세션에서 연결 실패”를 표시하고 다음 시작에 재시도할지, 또는 false로 보상 저장할지를 구현 전 UX 결정으로 고정한다. 권고는 동의와 서비스 가용성을 분리하여 동의 값은 유지하고 재시도하는 방식이다.
- 끄기: 먼저 provider 전송 gate를 false로 바꿔 신규 이벤트를 즉시 차단 → Hive에 false 저장 → `Sentry.close()`/해당 SDK 종료 API로 큐 flush 없이 종료 가능한지 구현 버전 API 확인. 저장 실패 시 gate와 UI를 원래 상태로 복원한다. 이미 프로세스에 로드된 라이브러리를 완전히 unload할 수는 없으므로 “초기화 자체 skip”은 다음 앱 시작부터 완전 보장되고, 현재 세션은 close+gate로 전송을 보장 차단한다.

### `SettingsScreen` 배치와 문구

`SettingsScreen.build()`의 현재 순서에서 `주간 리포트 알림` `SwitchListTile` 다음, `추천 퀘스트 새로고침` `ListTile` 전에 새 `SwitchListTile`을 둔다. 기존 토글 패턴(secondary icon, title, subtitle, value, 진행 중이면 `onChanged: null`)을 그대로 따른다.

- 아이콘: `Icons.bug_report_outlined`
- 제목: `익명 크래시 리포팅`
- 꺼짐 부제: `꺼짐 · 오류 정보가 외부로 전송되지 않아요`
- 켜짐 부제: `켜짐 · 앱 오류와 기기·OS 정보를 Sentry로 보내요`
- 첫 활성화 시 확인 다이얼로그에서 전송 항목, Sentry라는 처리자, 언제든 끌 수 있음, 개인정보처리방침을 먼저 보여주고 명시적으로 `동의하고 켜기`를 눌러야 한다. 단순 switch 탭만으로 바로 초기화하지 않는다.
- 변경 중에는 switch를 비활성화하고 실패 시 `SnackBar`로 알린다. settings 화면이 dispose된 뒤에는 `context.mounted`를 확인하되 notifier/storage 결과는 일관되게 완료한다.
- 기존 `데이터 및 개인정보` 다이얼로그에는 “크래시 리포팅은 기본적으로 꺼져 있고 켠 경우에만 외부 전송” 문구와 `docs/privacy_policy.md`에 대응하는 정책 보기 진입점을 추가한다. 앱에서 Markdown 파일을 직접 번들하지 않는다면 배포 URL을 여는 방식은 별도 릴리즈 설정으로 둔다.

## 4. 개인정보처리방침 초안 구조 (`docs/privacy_policy.md`)

구현 커밋에서 다음 목차와 핵심 문구로 별도 문서를 작성한다.

1. **개요 및 시행일** — 앱 이름, 운영자/문의 채널, 시행일, 정책 변경 고지 방법.
2. **로컬 저장 원칙** — “Human Status의 스텟, 퀘스트, 목표, 거래, 자산, 재무 계획 및 설정은 계정이나 서버 동기화 없이 사용자의 기기에 저장됩니다.” Claude API 키는 지원 플랫폼의 보안 저장소에 저장되고 백업에서 제외된다는 현재 README/설정 문구를 유지한다.
3. **선택적 크래시 리포팅** — “익명 크래시 리포팅의 기본값은 꺼짐입니다. 사용자가 설정에서 명시적으로 켠 경우에만 Sentry SDK를 초기화하고 오류 정보를 Sentry로 전송합니다. 끄면 이후 신규 오류 전송을 중단합니다.”
4. **전송될 수 있는 정보** — 예외 종류와 메시지, Dart/Flutter stack trace(함수·파일명·줄 번호와 경우에 따라 경로), 오류 발생 시각, 앱 이름/버전/build/release/environment, SDK 버전, 플랫폼, 기기 제조사·모델·아키텍처, OS 이름·버전·build, locale/timezone, 메모리·디스크·앱 foreground 같은 런타임/기기 상태, 무작위 event ID. 브라우저에서는 browser 이름/버전, user agent, 현재 page URL/referrer가 SDK/브라우저 integration에 의해 포함될 가능성을 별도 명시하고 `beforeSend`로 query/fragment를 제거한다. 전송 과정에서 서비스가 IP 주소를 처리할 가능성과 Sentry 프로젝트의 IP 저장/삭제 설정도 숨기지 않고 명시한다.
5. **수집하지 않도록 설계한 정보** — 이름/e-mail/계정 ID, 광고 ID, 퀘스트·목표·금융 원문, 백업 파일, Claude API 키, screenshot, session replay, 성능 trace를 의도적으로 첨부하지 않는다. 단, 예외 메시지/stack 경로에 우발적으로 포함될 가능성을 필터링하며 100% 제거를 보장할 수 없다는 한계도 고지한다.
6. **처리 목적과 법적 근거/동의** — 안정성 문제 식별·수정만을 목적으로 하며 사용자의 opt-in 동의를 근거로 처리한다.
7. **외부 처리자와 국외 이전** — Sentry 운영 법인, 실제 선택한 데이터 region, 처리 위치, Sentry 개인정보처리방침 링크를 배포 전에 운영 계정 설정에 맞게 확정한다.
8. **보관 및 삭제** — Sentry 프로젝트의 실제 retention 기간을 확인해 숫자로 명시하고, 기간 경과/프로젝트 삭제 시 처리 및 사용자의 삭제 문의 절차를 적는다. 미정인 기간을 추측해 쓰지 않는다.
9. **동의 철회** — 설정의 `익명 크래시 리포팅`을 끄는 경로, 철회 전 이미 전송된 데이터는 retention에 따라 삭제된다는 설명, 별도 삭제 요청 채널.
10. **오프라인과 재전송** — 네이티브 SDK가 전송 실패 이벤트를 로컬 큐에 보관할 수 있는지와 최대 보관량/기간을 실제 SDK 옵션으로 확인해 명시한다. 동의 철회 시 미전송 큐를 삭제하는 구현을 요구한다.
11. **아동, 변경, 문의** — 대상 사용자 정책과 문의처, 중요한 변경 시 재동의가 필요한 조건.

정책에는 “익명”을 절대적 익명성 의미로 쓰지 않는다. UI 제목을 유지하더라도 본문에서는 기기/네트워크 메타데이터로 재식별 가능성이 완전히 0은 아니라고 설명한다.

## 5. 신규/수정 파일과 함수·위젯 단위 작업

### 신규

- `docs/privacy_policy.md`: 위 4절의 정책을 실제 운영 Sentry region/retention/문의처로 확정하여 작성.
- `lib/services/crash_reporting_service.dart`: `CrashReporter` 추상화, production `CrashReportingService`, no-op/테스트 구현; 동의 gate, Sentry 옵션, `beforeSend` redaction, init/close/capture의 idempotency와 동시 호출 직렬화.
- `lib/providers/observability_provider.dart`: reporter provider와 `crashReportingConsentProvider`; 초기 Hive 값 로드, 저장 우선 순서, UI용 `enabled/isChanging/error` 상태.
- `test/crash_reporting_service_test.dart`: SDK transport를 호출하지 않는 fake를 이용한 gate, redaction, 중복 init/close 테스트.
- `test/observability_provider_test.dart`: in-memory `StorageService`와 fake reporter를 이용한 기본값/저장 실패/초기화 실패/끄기 순서 테스트.
- `test/observability_settings_test.dart`: `SettingsScreen` 토글 위치·문구·확인 다이얼로그·취소·실패·재빌드 테스트.
- `test/global_error_handler_test.dart`: main handler 배선을 직접 테스트할 수 있도록 추출한 설치 함수와 fake reporter로 Flutter/zone 오류 전달을 검증.

### 수정

- `pubspec.yaml`: 호환 확인한 `sentry_flutter` 안정 버전 추가. 개인정보처리방침을 앱 안에서 asset으로 열기로 결정한 경우에만 `docs/privacy_policy.md` asset 등록.
- `pubspec.lock`: dependency resolution 결과 갱신.
- `lib/main.dart`: `main()` 바깥 zone, `FlutterError.onError`, reporter 주입; `AppBootstrap`의 저장소 성공 뒤 동의 기반 init. 기존 `StorageInitializer`, `_defaultCreateStorage`, `StartupSequenceRunner`, `runStartupSequence`, `scheduleNotifications`, `_BootstrapErrorScreen` 동작은 보존.
- `lib/services/storage_service.dart`: `settingsBoxName`, `settingsBox`, `init()`의 box open, fail-closed getter/setter, 종료 시 box 수명주기와 테스트 정리 연결.
- `lib/screens/settings_screen.dart`: `_notificationChangeInProgress`와 별개인 관측성 변경 상태 사용, `build()`에 새 `SwitchListTile`, 활성화 확인 다이얼로그, 실패 SnackBar, `_showDataPrivacyDialog()`의 opt-in 설명/정책 진입점. `_copyProfile()`은 관측성 설정을 profile에 넣지 않으므로 수정하지 않는다.
- `test/app_bootstrap_test.dart`: reporter fake를 주입하여 storage 실패 시 SDK 미초기화, false 시 미초기화, true 시 1회 초기화, SDK init 실패에도 `HomeShell` 도달, retry generation에 중복 init 없음 검증.
- `test/settings_data_privacy_dialog_test.dart`: 기존 네 가지 사실과 비변경 검증을 유지하면서 기본 꺼짐/선택 전송/Sentry 처리자/정책 문구를 추가 검증.
- `test/helpers/test_app.dart`: 필요한 경우 reporter/provider override를 선택 인자로 추가. 기존 호출자는 수정 없이 동작하는 기본 fake/no-op을 제공.
- `README.md`: local-first 설명에 “선택적 크래시 리포팅은 기본 꺼짐”과 정책 링크, DSN 개발 설정과 심볼/source map 업로드 명령을 추가.
- `docs/RELEASE_CHECKLIST.md`: 6개 플랫폼 빌드, opt-out 네트워크 무전송, opt-in 테스트 이벤트, symbol/source map, privacy policy/retention/region, DSN 환경 분리 검증 게이트 추가.
- `.github/workflows/ci.yml` 및 `.github/workflows/release-artifacts.yml`: 릴리즈 symbol/source map 업로드를 도입할 경우에만 Sentry auth token secret을 사용하고 fork PR에서는 업로드하지 않는다. 코드 빌드 성공이 업로드 서비스 장애에 불필요하게 묶이지 않도록 정책을 명시한다.
- 플랫폼 파일(`android/`, `ios/`, `macos/`, `windows/`, `linux/`, `web/`): 선택한 `sentry_flutter` 버전의 공식 설치 절차가 요구하는 최소 변경만 적용한다. 자동 수집을 동의 전에 켜는 manifest/Info.plist 설정은 금지한다. 구체적 변경은 구현 시 생성 diff를 플랫폼별 검토한다.

위 목록 외 파일 변경이 필요해지면 이유와 개인정보 영향부터 계획 문서에 보완한 뒤 구현한다. 특히 `UserProfile`, 백업 스키마, 금융/퀘스트 provider는 변경하지 않는다.

## 6. 테스트 계획과 합격 기준

### 단위 테스트

- `기본 동의 값은 키가 없어도 false다`: 새 in-memory storage에서 getter가 false이고 reporter init/capture 호출이 0회인지 확인.
- `잘못된 설정 값은 fail-closed다`: settings box에 문자열/손상 값을 넣어도 false로 읽는지 확인.
- `비동의 capture는 완전한 no-op이다`: Flutter 오류와 zone 오류를 전달해도 fake transport가 0회인지 확인.
- `동의 후 초기화는 한 번만 실행된다`: 병렬/반복 enable에도 init 1회, capture 1회인지 확인.
- `끄기 시작 즉시 신규 전송이 차단된다`: close가 지연되는 동안 오류를 넣어도 capture되지 않고, 미전송 큐 삭제/close가 호출되는지 확인.
- `저장 실패는 상태를 거짓으로 보이지 않는다`: 켜기 저장 실패 시 init 0회/false 유지, 끄기 저장 실패 시 기존 상태와 gate 복원을 확인.
- `필터가 민감 문자열을 제거한다`: `sk-ant-...`, URL query/fragment, 로컬 사용자 경로를 포함한 synthetic event가 redacted되는지 확인. 원본 앱 객체를 테스트 fixture로 전송하지 않는다.

### 전역 handler 테스트

- `FlutterError.onError가 오류를 reporter와 기존 presentation에 각각 한 번 전달한다`: 의도적으로 `FlutterError.reportError`를 호출하고 fake reporter count 및 기존 handler count를 검증한다.
- `zone의 처리되지 않은 Future 오류가 테스트 프로세스를 종료하지 않고 포착된다`: 별도 `runZonedGuarded` test zone에서 `Future.error`를 발생시키고 fake reporter에 error/stack이 1회 도달하며 테스트가 계속 진행됨을 확인한다.
- `reporter 자체 실패가 재귀 오류를 만들지 않는다`: capture가 throw하는 fake를 써서 `tester.takeException()`/zone 2차 오류가 없고 기존 Flutter presentation은 호출되는지 확인한다.
- 이 테스트는 OS native crash를 “복구”한다는 테스트가 아니다. native fatal/segfault는 플랫폼 integration smoke test에서 보고 여부만 검증한다.

### `AppBootstrap` 위젯 테스트

- 기존 `초기화 실패 시 복구 화면...` 테스트가 그대로 통과하고 reporter init/capture가 0회인지 추가 확인한다.
- storage 동의 false 성공 시 `HomeShell`에 도달하고 reporter init은 0회.
- storage 동의 true 성공 시 reporter init이 정확히 1회이고 기존 `startupSequenceRunner`도 정확히 1회.
- reporter init이 throw/timeout이어도 `_BootstrapErrorScreen`이 아닌 `HomeShell`에 도달.
- 실패 후 `_retry()` 성공, 빠른 retry/stale generation 상황에서 reporter와 startup sequence가 중복 실행되지 않음.

### 설정 위젯 테스트

- `익명 크래시 리포팅`이 `주간 리포트 알림` 뒤, `추천 퀘스트 새로고침` 앞에 렌더링되고 초기 switch가 false.
- switch를 탭해도 확인 다이얼로그에서 취소하면 저장/init이 0회.
- `동의하고 켜기` 후 저장 성공 → init 성공 순서를 fake call log로 검증하고 subtitle이 켜짐으로 갱신.
- 끄기 후 즉시 false, 저장 및 close 호출, 앱 재펌프 뒤에도 false.
- 저장/초기화 실패 시 정확한 SnackBar, 중복 탭 방지, 화면 pop 뒤 setState 예외 없음.
- `데이터 및 개인정보` 다이얼로그를 열고 닫아도 Claude 키와 Quest뿐 아니라 동의 값도 바뀌지 않음.

### 수동/통합 검증

각 6개 플랫폼에서 (1) 새 설치/기존 업데이트 후 기본 off, (2) 프록시 또는 Sentry 프로젝트로 off 상태 네트워크 요청 0건, (3) opt-in 후 synthetic Dart 오류 1건, (4) opt-out 뒤 신규 이벤트와 보류 큐 전송 0건, (5) release stack symbolication을 확인한다. 실제 사용자 데이터가 있는 기기 대신 비식별 QA fixture만 사용한다.

## 7. 엣지 케이스

- **오프라인 전송 실패:** 앱 기능과 UI에는 영향을 주지 않고 SDK의 제한된 disk envelope queue를 사용한다. 큐 크기/보관 기간을 명시적으로 제한하고, 재연결 시 동의가 여전히 true일 때만 재전송한다. 사용자가 끄면 pending envelope를 삭제한다. 웹은 브라우저 SDK/저장소 제약상 네이티브와 같은 영속 offline queue를 보장하지 않으므로 이벤트 유실을 정상으로 취급하며 자체 무한 재시도 큐를 만들지 않는다.
- **storage 초기화 전 오류:** 전역 handler는 이미 설치되어 오류를 콘솔/기존 Flutter 경로로 넘기지만 reporter는 no-op이다. 동의를 읽기 전에는 이전 실행에서 동의했을 것이라고 추정해 SDK를 초기화하지 않는다. storage open 실패는 현재 `_BootstrapErrorScreen`에서만 복구한다.
- **storage 성공과 reporter init 경쟁:** generation을 확인하여 dispose/stale retry의 완료가 새 `_container` 상태나 reporter를 덮어쓰지 않게 한다. init은 idempotent하게 만든다.
- **웹:** `runZonedGuarded`가 포착하지 못하는 브라우저/worker 오류 범위를 문서화한다. source map을 릴리즈마다 업로드하되 공개 web artifact에 Sentry auth token을 포함하지 않는다. page URL은 path만 필요할 때도 query/fragment를 제거한다. 브라우저 추적 방지/CSP/ad blocker로 전송이 실패해도 앱은 정상 동작한다.
- **동의 철회 직전 이벤트:** gate를 먼저 닫고 큐 삭제/SDK close를 수행한다. 이미 서버가 수신한 이벤트는 로컬 토글로 즉시 삭제할 수 없으므로 정책의 retention/삭제 요청 절차를 적용한다.
- **DSN 누락/오류:** 동의가 true여도 reporter는 disabled 상태로 남고 앱은 정상 시작한다. 설정 화면에는 동의 상태와 “현재 연결되지 않음”을 혼동하지 않도록 구분한다. DSN 값을 오류 메시지에 노출하지 않는다.
- **여러 isolate:** Phase 1은 main/UI isolate와 Flutter framework 오류를 우선한다. 앱이 새 isolate를 도입/사용하는 지점을 별도 조사하고 필요하면 Sentry error listener를 명시적으로 연결한다. 웹 worker는 별도 초기화 없이는 같은 보장을 하지 않는다.

## 8. 리스크와 롤백

| 리스크 | 완화 | 롤백 기준/방법 |
| --- | --- | --- |
| 바이너리 크기·시작 시간 증가 | 도입 전후 6개 release artifact 크기와 cold start를 동일 조건 측정; off에서 SDK init 0회 확인 | 허용 기준(권고: artifact 증가율과 p95 cold-start 회귀를 릴리즈 전에 팀이 수치 확정) 초과 시 dependency와 플랫폼 설정을 제거하고 no-op reporter/토글을 숨긴다. Hive 키는 무해하게 남기거나 마이그레이션에서 제거한다. |
| Windows/Linux 네이티브 크래시 공백 | Dart/Flutter 오류 지원과 native crash 지원을 구분해 릴리즈 노트에 명시; 플랫폼별 synthetic test | 빌드/런타임 불안정 시 해당 플랫폼만 compile-time adapter/no-op으로 전환하되 기본 off를 유지한다. 장기적으로 플랫폼 전용 native reporter를 별도 phase에서 평가한다. |
| 웹 source map 또는 개인정보 노출 | auth token은 CI secret에만 두고 `beforeSend` URL 정리; 업로드 artifact 검사 | source map 공개/잘못된 release 매핑 시 업로드를 끄고 웹 reporter를 no-op으로 배포한 뒤 노출 token 폐기. |
| SDK 자동 계측이 동의 전에 실행 | off 네트워크 테스트, 플랫폼 manifest/Info.plist 검토, init 호출 count 테스트 | 위반 발견 즉시 기능 플래그/DSN 제거 릴리즈. SDK 제거 전까지 모든 플랫폼에서 전송 endpoint 차단. |
| offline queue가 철회 후 전송 | gate-first, close 및 cache 삭제 테스트 | 큐 삭제를 보장할 수 없는 버전이면 offline caching을 비활성화하거나 기능 출시를 보류. |
| 오류 메시지에 금융/키 정보 포함 | no custom context, redaction, 테스트 corpus | 실제 민감정보 유입 시 프로젝트 ingestion 중단, 해당 이벤트 삭제, token/키 대응, 필터 수정 후 재출시. |
| SDK init 장애가 부트스트랩을 막음 | `_BootstrapStatus.error`와 분리하고 fail-open-to-app/no-op-to-reporting | `CrashReportingService`를 no-op 구현으로 교체하는 작은 revert 배포. `AppBootstrap` storage 복구 코드는 되돌리지 않는다. |

롤백은 관측성 커밋을 순차적으로 revert할 수 있게 구성한다. 데이터 모델/백업 포맷을 건드리지 않으므로 SDK와 UI를 제거해도 사용자 핵심 데이터 마이그레이션은 필요 없다. 개인정보 사고 가능성이 있으면 기능 유지보다 DSN 제거와 수집 중단을 우선한다.

## 9. 순차 커밋 제안

총 6개 커밋으로 나눈다.

1. `docs: add crash reporting privacy policy and release gates` — `docs/privacy_policy.md`, README, `docs/RELEASE_CHECKLIST.md`; 실제 region/retention/문의처 확정. 코드보다 먼저 사용자 약속과 승인 기준을 고정한다.
2. `feat(storage): persist crash reporting consent as opt-in` — `StorageService` 전용 settings box, provider, 단위 테스트. 기본 false와 백업 제외를 먼저 보장한다.
3. `feat(observability): add gated Sentry reporter` — 의존성, service abstraction, 보안 옵션/redaction, service/provider 테스트. 아직 UI/부트스트랩 자동 init은 연결하지 않는다.
4. `feat(bootstrap): capture global errors without changing recovery flow` — `runZonedGuarded`, `FlutterError.onError`, `AppBootstrap` 동의 기반 init, 기존/신규 부트스트랩 테스트.
5. `feat(settings): add explicit crash reporting consent UI` — 기존 `SwitchListTile` 패턴의 토글, 확인 다이얼로그, privacy UI 갱신, widget 테스트.
6. `ci: verify Sentry symbols and six-platform release behavior` — 플랫폼 설정, symbol/source map 업로드, off 무전송 및 opt-in QA 체크. 각 플랫폼 release build가 확인된 뒤 기능 출시.

각 커밋은 `flutter analyze`와 관련 테스트를 통과해야 하며, 4~5번 이후에는 전체 `flutter test`, 마지막에는 가능한 6개 플랫폼 release build와 수동 privacy gate를 통과해야 한다. 커밋 사이 어느 시점에서든 기본 off/no-op 상태로 안전하게 멈출 수 있어야 한다.

## 10. 완료 조건

- 새 설치, 기존 사용자, 백업 가져오기 후 모두 동의 기본값이 false다.
- off 상태에서 Sentry SDK init과 외부 요청이 0건이다.
- 기존 `AppBootstrap` loading/error/retry/ready와 `runStartupSequence` 1회 보장이 회귀하지 않는다.
- opt-in 뒤 Flutter framework 오류와 zone async 오류가 각각 한 번 보고되고 앱의 기존 오류 표시가 유지된다.
- opt-out 즉시 신규 전송이 차단되고 미전송 큐 처리 방침이 테스트·정책과 일치한다.
- 6개 플랫폼의 실제 지원 범위와 차이가 정책/릴리즈 문서에 사실대로 적혀 있다.
- 개인정보처리방침의 처리자, region, retention, 문의처가 placeholder 없이 확정되어 있다.
- Claude API 키, 금융/퀘스트 데이터, backup 원문, screenshot/replay/performance trace가 이벤트에 포함되지 않음을 synthetic 검증한다.
