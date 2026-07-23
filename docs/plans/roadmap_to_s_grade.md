# S급 달성 로드맵

목표: 4개 평가축(엔지니어링 완성도 / 프로덕션 출시 준비도 / 시장 매력도 / 현대적 편의성)을
모두 S급 수준으로 끌어올린다.

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
- [ ] Phase 2 — 클라우드 백업/동기화
- [ ] Phase 3 — 프로덕션 배포 블로커 해소 (서명, 실기기 검증, 스토어 자산)
- [ ] Phase 4 — 알림 액션 완료 + 홈 화면 위젯
- [ ] Phase 5 — 감성적 훅 강화 (마이크로 애니메이션, 공유 카드)
- [ ] Phase 6 — 엔지니어링 마감 (파일 분할, 접근성, 데스크톱 단축키)

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
