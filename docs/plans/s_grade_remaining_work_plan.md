# 로컬 개인 사용 S급 잔여 작업 실행계획

## 1. 범위와 판정 원칙

- 대상: `underkim/human_status`의 `master`, 로컬 목표 플랫폼 Windows
- 기준: `docs/plans/s_grade_criteria_v3_FINAL.md`
- 작성일: 2026-07-24
- 제품 코드는 변경하지 않고 테스트와 증적 문서만 변경한다.
- 자동 테스트는 수동 기준을 보조하지만, 기준 문구가 Windows release의 사람 조작이나
  시각 확인을 명시하면 이를 대체하지 않는다.
- `integration_test`는 2026-07-24 현재 `pubspec.yaml`에 없다. 이번 작업을 위해 새
  패키지·runner 인프라를 억지로 추가하지 않는다.

## 2. 현재 결론

| ID | 이번 세션에서 자동화 가능한 부분 | 반드시 사람이 해야 하는 부분 | 현재 판정 |
|---|---|---|---|
| L-P2 | Windows release build, exe/hash 확인, 프로세스·창 30초 생존 확인 | 설정 진입, 퀘스트 생성·완료, 종료·재시작 뒤 완료 상태 육안 확인과 화면 증적 | 미통과 |
| L-M3 | widget harness에서 7화면×2테마×2뷰포트 28개 렌더, golden 생성·비교, Flutter render/overflow 예외 검사 | Windows release의 실제 글꼴로 clip, icon, 텍스트 가독성을 28/28 육안 확인 | 미통과 |
| L-C2 | widget test가 실제 `KeyEvent`를 보내 Ctrl+1..5, Ctrl+F, Ctrl+N, Escape, Ctrl+Tab 뒤 상태를 assertion | Windows release 창에 9개 동작을 직접 입력하고 상태 변화를 육안 확인 | 미통과 |

`test/wide_layout_test.dart`는 light 테마의 400×800/2560×1440 렌더를 화면별
개별 테스트로 다룰 뿐, 요구된 light/dark × 400×800/1440×900의 28조합과
screenshot 보존을 하지 않았다. 따라서
`test/local_s_grade_visual_matrix_test.dart`와 `test/goldens/l_m3/*.png` 28개를
추가했다.

widget golden은 Flutter의 Ahem 테스트 글꼴을 사용하여 문자가 사각형으로 보인다.
레이아웃·테마·viewport 회귀 및 framework overflow 검출에는 쓸 수 있지만 실제
텍스트 가독성 판정에는 쓸 수 없다. 이 한계 때문에 L-M3의 release 수동 확인을
생략하지 않는다.

`test/shortcuts/desktop_shortcuts_test.dart`는 기존에도 `sendKeyEvent` 계열 API로
Ctrl+F/Ctrl+N/Escape/Ctrl+Tab을 검증했지만 Ctrl+1..5 중 Ctrl+2만 확인했다.
이번 세션에서 Windows platform override 아래 1부터 5까지 모두 입력하고
`NavigationRail.selectedIndex`가 0부터 4로 바뀌는지 검증하도록 보강했다.
이는 실제 OS 창으로 전달되는 native 입력은 아니므로 L-C2 수동 절차를 대체하지 않는다.

## 3. 자동 실행 명령과 증적

### L-M3 자동 렌더

```powershell
flutter test --no-pub --update-goldens test/local_s_grade_visual_matrix_test.dart
flutter test --no-pub test/local_s_grade_visual_matrix_test.dart
```

- 생성물: `test/goldens/l_m3/` 아래 PNG 28개
- 결과: 28/28 생성 및 즉시 비교 실행 성공, render/overflow 예외 0
- 비교 정책: Windows 생성본과 Ubuntu CI의 Skia 차이가 28장 전체에서
  0.06%~1.47%로 측정되어 cross-platform 허용치를 2%로 고정했다. 2% 초과는
  실패하며 framework render/overflow 예외는 허용치 없이 즉시 실패한다.
- 자동으로 판정하지 못하는 것: 실제 Windows 글꼴의 가독성, 미세 clip, 의미상 잘못된
  icon, release runner와 widget harness 사이의 차이

### L-C2 자동 키 이벤트

```powershell
flutter test --no-pub test/shortcuts
```

- 확인 상태: 최상위 탭 index 0..4, 검색 TextField·focus, `QuestFormScreen`,
  검색 닫힘, 퀘스트 내부 TabController 순환
- 결과: 10 tests, 실패 0
- 한계: `integration_test` 패키지/Windows runner가 없고 widget binding에 주입한
  KeyEvent이므로 확정 기준의 “Windows release 수동 실행”을 대신하지 않는다.

### L-P2 자동 빌드·생존 확인

한글 checkout의 Windows build는 경로가 mojibake되어 `app.dill`을 읽지 못했다.
확정 기준 1.4의 ASCII-only clean clone 대체 절차를 사용한다.

```powershell
flutter build windows --release --no-pub
Get-FileHash build/windows/x64/runner/Release/human_status.exe -Algorithm SHA256
$p = Start-Process build/windows/x64/runner/Release/human_status.exe -PassThru
Start-Sleep -Seconds 30
Get-Process -Id $p.Id | Select-Object Id,ProcessName,Responding,MainWindowTitle
```

최종 평가 SHA의 실제 clone 경로, hash, 프로세스 결과는 전체 테스트와 커밋이 끝난 뒤
이 문서의 실행 결과 절에 기록한다.

## 4. 사람이 그대로 수행할 체크리스트

증적에는 공통으로 `owner`, 날짜, 최종 commit SHA, Windows 버전, 화면 배율,
release exe SHA-256을 적고 각 지정 단계의 screenshot을 보존한다.

### 4.1 L-P2 수동 스모크 — 정확히 8단계

- [ ] 1. `build/windows/x64/runner/Release/human_status.exe`를 실행하고 작업 관리자와
  앱 창이 함께 보이는 screenshot을 남긴다. 30초 뒤에도 `Human Status` 창이
  응답하며 crash dialog가 없어야 한다.
- [ ] 2. 최초 실행 온보딩이 보이면 화면 안내대로 완료하거나 `건너뛰기`를 눌러
  `홈` 화면에 도달한다. 기존 개인 데이터가 있으면 이 단계는 “기존 데이터로 홈 표시”로
  기록한다.
- [ ] 3. 왼쪽/아래의 `더보기`를 누르고 목록의 `설정`을 누른다. AppBar 제목 `설정`과
  설정 목록이 보여야 하며 screenshot을 남긴다.
- [ ] 4. `퀘스트` 탭으로 이동하고 오른쪽 아래 `+`를 누른다. AppBar 제목
  `퀘스트 추가`가 보여야 한다.
- [ ] 5. 제목에 고유 문자열 `L-P2 smoke <YYYYMMDD-HHMM>`을 입력하고 필수값을
  채운 뒤 `추가하기`를 누른다. 진행중 목록에 같은 제목의 카드가 정확히 1개 보여야
  하며 screenshot을 남긴다.
- [ ] 6. 그 카드의 `완료`를 한 번 누른다. `"<제목>" 완료!` 안내가 보이고
  `완료` 탭에 같은 제목이 정확히 1개 있어야 하며 screenshot을 남긴다.
- [ ] 7. 앱 창을 정상 종료하고 작업 관리자에서 `human_status.exe`가 사라졌음을
  확인한 뒤 같은 exe를 다시 실행한다. crash/복구 경고 없이 홈이 떠야 한다.
- [ ] 8. `퀘스트` → `완료`로 이동해 같은 고유 제목이 여전히 정확히 1개이고
  완료 상태임을 확인한다. 화면 screenshot을 남기고 8/8, crash 0, 데이터 유실 0을
  체크 행에 기록한다.

### 4.2 L-M3 release 시각 확인 — 정확히 7단계 + 28개 체크 행

- [ ] 1. 최종 SHA의 release exe와 SHA-256, Windows 버전, 디스플레이 배율을 기록한다.
- [ ] 2. Windows `설정 → 시스템 → 디스플레이`와 앱 창 크기 조절 도구를 사용해
  앱 client 영역을 먼저 400×800, 다음 1440×900으로 맞출 방법을 준비한다.
- [ ] 3. 앱 설정/Windows 앱 테마를 이용해 light를 고정하고 7개 화면을 순회한다.
- [ ] 4. 각 화면에서 전체 창 screenshot을 저장하고 아래 light 14행을 판정한다.
- [ ] 5. dark를 고정하고 같은 두 viewport에서 같은 7개 화면을 순회한다.
- [ ] 6. 각 화면에서 전체 창 screenshot을 저장하고 아래 dark 14행을 판정한다.
- [ ] 7. 28장을 100% 확대해 overflow 경고, 잘린 콘텐츠, 깨진 icon, 읽을 수 없는
  텍스트가 모두 0인지 재검수하고 28/28일 때만 L-M3 통과로 서명한다.

각 행은 `owner/date/SHA/environment/evidence 파일명`을 함께 적는다.

| 화면 | 테마 | viewport | overflow 0 | clip 0 | 깨진 icon 0 | 읽기 불가 텍스트 0 | evidence |
|---|---|---:|---|---|---|---|---|
| 온보딩 | light | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 온보딩 | light | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 대시보드 | light | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 대시보드 | light | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 퀘스트 | light | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 퀘스트 | light | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 목표 | light | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 목표 | light | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 재무 | light | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 재무 | light | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 리포트 | light | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 리포트 | light | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 설정 | light | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 설정 | light | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 온보딩 | dark | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 온보딩 | dark | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 대시보드 | dark | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 대시보드 | dark | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 퀘스트 | dark | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 퀘스트 | dark | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 목표 | dark | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 목표 | dark | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 재무 | dark | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 재무 | dark | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 리포트 | dark | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 리포트 | dark | 1440×900 | [ ] | [ ] | [ ] | [ ] | |
| 설정 | dark | 400×800 | [ ] | [ ] | [ ] | [ ] | |
| 설정 | dark | 1440×900 | [ ] | [ ] | [ ] | [ ] | |

### 4.3 L-C2 Windows release 키 입력 — 정확히 12단계

- [ ] 1. release exe를 실행하고 앱 본문을 한 번 클릭해 keyboard focus를 준다.
- [ ] 2. `Ctrl+1`을 눌러 `홈` 탭이 선택되고 대시보드가 보이는지 확인한다.
- [ ] 3. `Ctrl+2`를 눌러 `퀘스트` 탭이 선택되는지 확인한다.
- [ ] 4. `Ctrl+3`을 눌러 `목표` 탭이 선택되는지 확인한다.
- [ ] 5. `Ctrl+4`를 눌러 `재무` 탭이 선택되는지 확인한다.
- [ ] 6. `Ctrl+5`를 눌러 `더보기` 탭이 선택되는지 확인한다.
- [ ] 7. `Ctrl+2`로 퀘스트로 돌아온 뒤 `Ctrl+F`를 눌러 `퀘스트 검색` 입력창과
  caret가 보이는지 확인한다.
- [ ] 8. `Escape`를 눌러 검색 입력창이 닫히고 퀘스트 목록이 유지되는지 확인한다.
- [ ] 9. `Ctrl+N`을 눌러 `퀘스트 추가` 화면이 열리는지 확인한다.
- [ ] 10. `Escape` 또는 화면의 뒤로가기로 퀘스트 목록으로 돌아온다. 이 Escape는
  기준의 9동작에 추가된 복귀 조작이며 별도 기능 통과 수에는 넣지 않는다.
- [ ] 11. `Ctrl+Tab`을 세 번 눌러 퀘스트 내부 탭이 `진행중 → 예정 → 완료 → 진행중`
  순으로 바뀌는지 확인한다.
- [ ] 12. 단계 2~9와 11의 총 9개 요구 동작이 모두 기대 상태를 만들었음을 한 장 이상의
  화면/영상 증적으로 연결하고 9/9로 서명한다.

## 5. 스토어 출시 로드맵 - 보류

**아래 항목은 사용자가 명시적으로 착수를 지시하기 전까지 실행하지 않는다.**
이번 세션에서는 계정 개설, 기기 구매, 서명 설정, Sentry DSN, privacy TODO,
스토어 자산/업로드를 변경하거나 실행하지 않는다.

| ID | 착수 전 필요한 선행 조건 |
|---|---|
| S-E1 | Android/iOS/macOS/Linux/Windows/Web OS runner, Flutter 3.44.6 고정 환경, artifact 보관소 |
| S-P1 | Android upload signing key와 안전한 CI secret 관리, release 책임자 승인 |
| S-P2 | 법무/운영의 개인정보 처리방침 확정, 공개 HTTPS 호스팅과 도메인 비용·승인 |
| S-P3 | Google Play Console 개발자 계정·비용, upload certificate, 최소/최신 Android 실기기 2대 |
| S-P4 | Apple Developer 계정·연회비, macOS/Xcode, 인증서/provisioning, App Store Connect, iPhone |
| S-P5 | 공개 지원 플랫폼 결정, clean Windows/Linux/macOS 기기 또는 runner, HTTPS Web 환경 |
| S-P6 | Sentry 조직/프로젝트·DSN, 개인정보/telemetry 승인, proxy·symbol/source map 운영 절차 |
| S-P7 | release owner와 검수자, 최종 RC SHA, 27개 항목별 외부 증적 저장 위치 |
| S-M1 | Play/App Store console 계정, 최종 icon/screenshot/copy/rating/privacy 자산, 독립 검수자 2명 |
| S-M2 | Android/iPhone 사용자 각 5명, 실기기, 동의/모집 비용, 60과업 기록 양식 |
| S-M3 | 대표 Android/iPhone/Windows 기기, DevTools 측정 담당자, 30 cold starts/100 animations 시간 |
| S-C1 | TalkBack/VoiceOver/Narrator/Orca/Web reader 환경과 사용자/전문 검수자, 120과업 시간 |
| S-C2 | Windows/macOS/Linux/Web 실환경, keyboard-only 검수자, Web 200% zoom 환경 |
| S-C3 | 현재 master switch가 off이므로 해당없음. 기능 노출 결정·Android/iOS 실기기 전까지 보류 |
| S-C4 | 지원 버전 정책, 버전 고정 이전 backup fixture, 공개 지원 플랫폼별 RC 기기 |

## 6. 이번 세션 실행 결과

- 자동화 평가 SHA: `71c9c156e9706ae7f1d9397ecbfd549d5da78687`
- `flutter test --no-pub`: exit 0, `+1052: All tests passed!`, skip 0
- L-M3 update-goldens: 28/28 생성 성공; 비교 모드: 28/28 성공
- 첫 CI run `30092544838`: Windows 생성 golden과 Ubuntu Skia의 0.06%~1.47%
  pixel 차이로 28개가 실패하여 2% cross-platform comparator를 추가했다.
- L-C2 shortcuts: 10 tests, 실패 0
- 원 한글 checkout Windows build: 경로 mojibake로 `app.dill` read 실패
- ASCII clone `C:\codex_tmp\human_status_s_grade_8dbc7d2`에서 HEAD `71c9c15`:
  release build exit 0
- exe SHA-256: `59138CB81A658C4EC6E02DC0677325014E8F13E0FF877F1707535ECBD2F8E59C`
- 30초 생존: PID 611260, `ProcessName=human_status`, `Responding=True`,
  `MainWindowTitle=Human Status`; 확인 뒤 테스트 프로세스 정상 종료
- CI run `30093006861`: SHA `71c9c15`, Quality (Ubuntu)와 Windows smoke build
  모두 completed/success. analyze, 1,052 tests, Web release, debug APK,
  Windows release 전 단계 성공.
