# Human Status S급 달성 마스터 실행 플레이북

> 기준 시점: 2026-07-24(로컬 개인 사용 범위 재검증)
> 기준 환경: Windows 10.0.26200.8894, Flutter 3.44.6, Dart 3.12.2,
> Windows 데스크톱·Chrome·Edge 사용 가능. Android/iOS/macOS/Linux 실기기 없음.
> Phase 6 최초 구현은 Linux 컨테이너
> (Flutter 3.44.8, Dart 3.12.2, 한글 경로 문제 없음, 실기기·브라우저 없음)에서 수행했다 —
> 환경마다 도구 가용성이 다르므로 새 담당자는 자신의 실제 환경에서 재검증한다.  
> 목적: 새 에이전트가 이 문서 하나로 목표, 현황, 다음 작업, 검증 및 인수인계 방식을 파악하게 한다.

이 문서는 `docs/plans/roadmap_to_s_grade.md`, Phase 1~6 계획, `docs/RELEASE_CHECKLIST.md`,
`tool/check_release_readiness.dart`, `.github/workflows/`, `pubspec.yaml`의 현재 내용을
통합한 실행 기준이다. 계획과 실제 코드가 충돌하면 추측하지 말고 실제 코드와 테스트를
다시 조사한 뒤 해당 Phase 계획 및 이 문서를 함께 갱신한다.

## 0. 현재 목표 범위: 로컬 개인 사용 S급과 스토어 출시 S급의 분리

현재 사용자가 승인한 목표는 **개발자 본인이 Windows에서 로컬로 혼자 사용하는
앱의 S급**이다. 스토어 제출을 전제로 한 S급은 별도 후속 단계이며, 사용자가
명시적으로 착수를 지시할 때까지 보류한다.

### 0.1 로컬 개인 사용 기준 S급 판정

2026-07-24에 시작 SHA `a93b405b6f40a3944bb4cdb9de4e7cd6add8f502`를
Windows 실머신에서 재검증한 결과, **로컬 개인 사용 기준 S급을 선언할 수 있다.**

| 평가축 | 로컬 개인 사용 게이트 | 2026-07-24 증적과 판정 |
|---|---|---|
| 엔지니어링 완성도 | 정적 분석 0건, 전체 테스트 1,024개 이상 전부 통과, 접근성·단축키 회귀 없음 | 한글 checkout에서는 Flutter analysis server의 기존 경로 인코딩 오류(종료 255)를 재현했으나, 동일 SHA의 ASCII clone에서 `flutter analyze --no-pub` 0건. 원 checkout에서 `flutter test --no-pub` **1,024개 전부 통과**. 이전 기준선보다 감소 없음. **닫힘** |
| 프로덕션/운영 안정성(로컬 범위) | Windows release bundle이 빌드·실행되고, 로컬 데이터·백업·기본 off 관측성 계약이 자동 테스트로 보호됨 | 동일 SHA ASCII clone에서 `flutter build windows --release --no-pub` 성공, 생성된 `human_status.exe` 프로세스와 `Human Status` 창 실행 확인. 스토어 서명·실계정 관측성은 로컬 게이트가 아님. **닫힘** |
| 시장 매력도(로컬 범위) | 완료 즉시 피드백, 레벨업/업적 celebration, reduced motion·중복 완료 방지가 기존 테스트로 보호됨 | Phase 5 Part A 구현과 전체 1,024개 테스트 통과를 재확인. 공유 카드는 개인 로컬 사용에 필요하지 않으므로 제외. **닫힘** |
| 현대적 편의성 | Windows 단축키·접근성 semantics·Web compile이 자동 검증되고, Windows release가 실제 실행됨 | `test/accessibility`+`test/shortcuts` **28개 전부 통과**, Windows/Web release build 성공. Windows 앱 실제 실행 확인. 자동화 세션에서 Orca 런타임이 없고 Flutter UI Automation tree가 단일 `FLUTTERVIEW`만 노출되어 실제 키 입력 후 화면 변화를 판독하지 못했으므로 단축키와 Narrator 낭독은 **수동 확인 권장**으로 남긴다. 이는 구현/빌드/자동 회귀 게이트를 막는 결함은 아니다. **닫힘** |

Web은 `flutter build web --release --no-pub` 성공까지 확인했다. 실제 Chrome
인터랙션 스모크는 이번 세션에서 수행하지 않았으며 로컬 Windows 주 사용 목표의
필수 게이트로 두지 않는다. TalkBack/Android, VoiceOver/iOS·macOS, Orca/Linux는
해당 실기기/플랫폼 부재로 검증 불가다. 없는 환경을 검증했다고 간주하지 않는다.

### 0.2 스토어 출시 기준 S급: 명시적 지시 전까지 보류

다음 항목은 기존 계획과 체크리스트에 그대로 유지하되 지금 착수하지 않는다.

- 실제 Play/App Store 제출과 스토어 자산 준비
- Android keystore, `android/key.properties`, iOS 인증서/profile 및 코드 서명
- Sentry 실운영/테스트 DSN 발급·주입, 실제 네트워크·symbol/source map 검증
- `docs/privacy_policy.md`의 TODO를 실제 회사·법무·운영 정보로 채우는 작업
- Android/iPhone 및 6플랫폼 실기기/VM 행렬, Phase 4 cross-isolate 알림 액션 활성화
- release evidence index, artifact/signing identity 연결, owner 승인 절차

위 보류는 미완료 사실을 숨기기 위한 것이 아니라 목표 범위를 분리한 것이다.
따라서 **스토어 출시 기준 S급은 아직 선언하지 않는다.** 사용자의 별도 착수
지시가 오기 전에는 서명 파일·DSN·privacy TODO·스토어 자산을 수정하지 않는다.

## 1. S급 정의와 4개 평가축

S급은 기능 수가 많은 상태가 아니라 아래 네 축의 게이트를 모두 증적으로 닫은 상태다.
어느 한 축이라도 미완료이면 전체를 S급으로 선언하지 않는다.

| 평가축 | S급의 측정 가능한 기준 | 주 증적 |
|---|---|---|
| 엔지니어링 완성도 | `flutter analyze` 0건, 전체 `flutter test` 통과 및 직전 승인 기준선보다 테스트 수가 감소하지 않음(감소 시 사유 승인), 주요 화면의 책임 분할, Hive/public provider 계약 보존, 핵심 UI의 semantics·focus·2.0 이상 text scale·reduced motion·터치 영역·대비 검증, 데스크톱 단축키 회귀 없음 | CI `quality`, Phase 6 테스트/수동 QA, 커밋별 diff와 테스트 로그 |
| 프로덕션 출시 준비도 | `dart run tool/check_release_readiness.dart --json`이 실제 자격 증명 환경에서 종료 0/`"ready": true`, 6개 플랫폼 release build 및 플랫폼별 스모크, Android signed AAB/Play internal track, iOS signed archive/TestFlight 실기기, Sentry off 0건·opt-in 1건·opt-out 신규 0건, 개인정보 TODO 0, `docs/RELEASE_CHECKLIST.md`의 기존 27개 미완료 항목을 증적으로 닫음 | Phase 3 release evidence index, artifact hash, 서명 identity, 스토어 콘솔/실기기 결과 |
| 시장 매력도 | 퀘스트 완료 즉시 피드백, 레벨업/업적 celebration이 기존 보상·문구·순서를 보존하고 중복 완료 0건, 모션 감소에서도 의미 손실 없음, 실제 RC UI로 스토어 텍스트·아이콘·그래픽·스크린샷·등급·privacy 필드를 완성 | Phase 5 테스트/6플랫폼 QA, Play/App Store 자산 2인 검수 |
| 현대적 편의성 | 로컬 우선 원칙을 지키며 Windows/Linux 자동 백업, 알림·백업·가져오기 흐름이 회귀하지 않고, 접근성 및 Windows/macOS/Linux/Web 키보드 흐름이 명세대로 동작함. 알림 즉시 완료는 Android/iOS cross-isolate 검증 통과 시에만 제공 | Phase 2/4/6 증적, `RELEASE_CHECKLIST.md`, 실기기·VM·브라우저 행렬 |

공유 카드는 Phase 5 계획에서 의도적으로 제외되었다. **로컬 개인 사용 범위에서는
불필요하며 스토어 배포 시점에 재검토한다.** Linux 파일 공유 대체 UX, Web
다운로드 fallback, 개인정보 정책, `share_plus` 고정 버전과 6개 플랫폼 검증 환경이
확정되기 전에는 S급을 이유로 무리하게 넣지 않는다. 현재 S급 시장 매력도 게이트는
검증 가능한 마이크로 인터랙션과 정확한 스토어 자산을 기준으로 한다.

## 2. Phase 지도(전체 개요표)

| Phase | 상태 | 담당 계획 문서 | 한 줄 목표 | 선행 의존성 | 핵심 산출물 |
|---|---|---|---|---|---|
| 0 | 완료 | `docs/plans/roadmap_to_s_grade.md` | 검색 기능 diff를 확정·커밋 | 없음 | 커밋 `d969691` |
| 1 | 완료 | `docs/plans/phase1_observability_plan.md` | 명시적 opt-in Sentry와 전역 오류 처리·개인정보 기반 확보 | Phase 0 | Sentry service/provider, 설정 토글, `docs/privacy_policy.md`, 테스트; 커밋 `7413536` |
| 2 | 완료 | `docs/plans/phase2_auto_backup_plan.md` | Windows/Linux에 실패 폐쇄형 자동 백업 제공 | Phase 1 settings storage | 자동 백업 service/provider/UI/테스트; 커밋 `8dbefa9` |
| 3 | 커밋 1(저장소 gate) 완료, 나머지 외부 계정/실기기 차단 | `docs/plans/phase3_production_release_plan.md` | 서명·개인정보·실기기·스토어 자산·릴리즈 증적의 배포 블로커 해소 | Phase 1, 2, 4 결과 및 계정/실기기/서명 owner | RELEASE_CHECKLIST.md 드리프트 수정, privacy TODO readiness category; 커밋 `c62b787`. readiness `ready:true`, signed artifacts, 6플랫폼 증적, 스토어 제출 후보, release evidence index는 계정 소유자 착수 후 |
| 4 | 완료(기능 플래그 제한) | `docs/plans/phase4_notification_action_plan.md` | 알림에서 퀘스트를 정확히 한 번 완료하는 경로 구현 | Phase 1/2 storage 안정성 | typed payload, execution lock, dedupe/dispatcher/tests; 커밋 `7d4aca9`; 플래그는 `false` |
| 5 | Part A 완료 / Part B 보류 | `docs/plans/phase5_delight_polish_plan.md` | 외부 패키지 없이 완료·레벨업·업적의 접근 가능한 마이크로 인터랙션 강화 | Phase 4 완료 흐름 | `QuestCompletionButton`, `CelebrationDialogShell`, 회귀/모션/semantics 테스트; 커밋 `443c893`; 공유 카드(Part B)는 별도 Phase 보류 |
| 6 | Part A/B 완료, Part C 부분 완료, 6플랫폼 수동 QA 보류 | `docs/plans/phase6_engineering_polish_plan.md` | 동작 고정 후 파일 분할, 접근성, 데스크톱 단축키 마감 | Phase 5 UI 계약 확정 | 책임별 파일 15개, a11y harness/테스트/개선, typed shortcuts 4종; 커밋 `f3e6487`~`4266201`; 6플랫폼 QA 기록은 미실행 |

Phase 3/5/6 계획 문서와 마스터 플레이북·`tool/verify_phase.sh`는 커밋 `6efdedc`/`443c893`로
tracked 상태다. “계획이 존재함”과 “Phase가 완료됨”을 혼동하지 않는다. Phase 4의 홈 화면 위젯은 네이티브 Kotlin/Swift 및
Xcode/실기기 검증 제약으로 별도 Phase에 보류되었다.

## 3. 현재 상태 스냅샷

### 3.1 Git과 작업 중 상태

- 2026-07-24 재검증 시작 상태는 브랜치 `master`, 워킹 트리 clean, HEAD
  `a93b405b6f40a3944bb4cdb9de4e7cd6add8f502`였다.
- Windows 실머신의 Flutter 3.44.6/Dart 3.12.2를 사용했다. 원 checkout의 한글
  경로에서는 analysis server 255 오류를 재현했으므로 같은 SHA를
  `C:\Users\rlaeh\AppData\Local\Temp\human_status_verify_a93b405`에 clone해
  analyze와 release build를 검증했다.
- Phase 6 Part A/B/C 구현 이력은 커밋 `f3e6487`부터 `4266201`까지이며,
  후속 차트 semantics와 Ctrl+Tab 보완은 `00c3863`/`01ab432`다.

### 3.2 기록된 품질 기준선

| 기록 지점 | 정적 분석 | 테스트 |
|---|---:|---:|
| Phase 1 완료 | 0건 | 834개 통과 |
| Phase 2 완료 | 0건 | 909개 통과 |
| Phase 4 완료 | 0건 | 971개 통과 |
| Phase 3 계획의 현재 작업 트리 실측 기록 | 한글 경로의 analysis server `FormatException`으로 종료 255 | 985개 통과 |
| Phase 5 Part A 완료 | 0건 | 985개 통과 |
| Phase 6 Part A/B/C 완료(이 문서 작성 시점) | 0건 | 1,014개 중 1,006 통과·6 스킵·2 실패 |
| 2026-07-24 Windows 재검증(`a93b405`) | 동일 SHA ASCII clone에서 0건 | **1,024개 전부 통과** |

따라서 최신 **기록 기준선은 1,024개 전부 통과**다. 과거 Linux 컨테이너의
6 스킵은 PowerShell 부재, 2 실패는 file backend advisory lock 환경 차이였으며
이번 Windows 재검증에서는 모두 통과했다. Phase 3과 Phase 5 Part B는 스토어
출시 범위로 보류한다. Phase 6의 구현·자동 테스트·Windows/Web build smoke는
완료했고, 실제 Narrator 낭독과 키보드 손 조작 및 다른 플랫폼 수동 QA만
권장/외부 검증 항목으로 남는다.

### 3.3 배포 전 미해결 TODO 전수

#### Phase 문서·로드맵의 명시적 TODO

| 출처 | 미해결 항목 |
|---|---|
| Phase 1/roadmap | 실제 Sentry 계정과 운영/테스트 DSN, 개인정보처리방침 문의처·보관기간 등 실제 값, Android/iOS/macOS/Linux 실기기 빌드, Windows Release 네이티브 재검증 |
| Phase 2/roadmap | Windows/Linux 실기기, Flatpak/Snap 패키징, macOS security-scoped bookmark 별도 Phase 및 재실행 검증 |
| Phase 3 | 운영자 승인으로 `docs/privacy_policy.md`의 11개 `[TODO: ...]`와 “초안” 제거, 공개 HTTPS URL·앱 내 문서·콘솔 선언 일치 |
| Phase 4/roadmap | Android/iOS cross-isolate Hive 동시성, 중복 탭·stale payload·종료 상태·저전력 matrix 통과 전 `kQuestCompletionNotificationActionEnabled`를 `true`로 바꾸지 않음 |
| Phase 5 | 공유 카드 Part B 보류: 카드 정책/aspect ratio, Linux 대체 UX, Web fallback, `share_plus` 감사, 플랫폼 행렬, 임시 PNG/개인정보 정책이 진입 조건 |
| Phase 6 | 자동화 범위(파일 분할·접근성·단축키 구현+테스트)는 완료. 2026-07-24 재검토로 나머지 차트(NetWorthChart/통계 XP/리포트 XP) semantics 요약과 Ctrl+Tab 퀘스트 탭 순환(네이티브 데스크톱 한정, Web은 브라우저가 이벤트를 페이지로 넘기지 않아 실제로 불가능)까지 마저 구현했다(phase6 계획서 9.1절). 남은 것: TalkBack/VoiceOver/Narrator/macOS VoiceOver/Orca/Web screen reader 6플랫폼 수동 QA, Windows/macOS 실제 키보드 확인(둘 다 실기기 부재로 차단), IndexedStack 탭의 route 명명(실기기 검증 없이 추가하면 오히려 혼란 위험 판단), 포커스된 퀘스트 완료(Ctrl+Enter — QuestCard에 없는 "포커스된 카드" 개념을 새로 설계해야 하는 별도 기능, 재검토 후에도 의도적으로 이번 범위에서 제외) |

`docs/privacy_policy.md`의 11개 실제 값은 운영자/문의 채널, 시행일, 변경 고지 방법,
Sentry 운영 법인, 처리 region, Sentry 정책 링크, 이벤트 보관 기간, 프로젝트
삭제/이전 정책, 이벤트 조기 삭제 요청 절차, 아동 대상 여부 관련 최종 문구,
재동의 조건이다.

#### `docs/RELEASE_CHECKLIST.md`의 기존 미완료 27개

| 묶음 | 전수 목록 |
|---|---|
| Windows 7개 | 전체 bundle에서 `human_status.exe` 실행; 브랜딩 아이콘; 좁은/넓은 창 레이아웃; 퀘스트·목표·뱅크샐러드 가져오기; 백업 내보내기/가져오기; 알림 설정 화면; 익명 크래시 리포팅 기본 off |
| Web 5개 | 정적 서버에서 최신 브라우저 실행; 새로고침 데이터 유지; Claude API 키 보호 수준 경고; 좁은/넓은 반응형; 익명 크래시 리포팅 기본 off |
| Sentry/privacy 8개 | 새 설치·업데이트·백업 가져오기 후 기본 off; off 네트워크 0건; opt-in 이벤트 도달; opt-out 후 신규 전송 0건; symbol/source map; privacy policy/retention/region 확정; DSN 환경 분리; Windows/Linux 네이티브 crash 지원 차이 고지 |
| 서명 운영 3개 | 비밀번호를 코드/YAML 평문에 두지 않음; iOS 인증서/profile 저장소 밖 관리; keystore/인증서 안전 백업 |
| 실기기 4개 | Android signed AAB 설치·알림·백업·뱅크샐러드 가져오기; iPhone/TestFlight 알림 권한·Keychain API key·백업·가져오기; 양 플랫폼 저전력/배터리 최적화 알림; Phase 4 cross-isolate 알림 액션 |

Phase 3의 Play 17개 및 App Store 15개 자산/콘솔 체크리스트도 제출 전에 모두 닫는다.
각 항목은 `docs/plans/phase3_production_release_plan.md` 6절을 원문 기준으로 사용하며,
실제 플래그가 꺼진 기능은 설명·스크린샷·릴리즈 노트에서 제외한다.

## 4. 에이전트 인수인계 프로토콜(핵심)

### 4.1 작업 시작 전 체크리스트

- [ ] `git status --short --branch`와 `git diff --stat`으로 브랜치·dirty files·선행
      작업을 확인한다.
- [ ] 이 플레이북과 담당 Phase 계획 문서를 처음부터 끝까지 읽는다.
- [ ] 실행 중인 Claude Code/Codex/Hermes/기타 에이전트가 없고, 이전 프로세스가
      완전히 종료되었음을 확인한다.
- [ ] dirty file의 소유자·목적을 확인한다. 남의 변경을 정리, 덮어쓰기, revert,
      amend하지 않는다.
- [ ] 해당 Phase의 진입 게이트와 순차 커밋 중 이번 작업 단위를 선언한다.
- [ ] 시작 SHA, Flutter/Dart 버전, 환경 제약(Windows·한글 경로·실기기 없음)을
      작업 로그에 남긴다.

### 4.2 단일 작성자 원칙

**한 시점에는 한 에이전트만 파일을 쓴다.** 계획·구현·검증 역할은 나눌 수 있지만
동시에 수정하지 않는다. roadmap의 운영 방식대로 이전 프로세스가 완전히 종료된 뒤
다음 에이전트를 시작한다. 읽기 전용 리뷰어도 수정 제안을 직접 적용하지 않고
Blocker/Should-fix/Nit와 근거만 남긴다.

### 4.3 작업 크기와 커밋

- 한 번에 한 Phase만 수행한다.
- Phase 내부에서는 해당 문서의 “순차 커밋 제안” 순서를 따른다.
- 파일 이동과 동작 변경, 안전 gate와 기능 활성화, 증적과 구현을 한 커밋에 섞지 않는다.
- 각 커밋 전에 관련 테스트와 `flutter analyze`를 통과시킨다.
- Phase 종료 시 전체 `flutter test`, 가능한 build smoke, 수동 게이트를 수행한다.
- 완료 후 이 문서의 Phase 표·Git 상태·기준선·TODO를 갱신하고 커밋한다.

### 4.4 교차검증 흐름

1. **계획:** Codex가 실제 저장소를 읽고 읽기 전용 상세 계획을 작성한다.
2. **계획 검토:** Hermes가 계획의 범위, 위험, 저장 계약, 검증 가능성을 검토한다.
3. **구현:** Claude Code가 한 Phase의 순차 커밋을 구현하고 analyze/test 수치를 보고한다.
4. **검증:** Hermes가 `git diff`와 검증 명령을 직접 재실행하고 결과를 비교한다.
5. **독립 리뷰:** Codex가 수정 없이 Blocker/Should-fix/Nit로 리뷰하고 테스트를 재실행한다.
6. **재수정:** 문제가 있으면 Claude Code만 다시 쓰고 Hermes가 최종 재검증한다.
7. **종료:** `flutter analyze` 0건, 전체 테스트 수, build/manual 결과, 남은 제한을
   보고하고 플레이북 갱신 및 커밋 후 프로세스를 종료한다.

인수인계 메시지는 최소한 `Phase/순차 커밋 번호`, 시작·종료 SHA, 변경 파일,
analyze 결과, 테스트 통과 수, 실행한 build와 결과, 미실행 사유, Blocker,
다음 정확한 작업, rollback 단위를 포함한다.

## 5. Phase별 진입 게이트 / 완료 게이트(Definition of Ready / Done)

### Phase 3 — 프로덕션 배포 블로커

**Definition of Ready**

- Phase 1/2/4 코드와 기준 테스트가 확정되고 Phase 5 dirty worktree와 쓰기 충돌이 없다.
- 영구 ID `io.github.underkim.humanstatus`와 `pubspec.yaml` 버전 현황을 재확인한다.
- 계정 소유자, Android keystore owner, Apple signing owner, privacy 승인 owner,
  각 플랫폼 Go/No-Go owner가 정해져 있다.
- Android/iPhone 실기기, macOS/Xcode, clean Windows/Linux VM, HTTPS Web 검증 환경
  또는 명시적 외부 gate 일정이 있다.
- 시크릿은 저장소 밖에서 주입하며 RC는 ASCII 경로 또는 CI 동일 SHA로 검증한다.

**Definition of Done**

- ASCII 경로/CI에서 analyze 종료 0, 전체 테스트 통과 및 985 기준선 감소 없음(감소 승인 예외).
- readiness JSON이 실제 release 자격 증명으로 `"ready": true`, 종료 0.
- 영구 ID·버전·스토어 레코드 일치, tracked/log/artifact 시크릿 노출 0.
- privacy TODO/초안 0, 공개 URL·앱 내 문서·스토어 privacy 선언 일치.
- 기존 release checklist 27개를 증적과 함께 닫는다.
- Android signed AAB/internal track와 iOS signed archive/TestFlight 실기기,
  macOS/Linux/Windows/Web release·스모크, 이전 백업 복원을 통과한다.
- Sentry off 0/opt-in 1/opt-out 0, symbol/source map과 플랫폼 차이 고지를 확인한다.
- 알림 액션 실기기 matrix가 통과한 경우에만 플래그를 켠다. 실패하면 false와 자산
  미노출을 증명한다.
- 동일 RC의 스토어 자산, artifact hash/SHA/version/signing identity, owner 승인을
  release evidence index에 연결한다. 계정 소유자의 명시 승인 전 production 제출은 없다.

### Phase 5 — 감성적 훅

**Definition of Ready**

- 현재 dirty files의 단일 소유 에이전트가 확인되고 다른 작성 프로세스가 없다.
- Phase 4의 `completeQuest()` 결과·중복 방지·dialog 공개 함수 계약을 기준 테스트로 고정한다.
- 외부 animation/share 패키지, Hive schema, provider 타입, 보상 계산을 바꾸지 않는
  Part A 범위에 동의한다.
- 공유 카드 Part B는 진입 조건이 별도 충족될 때까지 코드/UI에서 제외한다.

**Definition of Done**

- `QuestCompletionButton`을 세 완료 진입점에 연결하고 탭 즉시 피드백과 중복 완료 0건을 검증한다.
- `CelebrationDialogShell`, 레벨업/업적 dialog가 기존 텍스트·호출 순서를 유지한다.
- `disableAnimations`에서 의미 손실 없이 모션이 제거되고 semantics, overflow,
  dispose, frame 진행 회귀 테스트가 통과한다.
- 외부 패키지/animation asset 및 Part B 코드/UI가 추가되지 않는다.
- `flutter analyze` 0건, 관련 테스트와 전체 `flutter test` 통과 수를 보고한다.
- 가능한 6개 플랫폼 build smoke와 수동 애니메이션 QA 결과 또는 환경상 미실행
  항목을 명시한다.

### Phase 6 — 엔지니어링 마감

**Definition of Ready**

- Phase 5 UI·semantics·reduced-motion 계약이 커밋되고 전체 테스트가 녹색이다.
- finance/settings/bootstrap 행위를 characterisation test로 먼저 고정할 수 있다.
- 작업 순서를 동작 고정 → 순수 파일 분할 → 접근성 → 단축키 → 6플랫폼 검증으로
  유지하고, Hive schema/provider·service public 계약을 변경하지 않는다.

**Definition of Done**

- `finance_screen.dart`, `settings_screen.dart`는 호환 진입점/조합 역할만 하고 신규
  파일별 책임을 한 문장으로 설명할 수 있다.
- 분할 전후 공개 import·행위·전체 테스트가 동일하게 통과한다.
- 핵심 route/tab/card/dialog/비동기 상태 semantics, light/dark target·대비,
  2.0 이상 text scale, Web 200% zoom, focus 복귀, reduced motion을 통과한다.
- Windows/macOS/Linux/Web 단축키가 명세대로 동작하고 Android/iOS에서는 무해하다.
- TalkBack, VoiceOver, Narrator, macOS VoiceOver, Orca, Web screen reader 결과를 기록한다.
- `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`,
  전체 `flutter test`, 가능한 6개 플랫폼 build smoke가 모두 통과한다.

## 6. 표준 검증 명령

명령은 저장소 루트에서 실행한다. 현재 한글 경로에서 analysis/build 도구가 실패한
기록이 있으므로 코드 결함으로 단정하지 말고 ASCII 경로 또는 GitHub Actions의 같은
commit SHA에서 재검증한다. `--no-pub`은 먼저 `flutter pub get`을 수행한 환경에서 쓴다.

| 명령 | 보장하는 것 / 한계 |
|---|---|
| `flutter pub get` | `pubspec.yaml`/lockfile의 의존성을 해석한다. 품질이나 런타임은 보장하지 않는다. |
| `dart format --output=none --set-exit-if-changed lib test` | Phase 6 대상 Dart 파일의 포맷 드리프트가 없음을 보장한다. |
| `flutter analyze` 또는 CI의 `flutter analyze --no-pub` | Dart/Flutter 정적 진단 0건을 요구한다. 네이티브 런타임과 실기기는 보장하지 않는다. |
| `flutter test` 또는 CI의 `flutter test --no-pub` | 전체 widget/unit 회귀를 검증한다. 테스트 수를 반드시 함께 기록한다. |
| `dart run tool/check_release_readiness.dart` | 실제 플랫폼 프로젝트의 placeholder ID, 버전 형식, Android release signing 자격 증명/keystore를 읽기 전용으로 검사한다. 빌드·스토어·실기기는 보장하지 않는다. |
| `dart run tool/check_release_readiness.dart --json` | 같은 검사를 자동화 가능한 JSON/종료 코드로 제공한다. RC는 `"ready": true`와 종료 0이어야 한다. |
| `flutter build web --release --no-pub` | Web release 컴파일 가능성을 검증한다. HTTPS 배포/브라우저 스모크는 별도다. |
| `flutter build windows --release --no-pub` | Windows 전체 release bundle을 만든다. clean VM 7항목 스모크는 별도다. |
| `flutter build linux --release --no-pub` | Linux release 컴파일을 검증한다. clean VM 및 Flatpak/Snap 권한은 별도다. |
| `flutter build macos --release --no-pub` | macOS release compile을 검증한다. signing/runtime/bookmark 검증은 별도다. |
| `flutter build appbundle --release --no-pub` | 서명된 Android AAB 후보를 만든다. 실제 기기/internal track 및 fingerprint 대조가 필요하다. |
| `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab` | AAB 인증서 fingerprint를 출력해 upload certificate와 대조하게 한다. |
| `flutter build ios --release --no-codesign --no-pub` | iOS release compile smoke만 보장한다. signed archive 성공으로 보고하면 안 된다. |
| `flutter build ipa --release --no-pub --export-options-plist=<승인된 ExportOptions.plist>` | Apple signing 환경에서 IPA를 만든다. 실제 profile 경로/파일은 owner가 제공한 값을 쓴다. |
| `flutter build apk --debug --no-pub` | 현재 CI의 Android debug compile smoke다. release signing/스토어 준비를 보장하지 않는다. |

`.github/workflows/ci.yml`은 Ubuntu에서 analyze/test/Web release/Android debug, Windows에서
Windows release smoke를 수행한다. `.github/workflows/release-artifacts.yml`은 tag `v*`
또는 수동 실행으로 Windows x64와 Web zip 및 SHA-256을 14일 artifact로 만들 뿐,
GitHub Release 생성이나 배포는 하지 않는다.

## 7. 도구·스킬 인벤토리

| 도구 | 현재 상태 | 용도 | 호출 예시 |
|---|---|---|---|
| Codex CLI | 운영 절차에 명시, 저장소 전용 wrapper 없음 | Phase 계획, 실제 diff 독립 리뷰, Blocker/Should-fix/Nit 분류. 리뷰 단계는 읽기 전용 | 저장소 루트에서 Codex 세션을 열고 “`docs/plans/phase6_engineering_polish_plan.md`와 실제 diff를 읽기 전용 리뷰”라고 위임 |
| Claude Code | 운영 절차에 명시, 저장소 전용 wrapper 없음 | 한 Phase 순차 구현, analyze/test 직접 실행 및 수치 보고 | 저장소 루트에서 Claude Code 세션에 Phase 문서와 순차 커밋 번호를 명시 |
| Flutter/Dart | 설치 확인: Flutter 3.44.6, Dart 3.12.2 | 의존성, 포맷, 분석, 테스트, 6플랫폼 build | `flutter analyze`, `flutter test`, 위 6절 build 명령 |
| `tool/check_release_readiness.dart` | 있음 | placeholder application/bundle ID, 버전, Android release signing을 fail-closed로 읽기 검사 | `dart run tool/check_release_readiness.dart --json` |
| `tool/verify_phase.sh` | **있음(이 세션에서 추가)** | Phase 진입/완료 게이트를 한 번에 점검: 툴체인·git·계획 문서·analyze·test·readiness·Phase별 안전검사(알림 플래그/시크릿/대형 파일). 아무 파일도 수정하지 않는 읽기 전용. 한글 경로 crash를 코드 오류와 구분해 경고 처리 | `bash tool/verify_phase.sh 3` / `bash tool/verify_phase.sh --quick` |
| Hermes `human-status-s-grade` skill | **있음(이 세션에서 추가)** | 어떤 에이전트든 작업 인수인계 시 로드. 저장소 좌표·5단계 인수인계 프로토콜·검증 게이트·절대 금지사항·Phase 빠른 참조 제공. 최신 상태는 이 플레이북을 신뢰 | `skill_view(name='human-status-s-grade')` 또는 `~/AppData/Local/hermes/skills/human-status-s-grade/SKILL.md` |
| GitHub Actions | 있음 | 깨끗한 ASCII runner에서 동일 SHA 품질·빌드 재현, Windows/Web artifact 생성 | `CI`, `Release artifacts` workflow 수동 실행 또는 tag `v*` |

### 남은 도구 후보(선택)

필요성이 확인되면 별도 Phase/커밋으로 만든다. `tool/verify_phase.sh`(공통 게이트 wrapper)와
`human-status-s-grade` 스킬은 이미 존재하므로 아래에서 제외했다.

1. release evidence index 생성기: commit SHA, Flutter 버전, 테스트 수, artifact hash,
   signing fingerprint와 외부 증적 링크를 한 manifest로 묶되 시크릿을 redaction.
2. privacy drift checker: `docs/privacy_policy.md`의 `[TODO`/“초안”, 공개 URL 상태,
   앱 bundle 문서 일치를 검사.
3. store asset validator: 이미지 크기/alpha/파일명/민감정보 수동 검수를 보조.
4. Windows 대응 `verify_phase.ps1`: git-bash가 없는 환경을 위한 PowerShell 포팅.

## 8. 위험 신호와 절대 금지사항

| 절대 금지 / 위험 신호 | 이유와 안전 조치 |
|---|---|
| 실기기 gate 전 `kQuestCompletionNotificationActionEnabled = true` | 두 Flutter engine/isolate의 동일 Hive 파일 동시 쓰기로 XP·업적·목표 보상이 중복될 수 있다. Android/iOS matrix 전까지 `false`. |
| keystore, `android/key.properties`, 인증서, profile, 비밀번호, DSN, token 커밋 또는 로그 출력 | 자격 증명 유출 및 공급망 위험. 저장소 밖/Keychain/비밀번호 관리자/GitHub secret에서 주입하고 artifact도 검사한다. |
| Hive schema, typeId, field index, box lifecycle, secure migration 임의 변경 | 기존 사용자 데이터·백업 호환성을 깨뜨린다. Phase 5/6에서는 schema 변경 자체가 범위 밖이다. |
| `UserProfile`에 동의/일시 UI 상태를 편의상 추가 | adapter·copy·backup 호환성 위험. 설정은 기존 `settingsBox`, 일시 모션은 widget local state를 사용한다. |
| Sentry를 동의 전에 초기화하거나 PII/tracing/replay/screenshot/local variables를 켬 | local-first 및 명시적 opt-in 계약 위반. 기본 off, `sendDefaultPii=false`, redaction, error-only를 유지한다. |
| Claude API key, 금융·퀘스트·백업 원문을 breadcrumb/context/share card에 포함 | 민감정보 유출. synthetic redaction 및 스토어 screenshot 검수를 통과해야 한다. |
| release build 실패를 debug/no-codesign 성공으로 대체 보고 | 서명·배포 가능성을 증명하지 못한다. 각 결과를 별도 표기한다. |
| 한글 경로 도구 실패를 테스트/분석 성공으로 간주하거나 코드 결함으로 단정 | Phase 3에 analyze 255, Windows/AAB path failure 기록이 있다. ASCII 경로/CI 동일 SHA로 재검증한다. |
| 자동 백업을 Android/iOS/Web/macOS에 검증 없이 노출 | Phase 2 지원 범위는 Windows/Linux다. macOS는 security-scoped bookmark 재실행 검증 전 flag off. |
| Linux 파일 공유 미지원인데 공유 카드 6플랫폼 지원 선언 | Phase 5 Part B는 별도 제품·기술 결정 전 보류다. |
| 파일 이동과 행위 변경을 같은 커밋에 혼합 | Phase 6 회귀 원인과 rollback 단위를 잃는다. characterisation test 후 순수 이동한다. |
| printable single-key shortcut, text field/IME·브라우저 예약키 무시 | 입력 손실과 Web 충돌 위험. typed intent, editing/modal/platform 조건을 둔다. |
| 다른 에이전트의 dirty files 수정·정리·revert | 동시 수정과 작업 손실 위험. 단일 작성자와 소유권 확인이 먼저다. |
| 실기기·스토어·법무 증적 없이 Phase 3 또는 S급 완료 선언 | 저장소 준비와 프로덕션 출시 완료는 다르다. 외부 gate가 하나라도 비면 출시 완료가 아니다. |

## 9. S급 달성까지 남은 전체 경로(요약)

권장 주 경로는 **Phase 6 잔여 수동 QA → Phase 3 RC/출시 게이트 → (여유 있으면) Phase 5
Part B**다. Phase 6의 구현·자동 테스트 범위(Part A/B/C)는 완료됐고, 남은 것은 실기기·
브라우저에서만 확인 가능한 항목이다. Phase 3의 계정·기기·자산 준비는 파일을 쓰지
않는 범위에서 병렬 준비할 수 있지만, 저장소 수정은 항상 단일 작성자만 수행한다.

| 순서 | 작업 | 병렬 가능 여부 | 종료 신호 |
|---:|---|---|---|
| 1 | Phase 6 잔여: TalkBack/VoiceOver/Narrator/macOS VoiceOver/Orca/Web screen reader 6플랫폼 수동 QA, Windows/macOS 키보드 실기기 확인. (Ctrl+Tab과 나머지 차트 semantics는 2026-07-24 재검토로 code-only 범위에서 이미 구현·완료됨 — phase6 계획서 9.1절) | 플랫폼별 수동 QA는 서로 다른 기기/브라우저에서 병렬 가능 | 플랫폼별 QA 기록 또는 명시적 미실행 사유, 필요 시 후속 커밋 |
| 2 | Phase 3 저장소 gate: (완료) 체크리스트 드리프트·privacy readiness category → (남음) 실제 Android keystore/Sentry DSN 주입, privacy 실제 값, 버전·ID·secret audit | privacy/계정 owner의 실제 값 승인은 병렬 가능; 파일 반영은 단일 작성자 | readiness ready, TODO/초안 0, analyze/test 녹색 |
| 3 | 6플랫폼 RC build·스모크, 이전 백업 복원, Sentry 실제 네트워크 검증 | 서로 다른 외부 플랫폼 실행은 같은 immutable SHA에서 병렬 가능 | artifact hash와 플랫폼별 evidence |
| 4 | Android/iOS signed build·실기기 및 Phase 4 cross-isolate/저전력 matrix | Android/iOS 실험은 같은 RC에서 병렬 가능 | 통과 시에만 flag 단일 커밋; 실패 시 false·자산 제외 |
| 5 | Play/App Store 텍스트·그래픽·privacy·등급·심사 필드 freeze, 동일 RC screenshot | 두 스토어 준비는 병렬 가능 | validator required field 0, 2인 검수 |
| 6 | release evidence index와 최종 독립 리뷰, owner Go/No-Go | 리뷰는 읽기 전용 병렬 가능, 수정은 단일 작성자 | SHA/version/hash/signing identity 일치 및 모든 owner 승인 |
| 7 | 계정 소유자 승인 후 production rollout/App Review 제출 | 승인 전 불가 | 제출 기록과 rollback owner 확정 |

Phase 1의 Sentry/개인정보/플랫폼 TODO, Phase 2의 Windows/Linux·Flatpak/Snap 및 macOS
TODO, Phase 4의 알림 flag gate는 Phase 3에서 통합해 닫는다. 홈 화면 위젯과 Phase 5
공유 카드는 현재 S급 주 경로의 몰래 끼워 넣는 범위가 아니다. 별도 진입 조건과
검증 환경이 확보되면 독립 Phase로 계획→구현→검증→리뷰를 반복한다.
