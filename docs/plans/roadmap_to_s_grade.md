# S급 달성 로드맵

목표: 4개 평가축(엔지니어링 완성도 / 프로덕션 출시 준비도 / 시장 매력도 / 현대적 편의성)을
모두 S급 수준으로 끌어올린다.

> 새로 투입되는 에이전트는 먼저 [`docs/plans/S_GRADE_MASTER_PLAYBOOK.md`](S_GRADE_MASTER_PLAYBOOK.md)를
> 읽는다. 목표·현황·다음 작업·검증·인수인계 프로토콜이 한 문서에 정리되어 있다.
> 표준 게이트 점검은 `bash tool/verify_phase.sh <phase>`, 작업 가이드는 Hermes 스킬
> `human-status-s-grade`를 사용한다.

## 진행 방식 (모든 Phase 공통)

1. Codex에게 해당 Phase 상세 구현 계획 위임 (읽기 전용, 코드 수정 금지)
2. Hermes가 계획 문서를 직접 읽고 검토
3. Claude Code에게 구현 위임 (dart analyze / flutter test 직접 실행 및 결과 수치 보고 의무화)
4. Hermes가 git diff와 테스트 결과를 직접 재실행해 교차검증
5. Codex에게 독립 리뷰 위임 (코드 수정 금지, Blocker/Should-fix/Nit 분류, 직접 테스트 재실행)
6. 문제 발견 시 Claude Code에게 재수정 위임 → Hermes 최종 재검증
7. Phase 완료 시 커밋 + 진행 상황 이 문서에 기록

동시 수정 방지: 한 시점에는 한 에이전트만 파일을 쓴다. 이전 프로세스가
`process(action="wait")`로 완전히 종료된 것을 확인한 뒤에만 다음 에이전트를 기동한다.

## Phase 상태

- [x] Phase 0 — 검색 기능 diff 커밋 (완료: 커밋 d969691, 2026-07-23)
- [x] Phase 1 — 관측성 기반 확보 (완료: 커밋 7413536, 2026-07-23)
  - Codex 리뷰 3회 반복(반려→부분해소→최종 승인). dart analyze 0건, flutter test 834개 통과
  - [TODO] 배포 전: 실제 Sentry 계정/DSN, 개인정보처리방침 문의처/보관기간 확정,
    Android/iOS/macOS/Linux 실기기 빌드 검증, Windows Release 네이티브 빌드 재검증
- [x] Phase 2 — 자동 백업 (완료: 커밋 8dbefa9, 2026-07-23)
  - Windows/Linux만 지원(현실적 범위 조정), Android/iOS/macOS/Web은 기존 수동 백업 유지
  - Claude Code 자체 검증 미흡으로 재작업 2회, Codex 리뷰 1회(조건부통과→Should-fix 2건→승인)
  - dart analyze 0건, flutter test 909개 통과
  - [TODO] Windows/Linux 실기기 검증, Flatpak/Snap 패키징 검증, macOS는 별도 Phase
- [~] Phase 3 — 프로덕션 배포 블로커 해소 (서명, 실기기 검증, 스토어 자산)
  - 상세 계획: [`docs/plans/phase3_production_release_plan.md`](phase3_production_release_plan.md)
  - 커밋 1(저장소만으로 가능한 범위) 완료: `RELEASE_CHECKLIST.md`의 존재하지
    않는 로컬 keystore 단정 문구 제거, 27개 항목 owner/evidence/date/SHA
    기록 컨벤션 추가, `tool/release_readiness/checker.dart`에
    `docs/privacy_policy.md`의 TODO/초안 표시를 검사하는 privacy category
    추가(커밋 c62b787)
  - [차단] 나머지 전부(Android keystore/Play 계정, Apple 개발자 계정·
    macOS·iPhone, 실제 Sentry 계정, 개인정보처리방침 실제 값과 공개
    HTTPS 호스팅, Windows/macOS/Linux 실기기·VM 스모크, 스토어 제출)는
    계정 소유권·실기기·업무상 결정이 필요해 에이전트가 대신할 수 없다.
    S_GRADE_MASTER_PLAYBOOK.md 3.3절과 phase3 계획서 0.2절 참고
- [x] Phase 4 — 알림 액션 완료 + 홈 화면 위젯 (완료: 커밋 7d4aca9, 2026-07-23)
  - 알림 액션으로 퀘스트 즉시 완료만 구현. 홈 화면 위젯(네이티브 Kotlin/Swift)은
    실기기/Xcode 빌드 검증 불가로 범위에서 제외, 별도 Phase로 보류
  - Codex 리뷰 1회(반려→Blocker 3건→최종 승인). dart analyze 0건, flutter test 971개 통과
  - ⚠️ [TODO] 배포 전 필수: kQuestCompletionNotificationActionEnabled(기본값 false)는
    Android/iOS 실기기 cross-isolate Hive 동시성 검증을 통과하기 전까지 true로
    바꾸면 안 됨(XP 중복 지급 위험). RELEASE_CHECKLIST.md에 게이트 문서화됨
- [~] Phase 5 — 감성적 훅 강화 (마이크로 애니메이션, 공유 카드)
  - 상세 계획: [`docs/plans/phase5_delight_polish_plan.md`](phase5_delight_polish_plan.md)
  - Part A(마이크로 애니메이션) 완료: 커밋 443c893. QuestCompletionButton,
    CelebrationDialogShell, 레벨업/업적 다이얼로그 애니메이션, flutter test 985개 통과
  - [보류] Part B(완료/레벨업 공유 카드)는 share_plus 등 의존성·플랫폼 검증 필요로
    별도 Phase. 진입 조건은 계획 문서 3.4절 참조
- [~] Phase 6 — 엔지니어링 마감 (파일 분할, 접근성, 데스크톱 단축키)
  - 상세 계획: [`docs/plans/phase6_engineering_polish_plan.md`](phase6_engineering_polish_plan.md)
  - Part A(파일 분할) 완료: `finance_screen.dart`(1,386줄)를 `lib/screens/finance/` 7개
    파일로, `settings_screen.dart`(1,320줄)를 `lib/screens/settings/` 6개 섹션으로,
    `main.dart`(505줄)를 `lib/app/` 3개 파일로, wizard를
    `lib/screens/financial_planning/` 5개 단계 위젯으로 분할(공개 진입점·동작 불변,
    커밋 f3e6487/b364df5/0873636/a8d901f)
  - Part B(접근성) 완료: 접근성 테스트 하네스, IndexedStack semantics 검증,
    text-scale/tap-target/contrast 가드, 아이콘 tooltip, 차트 semantics 요약,
    검색 autofocus·다이얼로그 키보드 조작성 확인(커밋 672e383/2f57f47/f8ee255).
    자동 검사 중 다크 테마 FilledButton 대비 미달(2.53:1)을 실제로 발견해
    onPrimary 토큰을 고쳤다
  - Part C(데스크톱 단축키) 부분 완료: 탭 전환(Ctrl/Cmd+1..5), 퀘스트 검색
    (Ctrl/Cmd+F), 새 퀘스트(Ctrl/Cmd+N), 검색 닫기(Escape)를 구현하고
    Windows/macOS/Android 분기까지 테스트로 확인(커밋 4266201). Ctrl+Tab 탭
    순환과 포커스된 퀘스트 완료(Ctrl+Enter)는 계획서가 허용한 대로 이번
    범위에서 제외
  - [보류] TalkBack/VoiceOver/Narrator/macOS VoiceOver/Orca/Web screen reader
    6플랫폼 수동 QA, Windows/macOS 키보드 실기기 확인, 라우트 명명
    (IndexedStack 탭의 namesRoute)은 실기기 없이는 검증 신뢰도가 낮아 미실행 —
    S_GRADE_MASTER_PLAYBOOK.md 3.3절에 남은 항목 기록
  - flutter analyze 0건, flutter test 1014개 중 1006 통과·6 스킵(이 환경에
    PowerShell 없음)·2 실패(quest_completion_execution_lock_test.dart file
    backend — 이 컨테이너의 파일 advisory lock 특성 차이로 추정되는 기존
    환경 이슈, Phase 6 착수 전부터 동일하게 실패)

## Phase 1 상세 계획 (진행 중)

### 목표
이후 모든 단계에서 발생하는 신규 버그를 개발자가 인지할 수 있는 최소한의 관측성을 확보한다.
로컬 전용 데이터 철학(README 명시)과 충돌하지 않도록, 크래시 리포팅은 opt-in 토글로 설계한다.

### 범위
1. `lib/main.dart`에 `runZonedGuarded` + `FlutterError.onError` 전역 캐치 추가
   - 현재 앱 부트스트랩(`AppBootstrap`)이 storage 초기화 실패만 복구 화면으로 처리하고 있음
   - 이 구조를 유지한 채, 그 바깥 zone과 프레임워크 에러 핸들러에 전역 캐치를 추가
2. 크래시 리포팅 서비스 도입 (Sentry 또는 Firebase Crashlytics 중 택1 — Codex 계획 단계에서
   두 옵션의 트레이드오프를 비교하고 이 프로젝트(오프라인 우선, 6개 플랫폼 지원)에 더 맞는
   쪽을 제안하도록 위임)
   - 설정 화면에 "충돌 리포트 보내기" 토글 추가 (기본값: 꺼짐 — opt-in)
   - 꺼져 있으면 SDK 초기화 자체를 하지 않거나 전송을 억제
3. 개인정보처리방침 문서 작성 (`docs/privacy_policy.md`)
   - 로컬 저장 원칙 명시
   - 크래시 리포팅 켰을 때만 전송되는 데이터 범위 명시
   - 설정 화면에서 이 문서로 연결

### 신규/수정 예상 파일
- `lib/main.dart` (수정)
- `lib/services/crash_reporting_service.dart` (신규)
- `lib/screens/settings_screen.dart` (수정 — 토글 추가)
- `docs/privacy_policy.md` (신규)
- `pubspec.yaml` (수정 — 선택한 SDK 의존성 추가)
- 관련 테스트 신규/수정

이 계획은 Codex의 상세 계획 문서(`docs/plans/phase1_observability_plan.md`)로 구체화된 뒤
실행한다.
