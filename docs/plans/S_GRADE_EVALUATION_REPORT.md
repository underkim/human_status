# Human Status S급 재평가 보고서

## 1. 평가 대상과 원칙

- 저장소/브랜치: `underkim/human_status`, `master`
- 평가 코드 SHA: `71c9c156e9706ae7f1d9397ecbfd549d5da78687`
- 기준: `docs/plans/s_grade_criteria_v3_FINAL.md`
- 평가일: 2026-07-24

실행하거나 열어 확인한 사실만 통과로 판정했다. 수동/외부 증적이 없으면 코드가
준비돼 보여도 미통과다.

## 2. 로컬 개인 사용 기준

### 엔지니어링 완성도

| ID | 판정 | 실제 근거 |
|---|---|---|
| L-E1 | 통과 | 제품 코드 변경 없이 기존 ASCII clone HEAD `809cf21`의 `flutter analyze --no-pub` → `No issues found!`, exit 0. 이번 변경은 test/golden뿐이며 최종 CI의 analyze로 재확인한다. |
| L-E2 | 통과 | 원 checkout `flutter test --no-pub` → `+1052: All tests passed!`, exit 0, skip 0. |
| L-E3 | 통과 | 열거한 9개 파일이 `rg --files test`에 모두 존재하며 전체 test run에 포함되어 통과했다. |
| L-E4 | 통과 | `.github/workflows/ci.yml:29-41,61-75`에 analyze/test/Web/Windows 단계. `gh run view 30093006861` → SHA `71c9c15`, Quality (Ubuntu)와 Windows smoke build 모두 `completed/success`. |

축 판정: **통과**.

### 프로덕션/운영 안정성

| ID | 판정 | 실제 근거 |
|---|---|---|
| L-P1 | 통과 | ASCII clone HEAD `71c9c15`에서 Windows release build exit 0, `.../Release/human_status.exe` 존재. SHA-256 `59138CB81A658C4EC6E02DC0677325014E8F13E0FF877F1707535ECBD2F8E59C`. |
| L-P2 | 미통과 | 위 exe 프로세스 `611260`이 30초 뒤 `MainWindowTitle: Human Status`, `Responding: True`였다. 그러나 설정 진입·퀘스트 생성/완료·재시작 유지 4단계는 실제 조작/관찰하지 않았다. `docs/plans/s_grade_remaining_work_plan.md`의 8단계 체크리스트가 남아 있다. |
| L-P3 | 통과 | 열거한 7개 테스트 파일 존재, 전체 1,024 test run에서 실패 0. `crash_reporting_service.dart:61`은 compile-time `SENTRY_DSN`, `:204-214`는 PII/tracing/replay/screenshot/view hierarchy off. |

축 판정: **미통과**(L-P2).

### 시장 매력도

| ID | 판정 | 실제 근거 |
|---|---|---|
| L-M1 | 통과 | delight/action hub/dashboard/quest flow/reward/goal claim 파일 존재, 전체 test 통과. |
| L-M2 | 통과 | 온보딩·대시보드·목표/퀘스트 폼·재무·리포트 파일 존재, 전체 test 통과. |
| L-M3 | 미통과 | `test/local_s_grade_visual_matrix_test.dart`가 7화면×2테마×2뷰포트 28조합을 렌더했고 `test/goldens/l_m3/` PNG 28개 생성·비교와 overflow/render 예외 0을 확인했다. Windows/Ubuntu Skia 차이 0.06%~1.47%를 실측해 cross-platform 한계를 2%로 고정했다. 다만 Ahem 테스트 글꼴이라 실제 텍스트 가독성과 Windows release clip/icon을 판정할 수 없다. 남은 release 육안 검사는 실행계획의 7단계+28행 체크표에 있다. |

축 판정: **미통과**(L-M3).

### 현대적 편의성

| ID | 판정 | 실제 근거 |
|---|---|---|
| L-C1 | 통과 | `test/accessibility/` 6개 파일 존재, 전체 run에서 실패·스킵 0. 출력에 semantics, focus, 2배 글꼴, tap target/contrast 검사가 포함됐다. |
| L-C2 | 미통과 | `test/shortcuts/desktop_shortcuts_test.dart`에서 실제 KeyEvent로 Ctrl+1..5/Ctrl+F/Ctrl+N/Escape/Ctrl+Tab 상태 변화를 검증했고 shortcut 10 tests 및 전체 run이 통과했다. `integration_test`는 pubspec에 없다. widget binding 주입은 Windows release 수동 9동작을 대체하지 않으므로 실행계획의 12단계 체크리스트가 남아 있다. |
| L-C3 | 통과 | 열거한 wide layout/backup/import/settings 테스트 파일 존재, 전체 run 실패 0. |

축 판정: **미통과**(L-C2).

### 로컬 최종 판정

**비S급**이다. L-M3 28조합 렌더와 L-C2 9동작 KeyEvent 자동 증적을 추가했지만
확정 기준이 요구하는 Windows release 수동 증적은 L-P2, L-M3, L-C2 모두 아직
없다. 남은 절차는 `docs/plans/s_grade_remaining_work_plan.md`에 고정했다.

## 3. 스토어 출시 기준

### 엔지니어링 완성도

| ID | 판정 | 실제 근거 |
|---|---|---|
| S-E1 | 미통과 | 같은 SHA에서 Windows/Web release만 실제 성공했다. Android signed AAB, iOS, macOS, Linux artifact와 hash 증적이 없다. |
| S-E2 | 통과 | 관련 보안 테스트 파일 존재·전체 run 통과. `git ls-files`의 signing secret 확장자/`key.properties` 검색 결과 0. 실제 DSN은 코드에 없고 `String.fromEnvironment('SENTRY_DSN')`만 존재한다. |

축 판정: **미통과**.

### 프로덕션 출시 준비도

| ID | 판정 | 실제 근거 |
|---|---|---|
| S-P1 | 미통과 | readiness JSON exit 1, `"ready": false`; Android signing credential 누락, privacy TODO, draft marker의 3 issues. |
| S-P2 | 미통과 | `rg`가 `docs/privacy_policy.md:1,3,15-19,90-103,190-193`에서 초안 및 `[TODO:` 12개를 검출. 공개 HTTPS/운영 승인 증적 없음. |
| S-P3 | 미통과 | signed AAB fingerprint, Play internal track, Android 2기기 증적 없음. |
| S-P4 | 미통과 | signed archive/TestFlight/iPhone 증적 없음. |
| S-P5 | 미통과 | Windows build/창 실행과 Web compile만 확인. clean Windows/Linux/macOS/HTTPS Web의 플랫폼별 7과업 증적 없음. |
| S-P6 | 미통과 | 실제 Sentry DSN/프로젝트가 없고 off/on/off 네트워크 및 stack mapping 증적 없음. |
| S-P7 | 미통과 | `rg -n "^- \\[ \\]" docs/RELEASE_CHECKLIST.md` 집계 27개 미완료. 기존 `[x]`는 8개지만 27개 필수 외부 항목은 닫히지 않았다. |

축 판정: **미통과**.

### 시장 매력도

| ID | 판정 | 실제 근거 |
|---|---|---|
| S-M1 | 미통과 | Play/App Store console required field, 실제 자산, 2인 검수 증적 없음. |
| S-M2 | 미통과 | Android/iPhone 사용자 10명·60과업 표 없음. |
| S-M3 | 미통과 | 30회 cold start/100회 animation DevTools 측정 없음. |

축 판정: **미통과**.

### 현대적 편의성

| ID | 판정 | 실제 근거 |
|---|---|---|
| S-C1 | 미통과 | widget 접근성 테스트는 통과했지만 6개 실제 보조기술×20과업 증적 없음. |
| S-C2 | 미통과 | shortcut/widget 테스트는 통과했지만 4플랫폼×12 키보드 과업과 Web 200% 실제 증적 없음. |
| S-C3 | 해당없음 | `lib/services/notification_service.dart:151`에서 `kQuestCompletionNotificationActionEnabled = false`. handler도 이 master switch를 따르며, 현재 출시 자산 자체가 없어 기능 약속 증거도 없다. 기능을 켜면 재평가 필수다. |
| S-C4 | 미통과 | 백업 단위 테스트는 통과했지만 버전 고정 이전 fixture의 공개 지원 플랫폼별 RC 복원 증적 없음. |

축 판정: **미통과**.

### 스토어 최종 판정

**비S급**이다. 저장소 내부의 ID·버전·fail-closed 서명 배관과 테스트 기반은
좋지만, readiness가 명시적으로 실패하고 서명·privacy·실기기·Sentry·스토어
자산·접근성/성능 외부 증적이 없다.

## 4. 냉정한 결론

현재 코드는 1,052개 자동 회귀, L-M3 28조합 golden, L-C2 KeyEvent, Windows release
build/30초 생존이 재현된다. 그러나 v3가 요구하는 실제 사용자 조작과 release
시각·키보드 증적이 없으므로 로컬 S급은 아직 아니다. 스토어 S급은 실행하지 않았고
readiness가 fail-closed로 거절하는 기존 상태 그대로다.
