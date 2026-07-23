# Phase 3 — 프로덕션 배포 블로커 해소 구현·실행 계획

## 0. 결론 요약

Phase 3의 목표는 “모든 플랫폼이 이미 출시되었다”는 선언이 아니라, 저장소에서
해결할 수 있는 릴리즈 블로커를 닫고 외부 자격 증명·실기기·스토어 심사에 남는
게이트를 재현 가능한 증적으로 분리하는 것이다.

### 0.1 이 저장소 작업으로 끝낼 수 있는 것

- `tool/check_release_readiness.dart`가 검사하는 영구 ID·버전·Android 서명 배관을
  계속 fail-closed로 유지하고, 실제 자격 증명이 주입된 릴리즈 환경에서 검사를
  통과시킨다.
- Android용 서명 AAB 생성 경로와 시크릿 주입 경로를 만들고, 시크릿 값이나
  keystore를 저장소에 남기지 않는다.
- Sentry DSN을 현재 코드의 계약대로
  `--dart-define=SENTRY_DSN=...`로만 주입하고, DSN 없는 일반 CI에서는 SDK가
  초기화되지 않는 상태를 유지한다.
- 운영자가 제공한 실제 값으로 `docs/privacy_policy.md`의 모든 `[TODO: ...]`를
  제거하고, 같은 문서를 공개 HTTPS URL로 게시할 준비를 끝낸다.
- Windows/Web 릴리즈 빌드와 스모크 테스트를 현재 Windows 환경 또는 GitHub
  Actions에서 수행한다.
- Linux 빌드, Android AAB, iOS/macOS 빌드·archive를 각각 해당 OS runner에서
  검증하도록 CI/릴리즈 절차를 보강한다.
- Play Console/App Store Connect에 올릴 설명, 스크린샷, 아이콘, 개인정보 URL,
  심사 메모의 소스 패키지를 준비한다.
- `kQuestCompletionNotificationActionEnabled`를 실기기 검증 전에는 계속
  `false`로 두고, 검증 결과에 따라 별도 단일 커밋으로 활성화하거나 출시 범위에서
  명시적으로 제외한다.

### 0.2 이 Windows·무실기기 세션에서 완결할 수 없는 것

- 실제 Android upload keystore의 발급·복구·안전한 백업, 비밀번호 관리자 보관,
  Play App Signing 등록은 keystore 소유자와 Play Console 계정이 필요하다.
- iOS 배포 인증서, App ID, provisioning profile, App Store Connect 앱 레코드,
  TestFlight 업로드와 실제 iPhone 검증은 Apple Developer 계정, macOS/Xcode,
  실제 기기가 필요하다.
- `docs/privacy_policy.md`의 운영 법인, 문의처, 시행일, Sentry region·retention
  같은 값은 운영 주체와 실제 Sentry 계정 설정 없이는 확정할 수 없다.
- 실제 Sentry 프로젝트에서 opt-in 이벤트 수신, opt-out 뒤 무전송,
  symbol/source map 매핑을 확인하려면 테스트/운영 Sentry 프로젝트와 자격
  증명이 필요하다.
- Android/iOS에서 두 Flutter 엔진/isolate가 같은 Hive 파일을 다루는 Phase 4
  통합 검증은 실제 플랫폼 런타임에서 해야 한다. 이 검증 전에는 알림 완료 액션을
  출시하면 안 된다.
- Play Console/App Store Connect의 정책 설문, 콘텐츠 등급, Data safety/App
  Privacy 선언, 가격·국가·계약·세금 설정, 심사 제출은 계정 소유자가 완료해야
  한다.

따라서 이 세션에서 현실적으로 만들 수 있는 최종 상태는 **“저장소와 자동 빌드
경로는 준비되었고, 외부 소유자가 수행할 서명·계정·실기기·스토어 게이트가
증적과 함께 명확히 남은 상태”**다. 외부 게이트까지 통과하기 전에는 모바일
스토어 출시 완료 또는 6개 플랫폼 전체 출시 준비 완료라고 선언하지 않는다.

---

## 1. 현재 저장소 조사 결과

조사 기준일은 2026-07-23이며, 로컬 환경은 Windows 11, Flutter `3.44.6`,
Dart `3.12.2`다. `flutter doctor -v`는 Android SDK 36, Chrome, Visual Studio
2022를 포함해 문제 없음으로 끝났고 연결 대상은 Windows/Chrome/Edge뿐이다.
Android/iOS 실기기는 없다.

### 1.1 릴리즈 준비 검사 실측

실행 명령:

```powershell
dart run tool/check_release_readiness.dart
dart run tool/check_release_readiness.dart --json
```

두 명령 모두 종료 코드 `1`이었고 JSON은 `"ready": false`와 단 하나의 issue를
반환했다.

| 실제 issue | 범주 | 현재 원인 | 해제 조건 |
| --- | --- | --- | --- |
| `android_release_signing_credentials_missing` | `android` | `android/key.properties` 또는 환경 변수에 `storeFile`, `storePassword`, `keyAlias`, `keyPassword`가 없음 | 네 값과 실제 존재하는 keystore를 저장소 밖에서 주입 |

검사 진입점 `tool/check_release_readiness.dart`는 기본 루트를 현재 디렉터리로
정하고 `--json`만 허용한다. `tool/release_readiness/checker.dart`의
`checkReleaseReadiness()`는 다음을 모두 검사한다.

| 검사 영역 | 실패 ID/조건 |
| --- | --- |
| Android 프로젝트 | `android_build_gradle_missing` |
| Android namespace | 누락 `android_namespace_missing`, `com.example...`이면 `android_namespace_placeholder` |
| Android application ID | 누락 `android_application_id_missing`, placeholder면 `android_application_id_placeholder` |
| Android Kotlin package | namespace 경로에 `MainActivity.kt`가 없으면 `android_package_path_mismatch`, `package` 선언 불일치면 `android_package_declaration_mismatch` |
| Android release 서명 배관 | debug 서명이면 `android_release_signing_debug`, `signingConfigs.release` 미연결이면 `android_release_signing_not_wired`, `System.getenv(...)`/네 환경 변수 리터럴이 실제 코드에 없으면 `android_release_signing_env_not_wired` |
| Android 서명 자격 증명 | 네 필드가 비면 `android_release_signing_credentials_missing`, `storeFile` 대상이 없으면 `android_release_signing_keystore_missing` |
| iOS ID | 프로젝트 누락/Runner bundle ID 누락/placeholder |
| macOS ID | AppInfo 누락/bundle ID 누락/placeholder |
| Linux ID | CMakeLists 누락/application ID 누락/placeholder |
| 버전 | `pubspec.yaml`/`version` 누락, `+N` 누락, 형식 오류, 빌드 번호 0 이하 |

검사기의 경계도 중요하다. 이는 실제 서명 유효성, AAB 설치, iOS 서명/archive,
실기기 동작, Sentry, 개인정보처리방침, 스토어 자산을 검사하지 않는다. 따라서
`ready: true`는 필요조건이지 출시 충분조건이 아니다.

### 1.2 영구 ID와 버전

현재 값은 placeholder가 아니며 플랫폼 사이에서 일치한다.

| 플랫폼 | 파일·심볼 | 실제 값 | 상태 |
| --- | --- | --- | --- |
| Android | `android/app/build.gradle.kts`의 `namespace` | `io.github.underkim.humanstatus` | 검사 통과 |
| Android | 같은 파일의 `applicationId` | `io.github.underkim.humanstatus` | 검사 통과 |
| Android Kotlin | `android/app/src/main/kotlin/io/github/underkim/humanstatus/MainActivity.kt`의 `package` | `io.github.underkim.humanstatus` | namespace와 일치 |
| iOS | `ios/Runner.xcodeproj/project.pbxproj` Runner의 `PRODUCT_BUNDLE_IDENTIFIER` | `io.github.underkim.humanstatus` | 검사 통과 |
| macOS | `macos/Runner/Configs/AppInfo.xcconfig`의 `PRODUCT_BUNDLE_IDENTIFIER` | `io.github.underkim.humanstatus` | 검사 통과 |
| Linux | `linux/CMakeLists.txt`의 `APPLICATION_ID` | `io.github.underkim.humanstatus` | 검사 통과 |
| 전체 | `pubspec.yaml`의 `version` | `1.0.0+1` | 유효한 첫 릴리즈 형식 |

이 값들은 스토어 앱 레코드 생성 전에 계정 소유자가 최종 승인해야 한다. 한 번
등록한 Android `applicationId`와 Apple Bundle ID는 기존 앱의 정체성이 되므로,
스토어 등록 후 임의 변경하지 않는다. 재업로드 때는 `pubspec.yaml`의 `+1`을
반드시 증가시킨다.

### 1.3 Android 서명 배관

`android/app/build.gradle.kts`에는 이미 다음 안전장치가 있다.

- `android/key.properties`를 `java.util.Properties`로 읽는다.
- `ANDROID_KEYSTORE_PATH`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD` 중 비어 있지 않은 환경 변수 값이 로컬 파일보다
  우선한다.
- 이름에 `release`가 포함된 요청/실제 task만
  `failIfReleaseSigningIncomplete()`로 fail-fast한다.
- `signingConfigs.create("release")`를 만들고
  `buildTypes.release.signingConfig =
  signingConfigs.getByName("release")`로 연결한다.
- debug 서명 fallback이나 조용한 unsigned release 경로가 없다.

`.gitignore`와 `android/.gitignore`는 `android/key.properties`, `*.jks`,
`*.keystore`를 제외하며 `android/key.properties.example`에는 placeholder만
있다.

그러나 실제 작업 트리에는 `android/key.properties`와
`android/app/human-status-upload.jks`가 없다. 이는
`docs/RELEASE_CHECKLIST.md` 5.1절의 “현재 이 작업 환경에는 … 생성·연결되어
있습니다”라는 문장과 모순된다. 해당 문장은 과거 로컬 상태를 저장소 사실처럼
기록한 문서 드리프트다. Phase 3 구현 때에는 “파일이 있을 수도 있다”가 아니라
readiness 결과와 파일 존재 검사를 source of truth로 삼고 체크리스트 문구도
환경 비의존적으로 고친다.

### 1.4 CI 워크플로가 실제로 하는 일

`.github/workflows/`에는 두 파일만 있다.

| 워크플로/잡 | 트리거 | 실제 수행 | 하지 않는 일 |
| --- | --- | --- | --- |
| `.github/workflows/ci.yml` `quality` | PR, `master` push, 수동 | Ubuntu, Flutter `3.44.6`, Java 17, `pub get`, `analyze`, 전체 test, Web release, Android debug APK | readiness, Android release/AAB, Linux release, 서명, Sentry 업로드 |
| 같은 파일 `windows-smoke` | 동일 | Windows에서 `pub get`, Windows release build | 실행 스모크, 압축/체크섬, 서명 |
| `.github/workflows/release-artifacts.yml` `windows-release` | 수동 또는 `v*` tag | Windows release 폴더 전체를 zip, SHA-256 생성, 14일 artifact 업로드 | GitHub Release 생성, 배포, 설치 프로그램, 스토어 제출 |
| 같은 파일 `web-release` | 동일 | Web release를 zip, SHA-256 생성, 14일 artifact 업로드 | 실제 웹 호스팅/deploy |

두 워크플로 모두 `permissions: contents: read`이며 저장소 시크릿을 전혀 참조하지
않는다. iOS/macOS/Linux job, Android signed AAB job, Sentry symbol/source map
업로드 job은 없다.

### 1.5 현재 로컬 품질·빌드 실측

| 명령 | 결과 | 해석 |
| --- | --- | --- |
| `flutter test --no-pub` | 985 tests passed | 현재 작업 트리의 Dart/Flutter 테스트 통과 |
| `flutter analyze --no-pub` | 종료 `255` | 진단 문제가 아니라 analysis server가 한글 경로가 깨진 LSP JSON을 읽다 `FormatException`으로 종료 |
| `flutter build web --release --no-pub` | 성공, `build/web` 생성 | 이 환경에서 Web 컴파일 가능 |
| `flutter build windows --release --no-pub` | 실패 | `소스코드`가 깨진 경로로 전달되어 `app.dill`을 읽지 못함 |
| `flutter build appbundle --release --no-pub` | 실패 | Android Gradle plugin이 프로젝트 경로의 non-ASCII 문자를 먼저 거부; 아직 서명 누락 게이트까지 도달하지 못함 |

따라서 한글 경로의 현재 checkout은 Web/test 확인에는 쓸 수 있지만 Windows
release/Android release/analyze의 최종 증적 환경으로 쓰면 안 된다. 코드에
`android.overridePathCheck=true`를 넣어 증상을 숨기지 말고, 예를 들어
`C:\src\human_status` 같은 ASCII-only 경로의 깨끗한 clone 또는 GitHub-hosted
runner에서 같은 commit SHA를 검증한다. CI의 `windows-latest`/`ubuntu-latest`
경로는 이 로컬 경로 문제를 피한다.

### 1.6 Sentry와 개인정보처리방침 현황

`pubspec.yaml`은 `sentry_flutter: 8.14.2`를 정확히 고정한다.
`lib/services/crash_reporting_service.dart`의 `CrashReportingService`는:

- `const String.fromEnvironment('SENTRY_DSN')`만 사용하고 DSN을 하드코딩하지
  않는다.
- DSN이 비면 동의 값과 무관하게 SDK를 호출하지 않는다.
- `sendDefaultPii = false`, trace/profile/replay sample rate `0`,
  screenshot/view hierarchy off, `beforeSend = redactSentryEvent`를 설정한다.
- consent를 끌 때 `_gateOpen`을 await 전에 닫고 `Sentry.close()`를 수행한다.

`docs/privacy_policy.md`는 앱 asset으로 포함되고
`lib/screens/settings_screen.dart`의 “데이터 및 개인정보” →
“개인정보처리방침 전체 보기”에서 그대로 표시되지만 제목이 아직 “(초안)”이고
다음 실제 값이 비어 있다.

1. 운영자/문의 채널
2. 시행일
3. 정책 변경 고지 방법
4. 실제 운영 법인
5. Sentry data region
6. Sentry 개인정보처리방침 URL
7. 이벤트 retention
8. 프로젝트 삭제/이전 처리 방침
9. 특정 이벤트 조기 삭제 요청 절차
10. 대상 연령/이용 약관 일치 여부
11. 재동의를 요청할 변경 조건

### 1.7 Phase 4 알림 액션 게이트

`lib/services/notification_service.dart`의
`kQuestCompletionNotificationActionEnabled`는 현재 `false`다. 이 값이
`false`이면:

- `buildDailyReminderCompletionTarget()`이 항상 `null`을 반환한다.
- 알림에 완료 action/category/payload가 붙지 않는다.
- `lib/services/notification_action_handler.dart`의 dispatcher도 storage를
  건드리지 않고 no-op한다.

주석과 `docs/plans/phase4_notification_action_plan.md` 4.4절은 Android/iOS에서
두 Flutter 엔진/isolate가 동일 Hive 데이터를 쓰는 실기기 검증 전에는 true로
바꾸지 말라고 명시한다. `test/notification_schedule_mode_test.dart`와
`test/notification_action_handler_test.dart`는 플래그 양쪽 로직을 자동
검증하지만 cross-isolate 실기기 검증을 대체하지 않는다.

### 1.8 `RELEASE_CHECKLIST.md` 미완료 `[ ]` 전수

현재 미완료 항목은 총 **27개**다. 아래 목록은 누락 없이 원문 순서대로 묶었다.

| 절 | 미완료 항목 |
| --- | --- |
| Windows 스모크 7개 | 압축 폴더에서 exe 실행; 브랜딩 아이콘; 좁은/넓은 창; 퀘스트·목표·뱅크샐러드 가져오기; 백업 왕복; 알림 설정 화면; 크래시 리포팅 기본 off |
| Web 스모크 5개 | 정적 서버에서 Chrome/Edge 로드; 새로고침 데이터 유지; Web API key 경고; 좁은/넓은 반응형; 크래시 리포팅 기본 off |
| Sentry 8개 | 기본 off; off 무전송; opt-in 이벤트 도달; opt-out 후 무전송; symbol/source map; privacy/retention/region; DSN 환경 분리; Windows/Linux 네이티브 크래시 제한 고지 |
| 서명 운영 3개 | 비밀번호를 코드/YAML 평문에 두지 않음; iOS 인증서/profile 저장소 밖 관리; keystore/인증서 안전 백업 |
| 실기기 4개 | Android signed AAB 실기기; iPhone/TestFlight; 양 플랫폼 저전력/배터리 최적화; Phase 4 cross-isolate 알림 액션 |

체크리스트 마지막 문장의 “이 여섯 가지”는 바로 앞 bullet 수(4개) 또는 이
문서의 전체 27개와 일치하지 않는다. Phase 3에서 단순 체크 표시뿐 아니라
항목별 증적 링크/빌드 SHA/기기 정보를 기록하도록 문서 구조를 바로잡는다.

---

## 2. 범위

### 2.1 포함

- 릴리즈 baseline 고정: version/ID, readiness, analyze/test, 플랫폼별 build 결과
- Android upload keystore 주입·signed AAB·서명 검증·내부 테스트 트랙
- iOS App ID/배포 서명/archive/IPA/TestFlight 절차와 실제 iPhone 검증
- macOS/Linux/Windows/Web release compile 및 가능한 스모크
- Sentry 테스트/운영 프로젝트 분리, DSN 주입, consent/network, stack mapping
- 개인정보처리방침 실제 값 확정과 공개 HTTPS URL
- Android/iOS Phase 4 알림 액션의 실기기 Go/No-Go
- Play Store/App Store 제출용 텍스트·그래픽·privacy 선언·심사 자료
- `RELEASE_CHECKLIST.md`의 27개 항목별 증적과 책임자 기록

### 2.2 제외

- 이 Phase에서 새로운 제품 기능, UI 리디자인, 데이터 모델 변경
- 스토어 심사 통과를 보장하는 일정 약속
- 계정 소유자 동의 없는 영구 ID 변경, 인증서/keystore 재발급
- Windows Store, Mac App Store, Linux package repository의 실제 제출
- 자체 백엔드, 원격 푸시, 계정/서버 동기화 도입
- Sentry 외의 analytics/advertising SDK 추가
- Android/iOS 검증 없이 알림 액션 플래그를 true로 변경

### 2.3 작업 스트림 분할

| 스트림 | 저장소에서 준비 | 외부 소유자가 완료 |
| --- | --- | --- |
| 스토어 자산 | copy deck, 캡처 시나리오, 파일 규격, 검수 체크리스트 | 계정에 업로드, 국가/가격/등급/심사 답변 |
| 앱 서명 | fail-closed 배관, CI secret 이름, 검증 명령 | keystore/인증서 발급·백업·콘솔 등록 |
| 실기기 | fixture와 테스트 시나리오 | Android 기기/iPhone에서 실행 및 증적 |
| Sentry | DSN compile-time gate, redaction 테스트 | 프로젝트·region·retention·token 확정, 대시보드 검증 |
| 개인정보 | TODO 위치와 사실관계 템플릿 | 운영 법인/문의/정책 결정, 공개 URL 승인 |
| 플랫폼 빌드 | OS별 CI/명령/산출물·hash | Apple signing, 스토어 업로드 및 심사 |

---

## 3. 작업 항목별 상세

모든 작업은 같은 release-candidate commit SHA를 기준으로 수행한다. 자격 증명,
DSN, 개인 연락처를 로그·artifact·PR 본문에 복사하지 않는다.

### 3.1 릴리즈 baseline과 ASCII 빌드 환경

**무엇을/어디서**

- `pubspec.yaml`의 `version: 1.0.0+1`과 4개 플랫폼 ID를 스토어 계정 소유자가
  승인한다.
- 로컬 검증은 `C:\src\human_status` 같은 ASCII-only clone에서 수행한다.
- `.github/workflows/ci.yml`의 Flutter `3.44.6`과 로컬 버전을 맞춘다.

**명령**

```powershell
git clone <공식 저장소 URL> C:\src\human_status
Set-Location C:\src\human_status
git checkout <release-candidate-sha>
flutter doctor -v
flutter pub get
dart run tool/check_release_readiness.dart --json
flutter analyze --no-pub
flutter test --no-pub
```

**검증/증적**

- clone의 `git rev-parse HEAD`를 빌드 기록에 남긴다.
- analyze `0`, test `0`, readiness는 서명 주입 전 예상된 서명 issue만 허용한다.
- 기존 한글 경로 실패 로그는 “코드 회귀”가 아니라 “검증 환경 제약”으로 보존한다.

**Go/No-Go**

- Go: ASCII clone/CI에서 analyze와 985개 이상 전체 테스트가 통과하고 새 실패가
  없다.
- No-Go: 한글 경로 실패를 코드/Gradle 옵션으로 우회한 결과만 있거나, 서로
  다른 SHA의 플랫폼 artifact를 조합한다.

### 3.2 Android upload key와 signed AAB

**무엇을/어디서**

- 기존 Play 앱/키가 있으면 새 키를 만들지 말고 기존 upload key를 복구한다.
- 신규 앱이면 계정 소유자가 `keytool`로 upload keystore를 발급하고 암호화된
  별도 저장소에 백업한다.
- 로컬은 gitignored `android/key.properties`, CI는 네 `ANDROID_*` 환경 변수와
  runner 임시 파일을 사용한다. 실제 값은 어떤 tracked 파일에도 쓰지 않는다.
- CI를 추가할 때 keystore base64 secret은 임시 파일로 복원하고 job 종료 때
  runner와 함께 폐기한다.

**명령**

```powershell
# 소유자가 신규 키가 필요하다고 승인한 경우에만
keytool -genkeypair -v `
  -keystore C:\secure\human-status-upload.jks `
  -alias human_status_release `
  -keyalg RSA -keysize 2048 -validity 10000

Copy-Item android/key.properties.example android/key.properties
# 파일을 편집해 실제 값 입력. 출력/커밋 금지.

dart run tool/check_release_readiness.dart --json
flutter build appbundle --release --no-pub `
  --dart-define=SENTRY_DSN=<운영 또는 테스트 DSN>
```

CI에서는 환경 변수 4개를 주입한 뒤 동일 명령을 실행한다. Play 업로드용 결과는
`build/app/outputs/bundle/release/app-release.aab`다. Flutter 공식 문서도 Play
Store에 app bundle을 권장한다:
[Build and release an Android app](https://docs.flutter.dev/deployment/android).

**검증/증적**

```powershell
dart run tool/check_release_readiness.dart
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
Get-FileHash build/app/outputs/bundle/release/app-release.aab -Algorithm SHA256
```

- readiness가 `ready: true`, 종료 `0`이어야 한다.
- 인증서 fingerprint를 Play Console에 승인된 upload certificate와 대조한다.
- AAB의 package/versionCode/versionName이
  `io.github.underkim.humanstatus`/`1`/`1.0.0`과 일치하는지 확인한다.
- Play Console internal testing에 업로드하고 Play가 생성한 APK를 실제 기기에
  설치한다.

**Go/No-Go**

- Go: 키 백업 복구 시험, readiness, signed AAB, fingerprint 대조, internal
  track 설치가 모두 성공.
- No-Go: debug key, unsigned AAB, 키의 유일 사본, 평문 secret, package ID
  불일치, 이미 사용된 versionCode.

### 3.3 iOS App ID, signing, archive, TestFlight

**무엇을/어디서**

- Apple Developer Portal에 `io.github.underkim.humanstatus` App ID를 등록하고
  `ios/Runner.xcodeproj/project.pbxproj`의 Runner bundle ID와 대조한다.
- Distribution certificate와 provisioning profile은 Keychain/Developer
  Portal/CI secret에서만 관리한다.
- Xcode signing team과 capability를 확인한다. 저장소에 profile/private key를
  커밋하지 않는다.

**명령(macOS)**

```sh
flutter doctor -v
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build ios --release --no-codesign --no-pub

# 실제 배포 서명 환경
flutter build ipa --release --no-pub \
  --dart-define=SENTRY_DSN=<운영 또는 테스트 DSN>
```

필요하면 Xcode에서 `ios/Runner.xcworkspace`를 열고 Runner scheme →
Any iOS Device → Product → Archive 후 Validate App/Distribute App을 수행한다.
명령과 archive는 같은 SHA여야 한다.

**검증/증적**

- archive의 bundle ID, marketing version, build number, signing team,
  distribution certificate를 Organizer에서 확인한다.
- App Store Connect에 validate/upload하고 TestFlight processing 완료를
  확인한다.
- 실제 iPhone에서 새 설치/업데이트, 알림 권한, Keychain API key, 백업
  가져오기/내보내기, Sentry consent를 확인한다.

**Go/No-Go**

- Go: signed archive validation, TestFlight 설치, 실기기 필수 시나리오 통과.
- No-Go: simulator/no-codesign build만 성공, wildcard/mismatched profile,
  개인 인증서의 유일 사본, 실제 iPhone 미검증.

### 3.4 `kQuestCompletionNotificationActionEnabled` 게이트

**무엇을/어디서**

- 대상 파일은 `lib/services/notification_service.dart`의 상수와
  `lib/services/notification_action_handler.dart` dispatcher다.
- 플래그를 바꾸기 전 Android/iOS 각각에서 foreground Flutter 엔진과
  notification background 엔진이 같은 Hive 파일을 접근하는 시나리오를
  수행한다.

**검증 시나리오**

1. QA fixture에 활성 퀘스트 정확히 1개와 알려진 XP/스탯/업적 상태를 만든다.
2. 플래그 true인 내부 QA 빌드에서 일일 알림을 예약한다.
3. 앱 foreground에서 같은 퀘스트 완료와 알림 action을 근접하게 실행한다.
4. 앱 background/종료 상태에서도 action을 각각 실행한다.
5. action 연속 탭, stale payload, 이미 완료/삭제된 퀘스트, 프로세스 재시작,
   저전력/배터리 최적화를 반복한다.
6. 퀘스트가 한 번만 완료되고 XP/업적/목표 보상이 한 번만 반영되는지 확인한다.
7. 앱 복귀 후 Hive cache/UI가 디스크 상태와 일치하는지 확인한다.

**명령**

```sh
flutter test --no-pub test/notification_schedule_mode_test.dart
flutter test --no-pub test/notification_action_handler_test.dart
flutter test --no-pub test/quest_completion_execution_lock_test.dart
```

마지막 파일은 저장소에 실제 존재하는 경우에만 사용한다. 구현 시 테스트명이
달라지면 `rg --files test | rg "notification|completion.*lock"`으로 실제
대상을 다시 찾는다. 실기기 실행은 `flutter run --release -d <device-id>` 또는
내부 배포 빌드로 한다.

**Go/No-Go**

- Go: Android와 iOS 모두 중복 XP 0건, 상태 손실 0건, stale action 안전 no-op,
  foreground 재동기화 성공. 증적에 OS/기기/앱 SHA/시나리오/전후 값을 남긴다.
  그때만 플래그 변경을 독립 커밋한다.
- No-Go: 한 플랫폼이라도 재현 실패/불확실, emulator/simulator만 확인, Hive
  cache stale, lock timeout 시 데이터 일부 반영. 플래그는 `false`로 유지하고
  스토어 설명/스크린샷에서 이 기능을 제거한다.

### 3.5 Sentry 실계정 배선과 네트워크 게이트

**무엇을/어디서**

- 테스트와 운영 Sentry 프로젝트를 분리한다.
- region, retention, 조직/프로젝트 slug를 운영자가 기록한다.
- DSN은 secret/환경에서 `--dart-define`으로만 주입한다.
- symbol/source map 업로드에 필요한 auth token은 최소 권한으로 만들고
  artifact 업로드 job에만 노출한다. 실제 도입 방식은 고정된
  `sentry_flutter: 8.14.2`와 Sentry 공식 Flutter 문서를 기준으로 검증한 뒤
  lockstep으로 CI와 체크리스트를 갱신한다.

**빌드/검증**

```sh
# DSN 없는 fail-closed 빌드
flutter build web --release --no-pub

# 테스트 프로젝트 DSN이 있는 QA 빌드
flutter build web --release --no-pub \
  --dart-define=SENTRY_DSN=<test-project-dsn>
```

각 지원 플랫폼에서 다음 매트릭스를 실행한다.

| 상태 | 행위 | 기대 |
| --- | --- | --- |
| 새 설치/업데이트/백업 복원 | 설정 확인 | consent `false` |
| DSN 없음 + consent on | synthetic Dart 오류 | SDK 미초기화, 요청 0 |
| 테스트 DSN + consent off | 일반 사용/synthetic 오류 | Sentry 요청 0 |
| 테스트 DSN + consent on | 비식별 synthetic 오류 1건 | 테스트 프로젝트에 정확히 1건 |
| consent on→off | 신규 오류/재연결 | 앱이 트리거하는 신규 전송 0; 네이티브 보류 큐 한계는 정책과 릴리즈 노트에 명시 |
| release artifact | 오류 이벤트 | readable stack, release/version/environment가 대상 artifact와 일치 |

프록시 캡처와 Sentry 대시보드 양쪽 증적을 사용하되 DSN 전체와 event의 민감
필드를 스크린샷에서 가린다.

**Go/No-Go**

- Go: 기본 off, off 무전송, opt-in 1건, opt-out 신규 0건, readable stack,
  개인정보 문서와 실제 region/retention 일치.
- No-Go: DSN 하드코딩, 운영/테스트 혼용, 실제 사용자 데이터로 synthetic test,
  unreadable stack, off 상태 요청 발생.

### 3.6 `privacy_policy.md` TODO 확정과 공개 URL

**무엇을/어디서**

- `docs/privacy_policy.md`의 11개 TODO를 운영자가 승인한 실제 값으로 바꾸고
  제목의 “(초안)” 및 상단 경고를 제거한다.
- Sentry의 실제 처리 법인/region/retention을 계정 설정과 계약 문서로 대조한다.
- 앱 안의 bundled 문서와 공개 HTTPS 페이지의 내용/시행일을 같은 release에서
  일치시킨다.
- 정책 URL은 로그인, 지역 차단, 다운로드가 필요 없는 공개 HTTPS URL이어야
  한다.

Google Play는 모든 앱에 Play Console과 앱 내부의 개인정보처리방침 및 Data
safety 선언을 요구한다:
[Google Play Developer Program Policy](https://support.google.com/googleplay/android-developer/answer/17190352?hl=en),
[Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).
Apple도 모든 앱에 privacy policy URL과 App Privacy 답변을 요구한다:
[Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

**검증**

```powershell
rg -n '\[TODO|초안' docs/privacy_policy.md
flutter test --no-pub test/settings_data_privacy_dialog_test.dart
```

- `rg` 결과가 0건이어야 한다.
- 공개 URL을 로그인하지 않은 Chrome/Edge/Safari와 모바일 네트워크에서 연다.
- Play Data safety/App Privacy 답변과 문서의 Sentry, 로컬 저장, 백업, API key
  설명을 필드별로 대조한다.

**Go/No-Go**

- Go: 법무/운영 승인, TODO 0, 공개 URL 200, 앱 내/웹 내용 일치, 콘솔 선언 일치.
- No-Go: 예시 값, 개인 이메일 무단 게시, region/retention 추정, 저장소 raw URL의
  가용성을 검증하지 않은 상태.

### 3.7 Windows release 검증

**무엇을/어디서**

- ASCII clone 또는 `.github/workflows/release-artifacts.yml`의
  `windows-release` artifact를 사용한다.
- `build/windows/x64/runner/Release` 폴더 전체를 배포 단위로 취급한다.

**명령**

```powershell
flutter build windows --release --no-pub
$exe = 'build/windows/x64/runner/Release/human_status.exe'
Test-Path $exe
Get-FileHash $exe -Algorithm SHA256
```

**검증**

- 새 Windows 사용자/VM에서 zip을 풀고 별도 개발 도구 없이 실행한다.
- 체크리스트의 Windows 7개 항목과 이전 버전 JSON 백업 왕복을 수행한다.
- 아이콘은 `windows/runner/resources/app_icon.ico`, 제품 메타데이터는
  `windows/runner/Runner.rc`의 `Human Status`로 확인한다.

**Go/No-Go**

- Go: CI artifact hash 일치, clean VM 실행, 7개 스모크 전부 통과.
- No-Go: exe만 따로 배포, 한글 checkout 실패를 제품 실패와 혼동, 개발 PC에서만
  실행.

### 3.8 Web release 검증과 배포

**무엇을/어디서**

- 현재 로컬에서 성공한 `build/web` 또는 release-artifacts의 Web zip을
  immutable preview에 배포한다.
- `web/manifest.json`, `web/index.html`, 아이콘과 deep-link/base href 전략을
  대상 host에서 확인한다.

**명령**

```powershell
flutter build web --release --no-pub
Set-Location build/web
python -m http.server 8080
```

**검증**

- 최신 Chrome/Edge에서 체크리스트 Web 5개와 백업 왕복을 확인한다.
- 새로고침/캐시 비우기/새 버전 배포 뒤 데이터 유지와 service worker 갱신을
  확인한다.
- HTTPS preview에서 Claude API key 경고, 개인정보 문서, Sentry off/on을
  확인한다.

**Go/No-Go**

- Go: 정적 서버와 실제 HTTPS host 양쪽에서 5개 스모크 통과.
- No-Go: 로컬 compile 성공만으로 production deploy 완료 선언, HTTP에서만
  검증, 이전 service worker가 새 artifact를 가리는 상태.

### 3.9 Linux release 검증

**무엇을/어디서**

- Ubuntu runner/VM에서 `linux/CMakeLists.txt`의
  `APPLICATION_ID = io.github.underkim.humanstatus`로 release bundle을 만든다.
- 자동 백업이 Windows/Linux 전용이므로 실제 폴더 선택·쓰기·7개 retention을
  Linux에서 반드시 확인한다.

**명령(Ubuntu)**

```sh
flutter doctor -v
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build linux --release --no-pub
```

**검증/Go-No-Go**

- clean supported distro VM에서 bundle 실행, libsecret 기반 API key, 파일
  picker, 백업 왕복/자동 백업, 알림 설정 화면, Sentry Dart 오류를 확인한다.
- Go는 compile+clean VM 스모크 통과다. 패키징을 한다면 Flatpak/Snap은 각
  sandbox 권한과 secret service/file picker를 별도 검증한다.
- No-Go는 Windows에서 cross-compile을 시도하거나 compile만으로 package
  repository 준비 완료를 선언하는 것이다.

### 3.10 macOS release 검증

**무엇을/어디서**

- macOS runner에서 `macos/Runner/Configs/AppInfo.xcconfig`의 bundle ID,
  `macos/Runner/Release.entitlements`, icon asset을 기준으로 release build한다.
- Mac App Store 제출이 Phase 3 목표인지 direct distribution인지 먼저 결정한다.

**명령(macOS)**

```sh
flutter doctor -v
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build macos --release --no-pub
```

**검증/Go-No-Go**

- clean Mac에서 launch, Keychain, file picker/백업, notification UI, Sentry,
  code signing/notarization(배포 방식에 해당하면)을 확인한다.
- Go는 target 방식에 맞는 서명/실행 증적까지 있는 경우다.
- No-Go는 unsigned local `.app`만으로 일반 배포 가능하다고 선언하는 것이다.

### 3.11 스토어 자산 제작과 검수

**무엇을/어디서**

- 저장소의 실제 브랜딩 원본은
  `assets/branding/human_status_icon_master.png`; `pubspec.yaml`의
  `flutter_launcher_icons` 설정이 플랫폼 아이콘을 생성한다.
- 스크린샷은 release candidate와 비식별 fixture에서만 캡처한다.
- 설명에는 실제 제공 기능만 넣고, 플래그 false인 알림 완료 액션이나 미지원
  자동 백업 플랫폼을 광고하지 않는다.

**검증**

- 스크린샷마다 앱 SHA, 플랫폼, 기기 크기, locale, fixture version을 기록한다.
- 최신 console upload validator로 크기/alpha/파일 형식을 최종 검증한다.
- Google Play의 asset 요구사항은
  [Add preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en),
  Apple은
  [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)
  및
  [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
  을 기준으로 한다. Apple은 현재 1~10장의 screenshot을 허용한다.

**Go/No-Go**

- Go: 실제 UI와 설명 일치, 개인/재무/API key/DSN 노출 없음, 필수 locale·device
  slot 통과.
- No-Go: mockup이 실제 기능을 암시, placeholder icon, 테스트 개인정보 노출,
  플래그 false 기능 홍보.

---

## 4. 플랫폼별 실현 가능성

| 플랫폼 | 현재 Windows·무실기기 환경에서 가능 | 사용자가/별도 runner가 해야 함 | 최종 Phase 3 판정 |
| --- | --- | --- | --- |
| Android | SDK/Java 확인, Dart test, ID·서명 배관 정적 검사, ASCII clone에서 AAB compile 가능 | upload key/Play 계정, signed AAB, internal track, 최소/최신 실기기, 알림·저전력·Sentry·cross-isolate | 외부 게이트 전 No-Go |
| iOS | 소스/Bundle ID/테스트 정적 검사만 가능 | macOS/Xcode, Apple Developer/App Store Connect, certificate/profile, archive/TestFlight, iPhone | 이 환경에서 완결 불가 |
| macOS | 소스/ID/entitlement 정적 검사만 가능 | macOS runner, release build, signing/notarization 또는 Mac App Store 정책, clean Mac 스모크 | 이 환경에서 완결 불가 |
| Linux | 소스/ID/테스트 계획 가능; Windows cross-build 불가 | Ubuntu runner/VM release build, libsecret/file picker/자동 백업 스모크, 선택 시 Flatpak/Snap | Linux runner 후 판정 |
| Windows | 도구 설치됨; ASCII clone/CI에서 release 가능, release-artifacts 존재 | clean VM 수동 7항목 스모크와 artifact hash 대조 | 이 세션에서 가장 많이 완결 가능 |
| Web | 현재 release build 성공, Chrome/Edge 사용 가능 | 실제 HTTPS host deploy, service worker/새로고침/브라우저 스모크, 공개 privacy URL | host 검증 후 Go 가능 |

---

## 5. 스토어 제출 자산 체크리스트

콘솔 필드는 정책과 계정 유형에 따라 바뀔 수 있으므로 제출 직전에 위 공식 링크와
실제 Console의 required 표시를 다시 확인한다.

### 5.1 Google Play

- [ ] 앱 이름, 기본 언어, 카테고리, 연락 이메일/웹사이트
- [ ] 짧은 설명(현재 공식 가이드상 80자 이하), 전체 설명(4,000자 이하)
- [ ] 고해상도 Play listing icon
- [ ] feature graphic
- [ ] 실제 Android release 화면의 phone screenshots
- [ ] tablet/Chromebook 등 실제 배포 device form factor용 자산(해당 시)
- [ ] promo video URL(선택)
- [ ] 공개 HTTPS 개인정보처리방침 URL과 앱 내부 접근
- [ ] Data safety: Sentry와 로컬/자동 백업/Claude API key 처리까지 반영
- [ ] Content rating, target audience/children, ads 여부
- [ ] App access: 로그인이 없음을 설명; Claude key가 선택 기능임을 심사 메모에 기재
- [ ] 권한/민감 API 선언과 알림/정확 알람 사용 설명(실제 manifest 기준)
- [ ] 국가/지역, 가격, 개발자 계정/결제 프로필/연락처 검증
- [ ] signed AAB, versionCode 미사용 확인, Play App Signing/upload certificate
- [ ] internal/closed test 결과와 pre-launch report 검토
- [ ] 릴리즈 노트: Windows/Linux가 아니라 Android 실제 동작만 기술
- [ ] 알림 완료 액션 플래그가 false면 listing/스크린샷/릴리즈 노트에서 제외

### 5.2 Apple App Store

- [ ] App Store Connect 앱 레코드: 이름, primary language, Bundle ID, SKU
- [ ] subtitle, description, keywords, primary/secondary category
- [ ] support URL, privacy policy URL, marketing URL(선택)
- [ ] iPhone screenshots 1~10장; 지원 기기에 iPad가 포함되면 해당 slot도 확인
- [ ] app preview(선택, device size/language당 최대 3개)
- [ ] Xcode asset catalog의 1024×1024 App Store icon 및 alpha 검증
- [ ] App Privacy: Sentry 포함 제3자 SDK의 데이터 처리까지 정확히 선언
- [ ] age rating, content rights, Made for Kids 여부, 암호화/export compliance
- [ ] 가격, availability, 계약·세금·은행 정보(유료/판매 조건에 해당 시)
- [ ] signed archive/IPA, build number 미사용, TestFlight processing
- [ ] 실제 iPhone QA와 TestFlight tester 결과
- [ ] App Review contact, 심사 메모, 선택적 Claude API 기능 설명
- [ ] 계정이 없어 demo login은 불필요하다는 설명과 주요 기능 탐색 경로
- [ ] 알림 권한/백그라운드 action 검증 결과; 플래그 false면 기능 미기재
- [ ] Sentry opt-in 기본 off와 개인정보처리방침 접근 경로 설명

---

## 6. 리스크와 완화

| 리스크 | 가능성/영향 | 조기 신호 | 완화 | 최종 owner |
| --- | --- | --- | --- | --- |
| keystore 분실/비밀번호 분실 | 중/치명적 | 단일 로컬 사본 | 암호화 백업 2곳, 복구 시험, fingerprint 기록 | 계정 소유자 |
| debug/잘못된 키로 AAB | 중/치명적 | fingerprint 불일치 | fail-closed Gradle, readiness, `keytool -printcert`, Play 대조 | Android release owner |
| 영구 ID 오등록 | 낮/치명적 | Console ID와 저장소 불일치 | 앱 레코드 생성 전 2인 승인 | 계정 소유자 |
| 한글 경로 도구 실패 | 높/중 | analyze 255, app.dill path 깨짐, AGP path check | ASCII clone/CI를 공식 build 환경으로 고정 | release engineer |
| versionCode/build 중복 | 중/높음 | Console upload 거절 | 제출마다 `+N` 증가, release tag와 매핑 | release engineer |
| Sentry off 상태 전송 | 낮/치명적 | 프록시 요청/대시보드 event | real transport test, 기본 off, DSN 없는 CI | privacy/Sentry owner |
| Sentry stack unreadable | 중/높음 | 난독화 stack만 표시 | 동일 SHA symbol/source map 보존·업로드 검증 | Sentry owner |
| 정책과 실제 Sentry 설정 불일치 | 중/치명적 | region/retention 값 차이 | 계정 화면 증적, 법무 승인, release gate | privacy owner |
| 개인정보 URL 비공개/깨짐 | 중/높음 | 로그인/404/지역 차단 | 외부 네트워크와 Safari/Chrome 확인, uptime owner | web owner |
| 알림 action 중복 XP/Hive stale | 중/치명적 | XP 2회, 복귀 UI 불일치 | 플래그 false 유지, 양 플랫폼 cross-isolate matrix | mobile QA |
| iOS signing/profile mismatch | 중/높음 | archive validation 실패 | 명시 App ID, distribution profile, TestFlight 선검증 | iOS owner |
| store listing과 실제 기능 불일치 | 중/높음 | QA/심사자가 기능 재현 불가 | RC 캡처, 기능 플래그 기반 copy 검수 | product owner |
| Web service worker가 구버전 유지 | 중/중 | deploy 후 이전 UI | versioned deploy, cache-clear/upgrade smoke, rollback | web owner |
| Windows exe만 배포해 DLL/data 누락 | 중/높음 | clean VM 시작 실패 | Release 폴더 전체 zip, artifact hash, VM smoke | Windows owner |
| Linux/macOS compile만으로 배포 선언 | 중/중 | clean OS 실행 증적 없음 | OS별 bundle/signing/runtime gate 분리 | platform owner |
| 사용자 실제 데이터가 QA/Sentry에 노출 | 낮/치명적 | event/screenshot에 재무·API key | 비식별 fixture, redaction, 캡처 검수 | QA/privacy owner |

---

## 7. 순차 커밋·작업 제안과 merge gate

실제 구현자는 각 단계에서 기존 사용자 변경을 보존하고, 시크릿 파일은 stage하지
않는다. 외부 계정 작업은 커밋과 별도의 release log에 증적을 남긴다.

### 커밋 1 — 릴리즈 사실관계와 검사 강화

대상 후보:

- `docs/RELEASE_CHECKLIST.md`
- `tool/check_release_readiness.dart`
- `tool/release_readiness/checker.dart`
- 관련 `test/*release*`

작업:

- 존재하지 않는 로컬 keystore를 “있다”고 단정하는 문구 제거
- 27개 미완료 항목에 owner/evidence/date/SHA 기록란 추가
- 필요하면 privacy TODO, notification flag, CI release coverage를 별도
  non-secret readiness category로 추가

Merge gate:

- 검사 unit test, `dart run ... --json` schema test, analyze/test 통과
- 자격 증명 값이 오류/fixture에 노출되지 않음
- 기존 서명 없는 개발/Android debug build가 계속 가능

### 커밋 2 — Android signed release CI

대상 후보:

- 신규 또는 기존 `.github/workflows/*`의 Android release job
- `docs/RELEASE_CHECKLIST.md`
- CI script/test

작업:

- protected environment의 secrets로 임시 keystore 복원
- 네 `ANDROID_*` 환경 변수 주입
- readiness → signed AAB → fingerprint/hash → artifact 업로드
- PR/일반 CI에는 운영 secret을 노출하지 않고 수동/tag/protected ref로 제한

Merge gate:

- fork PR에 secret 노출 없음
- debug CI는 기존대로 통과
- 승인된 protected run에서 readiness 0, AAB와 hash 생성
- log/artifact 이름과 내용에 비밀번호/DSN/token 없음

### 커밋 3 — Linux/Apple 플랫폼 build coverage

대상 후보:

- `.github/workflows/ci.yml` 또는 별도 플랫폼 workflow
- 관련 build 문서

작업:

- Ubuntu Linux release build
- macOS iOS `--no-codesign` compile과 macOS release compile
- 실제 signing/archive는 protected 수동 workflow 또는 운영 Mac 절차로 분리

Merge gate:

- 세 OS에서 같은 Flutter `3.44.6`
- Linux/macOS/iOS compile success
- CI 시간/캐시/timeout이 안정적
- no-codesign 성공을 signed archive 성공으로 표시하지 않음

### 커밋 4 — Sentry 배포 배선과 정책 확정

대상 후보:

- Sentry artifact 설정/워크플로
- `docs/privacy_policy.md`
- `docs/RELEASE_CHECKLIST.md`
- 필요한 Sentry release 설정 코드와 테스트

작업:

- 테스트/운영 DSN 환경 분리
- symbol/source map 업로드와 release 식별자 통일
- 운영자가 승인한 11개 TODO 실제 값 반영
- 공개 HTTPS privacy URL 배포

Merge gate:

- TODO/“초안” 0
- DSN/token hardcode 0
- off 무전송, opt-in 1건, opt-out 신규 0건
- readable stack과 artifact SHA/release 일치
- 법무/운영 승인

### 외부 Gate A — Android/iOS 실기기와 Phase 4

작업:

- RELEASE_CHECKLIST의 Android/iOS/저전력/cross-isolate 4개 항목 실행
- 결과에 device, OS, SHA, fixture, 전후 데이터 기록

판정:

- 둘 다 통과하면 다음 커밋 진행
- 하나라도 실패/미실행이면 플래그 false로 모바일 release를 진행하거나 모바일
  전체를 No-Go로 한다. 제품 설명에는 action을 넣지 않는다.

### 커밋 5 — 알림 action 활성화(조건부, 단일 변경)

대상:

- `lib/services/notification_service.dart`
- 플래그 기본값을 assert하는 실제 테스트
- 릴리즈 체크리스트/릴리즈 노트

Merge gate:

- 외부 Gate A 증적 링크
- 전체 analyze/test
- Android/iOS signed build 재생성
- 실패 시 이 커밋 하나만 revert해 기능을 안전하게 끌 수 있음

### 작업 6 — 스토어 자산 freeze와 제출 후보 생성

작업:

- RC 빌드로 Play/App Store 자산 캡처
- 설명/privacy 선언/심사 메모 2인 검수
- Play internal/closed 및 TestFlight 최종 후보 업로드

Gate:

- listing이 실제 플래그/플랫폼 지원과 일치
- 개인·재무·API key·DSN 노출 0
- console validator의 required field 0건

### 작업 7 — 최종 release decision

한 장의 release evidence index에 다음을 연결한다.

- commit/tag/SHA, Flutter version
- analyze/test/readiness 결과
- 6개 플랫폼 build 결과와 artifact hash
- Android certificate fingerprint, Apple archive/TestFlight build
- Windows/Web/Linux/macOS 스모크
- Android/iPhone 실기기 matrix
- Sentry/privacy 증적
- Play/App Store 자산 승인
- 알려진 제한과 rollback owner

모든 필수 gate owner가 승인한 뒤에만 production track/App Review 제출을
실행한다.

---

## 8. 완료 기준(Definition of Done)

### 8.1 저장소 DoD

- [ ] release candidate는 ASCII 경로 또는 CI에서 `flutter analyze --no-pub`
      종료 `0`
- [ ] 전체 `flutter test --no-pub` 통과(현재 baseline 985개보다 감소하면 사유 승인)
- [ ] 실제 release 자격 증명 환경에서
      `dart run tool/check_release_readiness.dart --json`이
      `"ready": true`, 종료 `0`
- [ ] 영구 ID `io.github.underkim.humanstatus`와 스토어 앱 레코드 일치
- [ ] `pubspec.yaml` version/build가 제출 후보 및 양 스토어와 일치
- [ ] secret/keystore/certificate/profile/DSN/token이 tracked 파일·로그·artifact에
      노출되지 않음
- [ ] `docs/privacy_policy.md` TODO/초안 표시 0, 공개 URL과 앱 내 문서 일치
- [ ] `RELEASE_CHECKLIST.md`의 기존 27개 `[ ]`가 단순 체크가 아니라 증적과 함께
      닫힘

### 8.2 빌드·런타임 DoD

- [ ] Android signed AAB 생성, fingerprint 대조, Play internal track 실기기 설치
- [ ] iOS signed archive validate/upload, TestFlight 실제 iPhone 설치
- [ ] macOS release build와 선택한 배포 방식에 맞는 signing/runtime 검증
- [ ] Linux release build와 clean VM 스모크
- [ ] Windows 전체 Release bundle zip과 clean VM 7항목 스모크
- [ ] Web release의 실제 HTTPS 배포와 5항목 스모크
- [ ] 이전 릴리즈 JSON 백업이 새 후보에서 복원되고 핵심 데이터가 동일

### 8.3 관측성·개인정보 DoD

- [ ] 6개 플랫폼 각각에서 가능한 범위의 Sentry 기본 off 확인
- [ ] 실제 네트워크 off 0건, opt-in synthetic 1건, opt-out 신규 0건
- [ ] release stack symbol/source map 가독성 확인
- [ ] Windows/Linux 네이티브 crash 지원 차이를 릴리즈 노트에 고지
- [ ] Play Data safety와 App Privacy 답변이 코드·정책·Sentry 설정과 일치

### 8.4 알림 action DoD

- [ ] Android/iOS cross-isolate, 중복 탭, stale payload, 종료 상태, 저전력 matrix
      통과
- [ ] 중복 XP/업적/목표 보상 0건, foreground cache 불일치 0건
- [ ] 통과한 경우에만 `kQuestCompletionNotificationActionEnabled == true`
- [ ] 미통과 시 플래그 `false` 유지 및 모든 스토어 자산에서 기능 제외

### 8.5 제출 DoD

- [ ] Play/App Store 필수 텍스트·그래픽·privacy·등급·심사 필드 완료
- [ ] 모든 screenshot은 동일 RC의 실제 UI이고 민감정보가 없음
- [ ] artifact hash, build SHA, version, signing identity가 evidence index와 일치
- [ ] 각 플랫폼의 Go/No-Go owner와 rollback owner가 명시됨
- [ ] production rollout/App Review 제출은 계정 소유자의 명시 승인 후 실행

위 항목 중 계정·실기기·서명·개인정보 승인 항목이 하나라도 비어 있으면 Phase 3의
저장소 준비 작업은 완료로 표시할 수 있어도 **프로덕션 출시 완료**로 표시하지
않는다.
