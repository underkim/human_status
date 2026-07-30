# 릴리즈 체크리스트

이 문서는 Human Status를 실제로 배포할 때 따라야 할 절차를 정리합니다. 크게
두 가지를 분명히 구분합니다.

- **배포 가능한 Windows/Web/Android(디버그) 아티팩트** —
  `.github/workflows/release-artifacts.yml` 워크플로가 지금 바로 만들어낼 수
  있는, 실행 가능한 결과물(zip/apk + 체크섬)입니다. 퍼머넌트 앱/번들 ID나
  스토어 등록이 필요 없습니다. Android는 디버그 키로 서명된 사이드로딩용
  APK이며, 스토어에 낼 수 있는 릴리즈 서명 빌드가 아닙니다(4~5절 참고).
- **스토어 출시 준비가 된 모바일 앱(Android/iOS)** — 영구 애플리케이션/번들 ID,
  실제 릴리즈 서명, 실기기 검증까지 끝나야 하며, 이 저장소는 그 조건이
  충족되기 전까지는 "스토어에 낼 준비가 됐다"고 주장하지 않습니다
  (`tool/check_release_readiness.dart`가 이를 강제합니다).

## 1. 로컬에서 릴리즈 아티팩트 만들기

CI 워크플로와 동일한 절차를 로컬에서도 그대로 실행할 수 있습니다.

```sh
flutter pub get

# Windows (Windows 머신에서만 가능)
flutter build windows --release
# 결과물: build/windows/x64/runner/Release/ 폴더 전체
#   (human_status.exe뿐 아니라 data/, 각종 .dll까지 전부 있어야 실행됩니다)

# Web
flutter build web --release
# 결과물: build/web/ 폴더 전체 (정적 파일 세트, 아무 정적 서버로 서빙 가능)

# Android (사이드로딩용 디버그 APK, 릴리즈 서명 불필요)
flutter build apk --debug
# 결과물: build/app/outputs/flutter-apk/app-debug.apk
```

`release-artifacts.yml` 워크플로(`workflow_dispatch` 또는 `v*` 태그 푸시로
실행)는 위 세 빌드를 각각 실행한 뒤, Windows/Web은 **실행에 필요한 폴더
전체**를 `human_status-windows-x64-<버전>.zip`, `human_status-web-<버전>.zip`
으로 압축하고, Android는 디버그 APK 파일을
`human_status-android-debug-<버전>.apk`로 그대로 담아, 각각 같은 이름의
`.sha256` 체크섬 파일과 함께 워크플로 아티팩트로 업로드합니다. GitHub Release
생성이나 외부 배포(스토어 등)는 하지 않으며, 저장소 시크릿도 사용하지
않습니다.

Android 산출물은 **디버그 키로 서명된 APK**입니다 — Play Store에는 낼 수
없지만, 안드로이드 기기에서 "출처를 알 수 없는 앱 설치"를 허용하고 이
APK 파일을 직접 열면 그대로 설치됩니다(개인 사이드로딩 용도). 스토어에 낼
release 서명 APK/AAB가 필요해지면 4~5절의 영구 ID/키스토어 절차를 먼저
끝내야 합니다.

`<버전>` 라벨은 태그 이름/수동 입력값을
`tool/ci/sanitize_version_label.sh`(Ubuntu)와
`tool/ci/sanitize_version_label.ps1`(Windows)로 정제해 만듭니다. 이 값들은
셸 스크립트 본문에 직접 끼워 넣지 않고 환경 변수로만 전달되어 셸 인젝션을
막고, 영숫자·점·대시·밑줄 이외 문자는 대시로 바뀌며, 앞뒤 점은 제거하고,
64자를 넘으면 잘라냅니다. 결과가 비어 있으면 `dev`로 대체됩니다.
`test/release_artifacts_version_label_test.dart`가 두 스크립트 모두에 대해
빈 입력/점만 있는 입력/64자 초과 입력 같은 경계값을 검증합니다.

### 워크플로 아티팩트 받기

1. GitHub 저장소 → Actions → "Release artifacts" 워크플로 실행 선택
2. 실행 상세 페이지 하단 "Artifacts" 목록에서
   `windows-release-<버전>`, `web-release-<버전>`,
   `android-debug-apk-<버전>` 중 필요한 것을 다운로드
3. Windows/Web은 압축을 풀면 `*.zip`과 `*.zip.sha256`이, Android는
   `*.apk`와 `*.apk.sha256`이 함께 들어 있습니다

### 체크섬 검증

다운로드한 zip이 손상되지 않았는지 확인하려면:

```sh
# Windows (PowerShell)
Get-FileHash .\human_status-windows-x64-<버전>.zip -Algorithm SHA256
# .sha256 파일에 적힌 해시와 (대소문자 무시하고) 같은지 눈으로 비교

# macOS/Linux
sha256sum -c human_status-web-<버전>.zip.sha256
```

## 2. 백업 호환성 확인

새 릴리즈를 내기 전에, 이전 버전에서 내보낸 백업(JSON)을 새 빌드로 가져오기
해서 데이터가 그대로 복원되는지 확인하세요.

1. 이전 릴리즈(또는 프로덕션에 가까운 실제 사용 데이터)에서 설정 → 백업
   내보내기로 JSON 파일을 만듭니다.
2. 새로 빌드한 Windows/Web 앱에서 같은 파일을 가져오기 합니다.
3. 스텟/퀘스트/목표/거래/업적 진행 상황이 내보내기 시점과 동일한지
   확인합니다. `test/backup_service_test.dart`가 스키마 단위 회귀는 잡아주지만,
   실제 배포용 아카이브로 한 번은 손으로 확인하세요.

## 3. Windows/Web 스모크 체크리스트

압축을 푼 뒤 실제로 실행해서 아래를 확인합니다.

**Windows**

- [ ] `human_status.exe`가 압축 해제한 폴더 안에서 (별도 설치 없이) 바로
      실행된다
- [ ] 앱 아이콘이 placeholder가 아니라 실제 브랜딩 아이콘으로 보인다
- [ ] 창 크기를 좁게/넓게 조절해도 레이아웃이 깨지지 않는다
      (`PageContentBounds`로 넓은 화면에서 중앙 정렬되는지 포함)
- [ ] 퀘스트 추가/완료, 목표 생성, 뱅크샐러드 파일 가져오기가 동작한다
- [ ] 백업 내보내기/가져오기가 동작한다
- [ ] 알림 관련 화면(알림 시간 설정)이 오류 없이 열린다
- [ ] 설정 → "익명 크래시 리포팅"이 기본 꺼짐으로 보인다(3.5절 참고)

**Web**

- [ ] `build/web`을 정적 서버로 띄운 뒤 (`python3 -m http.server` 등) 최신
      Chrome/Edge에서 로드된다
- [ ] 새로고침 후에도 데이터가 유지된다(웹 로컬 저장소 기반)
- [ ] Claude API 키 입력 시 "브라우저 저장 보호 수준이 낮다"는 경고가
      표시된다
- [ ] 반응형 레이아웃(좁은 폭 vs 넓은 폭)이 모두 정상이다
- [ ] 설정 → "익명 크래시 리포팅"이 기본 꺼짐으로 보인다(3.5절 참고)

## 3.5 크래시 리포팅(Sentry) 릴리즈 게이트

`sentry_flutter` 도입은 [docs/privacy_policy.md](privacy_policy.md)(현재
초안)와 짝을 이룹니다. 아래 항목은 실제 배포 전 6개 플랫폼 각각에서(적어도
빌드 가능한 플랫폼에서는 직접) 확인해야 합니다.

- [ ] **기본 꺼짐** — 새 설치, 기존 사용자 업데이트, 백업 가져오기 직후 모두
      설정의 스위치가 꺼짐 상태다(`crashReportingEnabled`는 백업 스키마에
      포함되지 않으므로 새 기기/가져오기 후에는 항상 기본값 `false`다).
- [ ] **off 상태 무전송** — 프록시(예: mitmproxy)나 Sentry 프로젝트의 수신
      통계로, 꺼짐 상태에서 앱을 평소처럼 사용해도 Sentry로 나가는 네트워크
      요청이 0건인지 확인한다. 이 저장소의 자동 테스트(`test/crash_reporting_service_test.dart`
      등)는 fake SDK 경계로 이 게이트 로직을 검증하지만, 실제 네트워크 계층
      확인은 대체하지 못한다.
- [ ] **opt-in 이벤트 도달** — 테스트 전용 Sentry 프로젝트 DSN으로 빌드한 뒤
      (`--dart-define=SENTRY_DSN=...`), 설정에서 켜고 synthetic 오류를
      1건 발생시켜 Sentry 대시보드에 실제로 도달하는지 확인한다. 실제 사용자
      데이터가 있는 기기 대신 비식별 QA fixture만 사용한다.
- [ ] **opt-out 후 무전송** — 끈 뒤 신규 이벤트 발생과 (있었다면) 보류 큐
      전송이 없는지 확인한다.
- [ ] **symbol/source map** — 릴리즈 스택이 읽을 수 있는 형태로 매핑되는지
      확인한다. 이 저장소는 아직 심볼/소스맵 자동 업로드를 CI에 배선하지
      않았다(`SENTRY_AUTH_TOKEN` 등 실제 Sentry 조직 자격 증명이 필요해 이번
      변경 범위 밖으로 남겨 두었다) — 도입 시 이 항목과
      `.github/workflows/ci.yml`/`release-artifacts.yml`을 함께 갱신한다.
- [ ] **privacy policy/retention/region 확정** — `docs/privacy_policy.md`의
      `[TODO]` 표시가 모두 실제 값으로 채워졌는지 확인한다(운영 법인, data
      region, 보관 기간, 문의처).
- [ ] **DSN 환경 분리** — 운영 DSN이 소스에 하드코딩되지 않고
      `--dart-define=SENTRY_DSN=...`로만 주입되는지, 로컬 개발/CI 빌드에는
      DSN이 없어 SDK가 아예 초기화되지 않는지 확인한다.
- [ ] **네이티브 크래시 지원 차이 고지** — Windows/Linux는 Dart/Flutter 예외만
      다루고 네이티브(C/C++) 크래시는 Android/iOS와 동등한 수준으로 잡지
      않는다는 점을 릴리즈 노트에 명시한다.

## 4. 영구 ID 이전 체크리스트 (모바일 스토어 출시 전 필수)

아래 ID들은 **한 번 스토어에 등록하면 사실상 바꿀 수 없는 영구 식별자**입니다.
현재 모든 플랫폼은 저장소 소유자 네임스페이스 기반의
`io.github.underkim.humanstatus`로 통일되어 있습니다.

- [x] **Android** — `android/app/build.gradle.kts`의 `namespace`와
      `applicationId`를 변경한다. Kotlin/Java 소스의 패키지 경로/디렉터리
      (`android/app/src/main/kotlin/` 아래, `MainActivity.kt`)는
      **applicationId가 아니라 namespace**를 따라야 하므로, namespace를
      바꿨다면 그 경로와 `MainActivity.kt`의 `package` 선언을 새 namespace와
      일치하도록 옮긴다. applicationId는 namespace와 달라도 되는 별개의
      값이다(예: 같은 소스에서 유료판 applicationId만 다르게 배포하는 경우).
- [x] **iOS** — `ios/Runner.xcodeproj/project.pbxproj`의
      `PRODUCT_BUNDLE_IDENTIFIER`(Runner 타깃)를 변경하고, Apple Developer
      계정에 동일한 Bundle ID로 App ID를 등록한다
- [x] **macOS** — `macos/Runner/Configs/AppInfo.xcconfig`의
      `PRODUCT_BUNDLE_IDENTIFIER`를 변경한다 (배포 대상이라면)
- [x] **Linux** — `linux/CMakeLists.txt`의 `APPLICATION_ID`를 변경한다
      (배포 대상이라면)
- [x] **버전** — `pubspec.yaml`의 `version`이 `MAJOR.MINOR.PATCH+빌드번호`
      형식이고 빌드 번호가 1 이상의 양의 정수인지 확인한다. `1.0.0+1`은
      `flutter create` 기본값이면서 동시에 정당한 첫 릴리즈 버전이므로 그
      자체로는 문제가 아니다 — 빌드 번호가 아예 없거나 0 이하일 때만
      실패로 취급한다. 스토어에 다시 올릴 때마다 빌드 번호(`+` 뒤 숫자)를
      반드시 올린다

이 전체 항목은 `tool/check_release_readiness.dart`가 자동으로 검사합니다:

```sh
dart run tool/check_release_readiness.dart          # 사람이 읽는 한글 리포트
dart run tool/check_release_readiness.dart --json    # 스크립트/CI 연동용 JSON
```

placeholder ID, debug 서명, 그리고(5절의) Android 릴리즈 서명 배관/자격
증명 문제 중 하나라도 남아 있으면 0이 아닌 코드로 종료하며, 어떤 파일의 어떤
값을 왜 바꿔야 하는지(또는 어떤 자격 증명이 비어 있는지) 각 항목마다
구체적으로 안내합니다 — 자격 증명 관련 안내에는 필드 이름과 입력 경로
(`android/key.properties`의 키 이름 또는 환경변수 이름)만 나오고, 실제 비밀
값은 절대 출력하지 않습니다.

## 5. 시크릿을 안전하게 다루는 서명 체크리스트

- [x] Android 릴리즈 키스토어는 저장소에 **절대 커밋하지 않는다** —
      `.gitignore`가 이미 `android/key.properties`, `*.jks`, `*.keystore`를
      막고 있다(`test/gitignore_signing_secrets_test.dart`가 회귀를 잡는다).
      다른 경로/확장자로 키를 보관한다면 그 패턴도 `.gitignore`에 추가하세요.
- [x] `android/app/build.gradle.kts`의 `buildTypes.release.signingConfig`가
      `signingConfigs.getByName("release")`를 가리키도록 구성되어 있다(더 이상
      `signingConfigs.getByName("debug")`를 참조하지 않음). 로컬에서는
      `android/key.properties`(커밋 금지) 파일에서, CI에서는 환경변수에서
      키스토어 정보를 읽어오며, **값이 비어 있지 않은 CI 환경변수가 항상
      `android/key.properties`보다 우선한다.** `assembleDebug`/`test`/
      `analyze` 같은 태스크는 자격 증명 없이도 계속 구성되고, 이름에
      "release"가 들어간 태스크(`assembleRelease`, `bundleRelease` 등, 대소문자
      구분 없음)만 자격 증명이 없거나 keystore 파일을 찾을 수 없을 때 빌드
      전에 어떤 항목이 빠졌는지 구체적으로 알려주며 즉시 실패한다. debug
      키로 조용히 대체되거나 서명 없이 아티팩트가 만들어지는 경로는 없다.
      (`tool/release_readiness/checker.dart`와
      `test/android_release_signing_test.dart`가 이 배관 자체와 자격 증명
      사용 가능 여부를 함께 검증한다.)
- [ ] 키스토어 비밀번호/별칭 비밀번호를 코드나 워크플로 YAML에 평문으로
      적지 않는다 — 항상 `secrets.*` 컨텍스트로만 참조한다
- [ ] iOS 배포 인증서/프로비저닝 프로필도 동일하게 저장소 밖(Keychain,
      Apple Developer Portal, 또는 CI 시크릿)에서만 관리한다
- [ ] 서명에 사용한 키스토어/인증서를 잃어버리지 않도록 안전한 곳(팀
      비밀번호 관리자 등)에 별도 백업해 둔다 — 분실 시 기존 스토어 등록을
      이어서 업데이트할 방법이 없다. **키스토어 비밀번호나 별칭을 잃어버리면
      기존 Play Console 등록을 이어서 업데이트할 방법이 전혀 없다** —
      새 앱으로 처음부터 다시 등록해야 한다.

### 5.1 로컬에서 release keystore 만들고 연결하기

`android/app/human-status-upload.jks`와 `android/key.properties`는 어느
작업 환경에도 기본으로 존재하지 않습니다(`.gitignore`가 막고 있고, 실제로
발급·주입해야만 생깁니다) — `dart run tool/check_release_readiness.dart`가
`android_release_signing_credentials_missing`을 보고하면 아직 없는 것입니다.
두 파일이 생기면 Git에서 계속 제외되며, 분실하면 기존 앱의 업데이트 배포가
불가능할 수 있으므로 암호화된 별도 저장소에 즉시 백업해야 합니다. 아래
절차로 새로 발급하거나 기존 keystore를 이 환경에 연결하세요.

이미 발급받은 keystore가 있다면 아래 1~2단계는 건너뛰고 3단계부터 진행하세요.

1. JDK에 포함된 `keytool`로 새 release keystore를 생성합니다 (예시일 뿐이며,
   실제 조직 이름/유효기간은 상황에 맞게 정하세요):

   ```sh
   keytool -genkeypair -v \
     -keystore release-keystore.jks \
     -alias human_status_release \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

   실행 중 keystore 비밀번호와 key 비밀번호를 입력하라는 프롬프트가
   나옵니다 — 이 두 값을 반드시 기억/기록해 두세요(다음 단계에서 씁니다).
2. 생성된 `release-keystore.jks`를 저장소 **밖**(예: 저장소 상위 폴더나 팀
   비밀번호 관리자와 동기화되는 안전한 위치)으로 옮깁니다. 저장소 안에
   두더라도 `.gitignore`가 `*.jks`를 막지만, 실수로 강제 추가(`git add -f`)
   하는 사고를 피하려면 아예 저장소 밖에 두는 편이 안전합니다.
3. `android/key.properties.example`을 복사해 `android/key.properties`를
   만들고, 방금 만든 값으로 채웁니다:

   ```sh
   # macOS/Linux
   cp android/key.properties.example android/key.properties
   # Windows (PowerShell)
   Copy-Item android/key.properties.example android/key.properties
   ```

   ```properties
   # android/key.properties (커밋 금지 -- 이미 .gitignore에 있음)
   storeFile=C:/Users/me/keys/release-keystore.jks
   storePassword=여기에_실제_keystore_비밀번호
   keyAlias=human_status_release
   keyPassword=여기에_실제_key_비밀번호
   ```

   `storeFile`은 절대 경로든 `android/` 디렉터리 기준 상대 경로든 그대로
   동작합니다. **주의:** 이 파일은 Java `Properties` 형식으로 읽히며,
   `Properties`는 백슬래시(`\`)를 이스케이프 문자로 취급합니다. Windows
   경로를 쓸 때는 위 예시처럼 슬래시(`C:/Users/me/...`)를 쓰거나, 굳이
   백슬래시를 쓰려면 반드시 두 번 겹쳐 써야 합니다
   (`C:\\Users\\me\\keys\\release-keystore.jks`) — `C:\Users\me\...`처럼
   한 번만 쓰면 파싱 과정에서 경로가 깨집니다. 이 제약은
   `android/key.properties` 파일 안에서만 적용되며, 아래 5.2절의
   `ANDROID_KEYSTORE_PATH` 환경변수는 `Properties` 파싱을 거치지 않으므로
   단일 백슬래시 경로를 그대로 써도 안전합니다.
4. `flutter build apk --release` 또는
   `flutter build appbundle --release`를 실행합니다. 네 값 중 하나라도
   비어 있거나 `storeFile`이 가리키는 파일이 없으면, Gradle이 빌드를
   시작하기 전에 어떤 항목이 문제인지 알려주며 즉시 실패합니다(비밀 값
   자체는 오류 메시지에 나오지 않습니다).

### 5.2 CI에서 환경변수로 주입하기

CI에서는 `android/key.properties` 파일을 아예 만들지 말고, 아래 네
환경변수를 (예: GitHub Actions의 암호화된 저장소/환경 시크릿으로) 주입하세요:

| 환경변수 | 대응하는 `key.properties` 필드 |
| --- | --- |
| `ANDROID_KEYSTORE_PATH` | `storeFile` |
| `ANDROID_STORE_PASSWORD` | `storePassword` |
| `ANDROID_KEY_ALIAS` | `keyAlias` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` |

keystore 파일 자체는 시크릿 텍스트로 저장할 수 없으므로, base64로 인코딩한
시크릿을 워크플로 실행 중에 파일로 복원한 뒤 그 경로를
`ANDROID_KEYSTORE_PATH`로 넘기는 방식이 일반적입니다(예: `echo "$KEYSTORE_BASE64"
| base64 -d > $RUNNER_TEMP/release.jks`, 그 뒤 `ANDROID_KEYSTORE_PATH=$RUNNER_TEMP/release.jks`).
값이 비어 있지 않은 이 네 환경변수는 로컬 `android/key.properties`보다 항상
우선하므로, 실수로 저장소에 로컬 파일이 남아 있어도 CI 결과에는 영향을
주지 않습니다. 현재 이 저장소의 `.github/workflows/*.yml`은 어떤 저장소
시크릿도 사용하지 않으며(2절 참고), 위 네 환경변수를 실제로 주입하는 배포용
워크플로는 아직 이 저장소에 추가되어 있지 않습니다 — 실제 스토어 릴리즈
파이프라인을 구성할 때 팀 CI 설정에 맞게 추가해야 합니다.

## 6. Android/iOS 실기기 게이트

CI와 로컬 모두 에뮬레이터/시뮬레이터 이상의 실기기 검증을 대체할 수
없습니다. 스토어에 제출하기 전 최소 한 번은:

- [ ] **Android** — `flutter build appbundle --release`(영구 ID/서명 완료
      후)로 만든 AAB를 실제 Android 기기(가능하면 최소 지원 SDK 기기 1대,
      최신 기기 1대)에 설치해 알림 예약(정확/비정확 알람 권한 차이 포함),
      백업 가져오기/내보내기, 뱅크샐러드 파일 가져오기를 확인한다
- [ ] **iOS** — 실제 iPhone에서 TestFlight 또는 개발자 기기 설치로 알림
      권한 프롬프트, Keychain 기반 API 키 저장, 백업 가져오기/내보내기를
      확인한다
- [ ] 두 플랫폼 모두 저전력 모드/배터리 최적화 상태에서도 예약된 알림이
      과도하게 지연되지 않는지 확인한다
- [ ] **Phase 4 알림 액션(알림에서 바로 퀘스트 완료) 게이트** —
      `docs/plans/phase4_notification_action_plan.md` 4.4절이 요구하는
      실기기 cross-isolate 검증(두 Flutter 엔진이 같은 Hive 파일을 동시에
      쓰는 상황)을 통과하기 전까지는
      `lib/services/notification_service.dart`의
      `kQuestCompletionNotificationActionEnabled`를 `true`로 바꾸지 않는다.
      이 검증을 통과하고 플래그를 켜기 전에는 이 기능(알림의 완료 액션,
      백그라운드/포그라운드 완료 처리)을 배포하지 않는다.

이 문서 3·3.5·6절의 항목(현재 27개: Windows 7 + Web 5 + Sentry 8 + 서명 운영 3 +
실기기 4)이 모두 증적과 함께 끝나야 "모바일 스토어 출시 준비 완료"라고 말할 수
있습니다. 그 전까지는 Windows/Web 아티팩트만 배포 가능한 상태입니다.

### 6.1 항목을 완료 처리할 때 남겨야 하는 증적

이 문서의 각 `[ ]`를 `[x]`로 바꿀 때는 단순 체크만으로 끝내지 말고, 그 항목
바로 아래에 한 줄로 다음을 남깁니다(예시):

```
- [x] Android 실기기에서 알림 예약·백업 가져오기 확인
      — owner: <이름>, evidence: <스크린샷/로그 링크 또는 파일 경로>,
        date: 2026-MM-DD, SHA: <검증한 커밋 SHA>
```

owner(누가 확인했는지), evidence(스크린샷·로그·콘솔 캡처 등 확인 가능한
근거), date(확인한 날짜), SHA(어떤 커밋을 기준으로 확인했는지)가 모두 있어야
그 항목을 완료로 인정합니다. evidence가 없는 `[x]`는 실제로는 미완료로
간주합니다.
