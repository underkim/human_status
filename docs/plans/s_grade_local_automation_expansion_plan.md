# S등급 Windows 로컬 자동화 확장 계획

> **이 문서는 계획 전용이며 이번 세션에서는 어떤 자동화 스크립트도 실제로 실행하지 않았다. 사용자의 후속 지시가 있어야 실제 실행 단계로 넘어간다.**

## 1. 목적과 범위

이 계획은 `docs/plans/s_grade_remaining_work_plan.md` 4절에서 사람이 직접 수행하도록 남겨 둔
L-P2, L-M3, L-C2를 Windows 10 실기기에서 어느 정도 자동 재현할 수 있는지 사전 판단하고,
승인 후의 실행 순서와 판정 기준을 정한다. 조사 기준 저장소는
`underkim/human_status`, 브랜치는 `master`, 조사 시작 SHA는
`b821e1c835333fe5fb032f9dc605ca0db400a750`이다.

이번 문서 작성 중에는 앱, UI Automation, SendKeys/SendInput, 창 조작, 캡처, 이미지 비교를
실행하지 않았다. 기존 문서와 Dart/C++ 소스, 이전 세션이 남긴 로그·JSON·스크립트만 읽었다.
실제 실행 단계에서도 제품 코드, 테스트 코드, runner, 의존성은 변경하지 않고 별도 임시
PowerShell 도구와 증적만 사용한다.

## 2. 이전 시도의 잔여물

다음 untracked 경로는 의미 있는 산출물이므로 삭제하지 않고 그대로 보존한다.

- `tool/manual_evidence/windows_release_evidence.ps1`: UIA 트리 열거, 창 포커스·크기 조절,
  키 입력, `PrintWindow` 캡처, 픽셀 비교, 사용자 Hive 격리·복구를 시도한 PowerShell 도구
- `test-results/windows-release-evidence/20260724-*`: 5회 실행의 로그, JSON, PNG,
  격리한 Hive 파일
- 완료된 `21:54:45`, `21:56:13` 실행은 각각 L-C2 기록 13개, L-P2 생성·완료·재시작,
  light 화면 10개를 남겼다. 두 실행 모두 UIA descendant는 `FLUTTERVIEW` Pane 1개뿐이고
  `semanticControlsExposed=false`였다.
- `21:57:33` 실행은 L-C2, L-P2와 첫 400×800 캡처까지 진행한 뒤 `results.json` 및
  `finally` 복구 로그 없이 중단됐다. `isolated-profile/original-documents-storage`에 원본
  Hive가 남고 Documents에는 이 실행에서 만든 Hive/lock이 남아 있으므로, 잔여 디렉터리를
  삭제하거나 다음 자동화가 이를 덮어써서는 안 된다.

따라서 이전 시도는 “빈 폴더/미완성 무가치 임시 파일”이 아니다. 이번 계획 승인 후 실행에
앞서 별도 사용자 확인을 받아 원본 저장소 복구 여부부터 결정해야 한다. 이 계획은 복구를
자동 승인하거나 수행하지 않는다.

## 3. 공통 사전 판단

### 3.1 Flutter Windows UIA 노출 가능성

`windows/runner/flutter_window.cpp`는 표준 `FlutterViewController`로 native
`FLUTTERVIEW` 자식 창을 붙이고 `HandleTopLevelWindowProc`에 메시지를 전달한다.
`windows/runner/main.cpp`도 별도 MSAA/UIA provider나 접근성 플래그를 등록하지 않는다.
즉 접근성 provider가 있다면 앱 runner가 아니라 해당 release에 포함된
`flutter_windows.dll` 엔진 구현이 제공해야 한다. 앱의 `lib/`에는 Material 위젯의 기본
semantics와 일부 명시적 `Semantics`가 있지만 Windows provider 활성화를 별도로 설정하는
코드는 없다.

소스만 보면 엔진이 semantics tree를 native UIA에 투영할 가능성은 있으나, 현재 release를
실제로 조사했던 잔여 결과는 ProcessId 기준 UIA tree에 `FLUTTERVIEW`
(`ControlType.Pane`) 하나만 노출됐음을 반복해서 기록한다. 따라서 현재 사전 결론은 다음과
같다.

- **현재 빌드의 개별 컨트롤을 `AutomationElement`로 찾을 수 있다고 가정하면 안 된다.**
- 승인 후에는 UIA 탐색을 가장 먼저 한 번만 수행하고, 개별 노드가 보일 때만 UIA 경로로
  진행한다.
- 노출되지 않으면 좌표를 창 client 비율로 환산한 Win32 입력과 캡처/OCR·이미지 비교를
  사용하며, 판정이 불명확한 항목은 즉시 사람 손 체크리스트로 되돌린다.

### 3.2 UIA가 노출될 경우의 이름 후보

Flutter Material 위젯은 보이는 텍스트, `Tooltip`, `InputDecoration` label/hint를 semantics
Name으로 합성할 수 있다. 다만 앱에는 UIA AutomationId를 직접 지정하는 Windows 전용
코드가 없고 Dart `ValueKey`가 AutomationId로 변환된다는 근거도 없다. 따라서
AutomationId는 우선 빈 값으로 예상하고 Name, ControlType, 지원 pattern 조합을 사용한다.

| 대상 | 소스 근거 | 예상 Name 후보 | 예상 pattern/비고 |
|---|---|---|---|
| 더보기 탭 | `home_shell.dart` destination label | `더보기` | SelectionItem/Invoke |
| 설정 행 | `more_screen.dart` ListTile title | `설정`, 또는 subtitle이 합쳐진 이름 | Invoke |
| 퀘스트 탭 | `home_shell.dart` destination label | `퀘스트` | SelectionItem/Invoke |
| 검색 버튼/필드 | `quests_screen.dart` tooltip/hint | `퀘스트 검색` | Invoke, Edit/Value |
| 퀘스트 추가 FAB | `quests_screen.dart`, add icon | `추가`, `퀘스트 추가` 가능성 | Name이 비거나 generic일 수 있음 |
| 폼 제목 | `quest_form_screen.dart` label | `제목` | Edit/Value |
| 연결 스텟 | 같은 파일의 label | `연결 스텟` | ComboBox/ExpandCollapse |
| 난이도 | 같은 파일의 label | `난이도` | ComboBox/ExpandCollapse |
| 제출 버튼 | 같은 파일의 text | `추가하기` | Invoke |
| 퀘스트 카드 | `quest_card.dart`의 `Text(quest.title)` | 실행 시 만든 고유 제목 | Text; 카드 전체에 합쳐질 수 있음 |
| 완료 버튼 | `quest_completion_button.dart` | `완료`; Dart key `questCompletionLabel`은 UIA ID로 간주하지 않음 | Invoke |
| 내부 탭 | `quests_screen.dart` | `진행중 (n)`, `추천 (n)`, `완료 (n)` | SelectionItem |
| 설정 화면 제목 | `settings_screen.dart` | `설정` | Text/Header |

UIA 탐색은 완전 일치 → 정규식(개수 suffix 허용) → ControlType/pattern과 bounding rectangle
교차 확인 순서로 한다. 같은 Name이 여러 개면 예상 부모/화면 영역과 활성 상태로 좁히며,
유일성이 확보되지 않으면 Invoke하지 않는다.

## 4. L-P2: 설정 진입, 퀘스트 생성·완료·재시작 유지

### 4.1 자동화 가능성

- 설정 진입: UIA 노출 시 Name 기반 Invoke가 가능하다. 미노출 시 `Ctrl+5`로 더보기에
  진입한 뒤 상대 좌표 클릭과 화면 제목 OCR/이미지 영역 비교가 필요하다.
- 퀘스트 생성·완료: UIA 노출 시 Edit의 ValuePattern/키 입력과 InvokePattern으로 가능하다.
  미노출 시 `Ctrl+2`, `Ctrl+N`, 포커스 후 SendInput 텍스트 입력, 상대 좌표 클릭으로
  재현 가능하지만 폼 layout 변화에 취약하다.
- 재시작 유지: 고유 제목을 UIA Text Name으로 정확히 1개 찾는 것이 가장 강한 판정이다.
  UIA 미노출 시 완료 탭 캡처에 Windows OCR을 적용해 고유 제목을 정확히 1회 찾고, 원본
  캡처도 보존한다. 단순 전체 화면 픽셀 유사도만으로 데이터 유지를 통과시키지 않는다.
- 작업 관리자와 앱 창을 함께 담는 원래 1단계 증적, crash dialog 부재의 완전한 판정은
  사람 검수를 유지한다. 프로세스 생존·`Responding`·창 제목은 자동 보조할 수 있다.

### 4.2 승인 후 실행 순서

1. 사용자에게 잔여 Hive 복구 여부를 확인하고, 앱 프로세스가 0개인지 확인한다. 원본 저장
   데이터는 복사본으로만 다루며 현재 잔여물을 재사용하거나 삭제하지 않는다.
2. release exe의 경로·SHA-256, commit SHA, Windows 버전, DPI/배율, 모니터 해상도를
   manifest에 기록한다.
3. 별도 임시 사용자 데이터 사본을 준비한 뒤 앱을 시작하고 MainWindowHandle과 ProcessId를
   확정한다. 30초 생존, `Responding=true`, 제목 `Human Status`를 확인한다.
4. ProcessId로 UIA Window를 찾고 descendants의 Name, AutomationId, ControlType,
   bounding rectangle, 지원 pattern을 JSON으로 덤프한다. 개별 의미 노드가 2개 이상
   안정적으로 보일 때만 이후 UIA Invoke/Value 경로를 선택한다.
5. 온보딩이면 `건너뛰기`를 UIA Name 또는 검증된 상대 좌표로 누르고, 홈 제목/대표 영역
   변화로 도달을 확인한다.
6. `더보기` → `설정`을 Invoke하고 `설정` 제목과 설정 목록의 두 개 이상 고유 텍스트를
   확인해 캡처한다. 뒤로 돌아간다.
7. `퀘스트` → 추가를 열어 화면 제목 `퀘스트 추가`를 확인한다. 고유 제목
   `L-P2 smoke <timestamp>`를 만들고 제목 Edit에 입력한다. 기본 연결 스텟·난이도가 이미
   유효한지 확인한 뒤 `추가하기`를 한 번만 Invoke한다.
8. 진행중 탭에서 고유 제목 exact match가 정확히 1개인지 확인하고 캡처한다. 해당 제목과
   같은 카드 영역 안의 `완료` 버튼만 Invoke한다.
9. 완료 안내 또는 목록 이동을 기다린 뒤 `완료 (n)` 탭을 선택한다. 고유 제목 exact
   match가 정확히 1개이고 진행중 목록에는 0개인지 확인해 캡처한다.
10. `WM_CLOSE`로 정상 종료를 요청하고 제한 시간 안에 프로세스가 사라지는지 확인한다.
    강제 종료는 timeout 이후 정리 용도로만 쓰고 그 경우 정상 종료 항목은 실패 처리한다.
11. 같은 exe와 같은 격리 데이터로 재실행하고 `AutomationElement.FindFirst/FindAll`로
    퀘스트 화면의 완료 탭을 연다. 완료 목록에서 고유 제목을 exact match하여 개수가 1인지,
    진행중 목록에는 없는지 재확인한다. UIA가 없으면 OCR 결과와 캡처를 함께 사람에게
    넘긴다.
12. 프로세스를 종료하고 자동 판정, 원본 screenshot, UIA dump/OCR 결과를 연결한다.
    UIA/OCR가 고유 제목을 확정하지 못하면 L-P2는 자동 통과시키지 않고 기존 8단계 수동
    체크리스트로 되돌린다.

예상 소요 시간은 자동화 도구 준비·드라이런 3~5시간, 안정화 2~3시간, 최종 1회 실행
15~25분이다. UIA 미노출이나 좌표/OCR 불안정 시 대안은 기존 사람 손 8단계 전체 수행이다.

## 5. L-M3: 28개 release 화면 조합

### 5.1 캡처 계획

대상은 온보딩·대시보드·퀘스트·목표·재무·리포트·설정 7화면 × light/dark 2테마 ×
400×800/1440×900 client 2크기, 총 28장이다. 앱은 `ThemeMode.system`이므로 앱 내부
설정이 아니라 Windows 앱 테마를 따른다.

1. clean 격리 프로필을 복제해 온보딩용과 본 화면용 프로필을 분리한다.
2. MainWindowHandle에 `GetWindowRect`/`GetClientRect`를 적용해 non-client 차이를
   계산한 뒤 `SetWindowPos` 또는 `MoveWindow`로 client를 400×800, 1440×900에 맞춘다.
   호출 후 `GetClientRect` 실제값이 요청값과 정확히 같은 경우만 캡처한다.
3. Windows 개인 설정 UI 또는 승인된 사용자 범위 테마 설정을 light로 바꾸고
   `WM_SETTINGCHANGE` 반영 및 앱의 대표 배경/전경 색 변화가 안정될 때까지 기다린다.
   테마 변경 전 현재 값을 기록해 마지막에 반드시 복원한다.
4. 온보딩은 온보딩 전용 프로필로 캡처한다. 나머지는 본 화면 프로필에서 Ctrl+1..5와
   더보기의 `리포트`/`설정` 진입을 조합한다. 각 전환은 UIA 제목 또는 OCR/대표 영역
   signature로 확인한 후 캡처한다.
5. `PrintWindow(PW_RENDERFULLCONTENT)`를 우선 사용하되 검은/빈 프레임이면
   `BitBlt`/`CopyFromScreen`으로 해당 창 rectangle을 캡처한다. 창이 다른 창에 가리지
   않았고 foreground인지 manifest에 기록한다.
6. 같은 순서를 dark에서 반복한다. 28개 filename에는 screen/theme/client size/SHA를
   넣고 중복·누락을 manifest에서 검증한다.
7. Windows 테마, 창 위치, 사용자 데이터, 실행 프로세스를 원상 복구하고 자동 지표와
   사람 검수 열을 분리한 보고서를 만든다.

### 5.2 자동 판정과 사람 판정

자동 판정 가능한 항목:

- `GetClientRect`로 client 크기 정확 일치 여부
- PNG width/height, 파일 존재·해시, 28개 조합 중복/누락
- 빈 화면/단색 화면 비율, alpha 이상, 캡처 실패
- 기준 영역 mask를 사용한 색 범위로 light/dark 전환 여부
- 창 경계의 일정 폭 band, OCR/connected-component bounding box가 캡처 밖으로 닿는지,
  기준 이미지 대비 갑작스러운 edge 절단이 있는지에 대한 **clipping 의심 표시**
- 동일 화면·테마의 두 viewport 및 승인된 golden과의 perceptual/pixel diff

자동 판정만으로 확정할 수 없는 항목:

- 글자가 실제 사용자에게 편하게 읽히는지, 한글 자형과 anti-aliasing 품질
- 아이콘이 미학적으로 자연스럽고 의미가 맞는지
- 의도된 ellipsis/스크롤과 결함성 clipping의 구분
- 내용이 화면 밖에 존재하지만 스크롤로 접근 가능한지, 시각적 위계와 균형

픽셀은 “경계에 닿음”을 알려 줄 뿐 그것이 의도인지 판단하지 못하고, OCR도 작은 글자·아이콘을
놓칠 수 있다. 따라서 자동 검사는 28장의 누락·크기·명백한 캡처/절단 이상을 선별하는
보조 수단이다. 최종 L-M3 통과에는 사람이 100% 확대하여 기존 표의 overflow, clip,
깨진 icon, 읽기 불가 text 네 열을 28/28 확인해야 한다.

예상 소요 시간은 캡처 자동화 준비 4~6시간, 이미지 지표·manifest 3~5시간, 최종 실행
30~45분, 사람 검수 45~60분이다. 테마 반영, capture API, 화면 식별 중 하나라도 불안정하면
기존 28행 수동 캡처·검수로 되돌린다.

## 6. L-C2: Windows release 키보드 9종 입력

### 6.1 입력 방식과 상태 판정

`System.Windows.Forms.SendKeys.SendWait`는 간편하지만 현재 foreground/focus와 키보드
layout, 메시지 pump 타이밍에 의존하고 modifier up/down을 세밀하게 검증하기 어렵다.
`PostMessage(WM_KEYDOWN/WM_KEYUP)`는 특정 HWND에 보낼 수 있지만 실제 하드웨어 input
queue를 거치지 않아 Flutter/Windows가 실제 키 입력과 다르게 처리할 수 있으므로 기능
증적으로는 사용하지 않는다.

주 경로는 Win32 `SendInput`이다. modifier down → 본 키 down/up → modifier up을 한
배치로 보내고 반환된 input 수를 확인할 수 있으며 실제 foreground input 경로를 따른다.
SendKeys는 SendInput이 환경 정책으로 막힐 때의 보조 진단에만 쓰고, 그 결과만으로 통과
판정하지 않는다.

포커스 확보 순서는 MainWindowHandle 확인 → `ShowWindow(SW_RESTORE)` →
`SetForegroundWindow` → `GetForegroundWindow == handle` 확인 → client의 비동작 AppBar
영역 한 번 클릭 → `GetGUIThreadInfo`로 focus HWND가 앱 process에 속하는지 확인이다.
다른 앱이 foreground면 키를 보내지 않는다. 각 chord 뒤 모든 modifier key-up을 보장하고
짧은 안정화 polling을 한다.

### 6.2 승인 후 실행 순서

1. clean 격리 프로필, 고정 client 크기, 앱 process/window/focus를 준비하고 baseline
   캡처와 UIA tree를 저장한다.
2. Ctrl+1..5를 각각 SendInput으로 보내고, UIA가 있으면 `홈/퀘스트/목표/재무/더보기`
   SelectionItem의 IsSelected 또는 해당 화면 제목을 확인한다. UIA가 없으면 navigation
   rail/bar의 선택 indicator ROI와 화면별 대표 영역 image signature를 함께 비교한다.
3. Ctrl+2 후 Ctrl+F를 보내고 UIA Edit `퀘스트 검색`이 나타나며 keyboard focus를
   가졌는지 확인한다. UIA 미노출이면 AppBar ROI 변화와 caret의 반복 점멸 차분 캡처를
   보조로 쓰되 사람이 원본을 확인한다.
4. Escape 후 Edit가 tree에서 사라지는지와 퀘스트 목록 대표 영역이 유지되는지 확인한다.
5. Ctrl+N 후 `퀘스트 추가` 제목과 `제목` Edit 노출을 확인한다. 별도 복귀 Escape는 요구
   9종 통과 수에 포함하지 않는다.
6. 퀘스트 목록으로 돌아가 Ctrl+Tab을 세 번 보낸다. UIA가 있으면 `진행중 (n)` →
   `추천 (n)` → `완료 (n)` → `진행중 (n)`의 IsSelected 변화를 polling한다. 기존 문서의
   “예정” 표현과 실제 소스의 `추천`이 다르므로 실행 보고서에는 실제 UI 문자열 `추천`을
   쓰고 기준 문구 불일치를 별도 기록한다. UIA가 없으면 세 Tab label ROI의 selection
   색/indicator 위치를 검출한다.
7. 각 동작에 입력 반환값, foreground/focus, before/after screenshot, UIA 또는 ROI
   판정 근거를 연결한다. 9종 모두 확정될 때만 9/9로 기록한다.
8. modifier stuck 여부를 정리하고 앱을 정상 종료한다. 판정이 하나라도 모호하면 그 항목만
   자동 통과시키지 않고 기존 수동 체크리스트로 되돌린다.

예상 소요 시간은 SendInput·focus 제어 2~3시간, UIA/ROI 상태 판정 3~5시간, 최종 실행
15~20분이다. UIA 미노출 상태에서 ROI가 테마·크기에 따라 불안정하면 전체 9종을 사람이
직접 입력하고 관찰한다.

## 7. 승인 후 실행 시 공통 안전장치

- 제품 코드, test, runner, `pubspec.*`는 변경하지 않는다. 자동화 도구는 저장소 밖의
  고유한 임시 디렉터리에서 만들고, 결과만 사용자 승인 후 지정 증적 디렉터리로 복사한다.
- 기존 `test-results/`와 `tool/manual_evidence/`는 읽기 전용 잔여물로 취급한다.
- 시작 전과 종료 후 `human_status.exe` process 수를 기록한다. 자동화가 시작한 PID만
  정상 종료하고, 무관한 process는 종료하지 않는다.
- 사용자 Documents의 Hive를 직접 이동·삭제하지 않는다. 격리가 필요하면 먼저 현재
  `21:57:33` 중단 상태의 복구 결정을 사용자에게 받고, 복사·해시 검증·복구 로그와
  `try/finally`를 갖춘 별도 절차를 승인받는다.
- 임시 파일은 저장소 밖 ASCII-only 고유 경로(예:
  `%TEMP%\human_status_s_grade\<run-id>`)에 두고, run마다 새 디렉터리를 쓴다.
- 입력 직전마다 foreground HWND와 PID를 재검증한다. 일치하지 않으면 SendInput,
  mouse input, theme 변경을 중단한다.
- 좌표 입력은 client rectangle과 DPI를 기준으로 환산하고, 클릭 전후 screenshot으로
  화면 상태를 확인한다. 파괴적 메뉴(초기화, 삭제, 가져오기)는 자동화 대상에서 제외한다.
- Windows 테마를 변경하면 원래 값을 먼저 기록하고 `finally`에서 복원한다. 시스템 전체
  설정 변경이 승인되지 않으면 사람이 테마를 바꾸는 gate에서 자동화를 잠시 멈춘다.
- 강제 종료, 임시 파일 삭제, 사용자 데이터 복원은 정확한 PID/절대경로를 검증한 뒤에만
  수행한다. 실패 시 산출물과 로그를 보존하고 수동 체크리스트로 전환한다.
- 자동 지표는 “확정 통과”, “의심/사람 확인”, “실패”로 구분한다. 이미지 차이가 있다는
  사실만으로 기능 성공을 선언하지 않는다.

## 8. 승인 기준과 전체 예상 시간

1. 먼저 잔여 Hive 복구 방식을 사용자가 승인한다.
2. UIA probe 결과에 따라 UIA 우선 또는 Win32 입력+이미지/OCR 보조 경로를 선택한다.
3. L-P2와 L-C2는 고유 텍스트/선택 상태를 기계적으로 확정할 수 있을 때만 자동 통과를
   허용한다.
4. L-M3는 자동 캡처·선별이 성공해도 최종 사람 시각 검수를 유지한다.

전체 도구 준비와 안정화는 약 14~22시간, 최종 실행과 사람 검수는 약 2~3시간으로 예상한다.
어느 단계든 provider 미노출, focus 탈취, DPI/테마/capture 불안정, OCR 오판이 발생하면
범위를 확대하거나 제품 코드를 바꾸지 않고 `s_grade_remaining_work_plan.md`의 사람 손
체크리스트로 되돌아간다.
