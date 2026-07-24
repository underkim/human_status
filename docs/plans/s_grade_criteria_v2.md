# Human Status S급 기준 v2

> 상태: v1 검토의 Blocker와 Should-fix를 반영한 재수립안. 최종본이 아니다.

## 1. 공통 판정·증적 규칙

- 네 축은 모두 gate다. 하나라도 미통과면 해당 범위는 S급이 아니다.
- `해당없음`은 기능/플랫폼이 공식 지원 범위 밖이고 코드·UI·스토어 설명에서 모두
  노출되지 않을 때만 허용한다. 해당없음은 통과와 동등하게 gate를 닫지만 근거가
  필요하다.
- 자동 증적은 평가 대상 SHA에서 실행한다. 한글 경로 Flutter 도구 오류가 있으면
  동일 SHA의 ASCII-only clone에서 실행하고 clone SHA를 기록한다.
- 외부/수동 증적은 `owner, date, SHA, 환경/기기, evidence 경로 또는 URL`을 모두
  포함한다. RC artifact 증적은 SHA-256도 기록한다. 코드가 바뀌면 자동 증적은
  재실행하며, 수동 증적은 영향 분석으로 재사용 승인을 기록하지 않는 한 무효다.

## 2. 로컬 개인 사용 기준

| ID/축 | 측정 방법 | 통과 임계치 |
|---|---|---|
| L-E1 엔지니어링 | 동일 SHA ASCII clone에서 `flutter analyze --no-pub` | 종료 0, issue 0 |
| L-E2 엔지니어링 | `flutter test --no-pub`; `git diff <직전 승인 SHA> -- test`로 삭제/skip 변경 확인 | 실패·스킵 0; 현재 기준선 1,024 이상; 삭제·skip 증가는 승인 사유가 있어야 함 |
| L-E3 엔지니어링 | atomicity/reward/backup/import/secret 관련 저장소 내 테스트 파일을 명시 실행 | 모든 파일 존재, 종료 0 |
| L-E4a 엔지니어링 | `.github/workflows/ci.yml` 정적 검사 | analyze, 전체 test, Web release, Windows release step 존재 |
| L-E4b 엔지니어링 | GitHub Actions의 평가 SHA 포함 run 조회 | quality와 windows-smoke 모두 success |
| L-P1 출시준비 | ASCII clone에서 Windows release 빌드, exe 존재/hash 기록 | 종료 0, exe 존재, SHA-256 기록 |
| L-P2 출시준비 | Release bundle 수동 스모크: 시작, 설정 진입, 퀘스트 생성·완료, 재시작 후 유지 | 5/5 성공, crash·데이터 유실 0 |
| L-P3 출시준비 | backup/auto-backup/storage-secret/crash consent/bootstrap 테스트 | 파일 존재, 종료 0, 실패 0 |
| L-M1 시장 | delight/action hub/quest flow/reward integrity/goal completion 테스트 | 퀘스트 완료→XP→레벨업·업적·목표 연쇄와 중복 방지 테스트 모두 통과 |
| L-M2 시장 | onboarding/dashboard/forms/finance/report 테스트 | 핵심 6과업 테스트 모두 통과 |
| L-M3 시장 | 7화면×2테마×2뷰포트(400×800, 1440×900) 수동 검사 | 28/28에서 overflow·clip·깨진 icon·WCAG 대비 테스트 위반 0 |
| L-C1 편의 | `flutter test --no-pub test/accessibility` | 파일 존재, 실패·스킵 0 |
| L-C2 편의 | `flutter test --no-pub test/shortcuts`; Windows에서 9개 shortcut 수동 실행 | 자동 실패 0, 수동 9/9 |
| L-C3 편의 | `test/wide_layout_test.dart`, backup import/export/auto-backup/settings 테스트 | 파일 존재, 실패 0 |

## 3. 스토어 출시 기준

스토어 기준은 L-* 전부를 같은 RC SHA에서 통과해야 한다.

| ID/축 | 측정 방법 | 통과 임계치 |
|---|---|---|
| S-E1 엔지니어링 | OS별 runner에서 Android AAB, iOS no-codesign compile, macOS, Linux, Windows, Web release build; Apple signed archive는 S-P4 | 6/6 같은 SHA·고정 Flutter 버전, 종료 0, artifact hash 기록 |
| S-E2 엔지니어링 | 보안/release 테스트와 tracked 파일 시크릿 패턴 검사 | 테스트 실패 0, 실제 credential/DSN/token/keystore 0 |
| S-P1 출시준비 | 실제 Android release 자격 증명 환경에서 readiness JSON | 종료 0, ready true, issues 0 |
| S-P2 출시준비 | privacy TODO/초안 grep, 공개 HTTPS와 앱 asset byte/hash 대조, 운영 승인 | TODO/초안 0, HTTP 200, 내용 일치, 승인 1건 |
| S-P3 출시준비 | signed AAB fingerprint/Play certificate 대조, internal track 최소·최신 기기 | fingerprint 일치, 설치·핵심 여정 2/2, blocker 0 |
| S-P4 출시준비 | signed archive validate/upload, TestFlight iPhone | 3/3 성공, blocker 0 |
| S-P5 출시준비 | Windows/Linux/macOS/Web clean 환경 체크리스트 | 공개 지원 플랫폼별 필수 과업 100%, blocker 0 |
| S-P6 출시준비 | 고유 synthetic event ID로 기본 off/opt-in/opt-out/stack mapping | off 요청 0; ID 1개가 1회 도달; opt-out 이후 신규 0; stack source line 식별 |
| S-P7 출시준비 | RELEASE_CHECKLIST 27항목 메타데이터 검사 | 27/27 x, 각 owner/date/SHA/environment/evidence 존재 |
| S-M1 시장 | Play/App Store required field validator와 두 독립 검수자 | required 0, 실제 RC와 불일치·민감정보 0, 2/2 승인 |
| S-M2 시장 | Android/iPhone 각 5명, 사용자당 6개 고정 과업 | 60과업 중 57 이상 성공, 각 사용자 blocker 0; 중앙값 10분 이하 |
| S-M3 시장 | `flutter run --profile`/DevTools performance로 대표 Android/iPhone/Windows에서 30회 cold start와 완료 animation 100회 | cold start p95 ≤3초; animation frame p99 ≤33.3ms; crash 0 |
| S-C1 편의 | 6개 보조기술별 고정 20과업 | 각 20/20, blocker 0 |
| S-C2 편의 | Windows/macOS/Linux/Web 키보드 전용 12과업, Web 200% zoom | 플랫폼별 12/12, keyboard trap·가려진 콘텐츠·페이지 수평 스크롤 0 |
| S-C3 편의 | Android/iOS 알림 액션 행렬 | 기능을 노출하면 전 케이스 통과·중복보상 0. 플래그 false이고 자산/UI에 기능 약속이 없으면 해당없음 |
| S-C4 편의 | 버전 관리된 이전 백업 fixture를 각 공개 지원 RC에서 복원 | 지원 플랫폼 100%, 도메인별 개수·금액 합계·완료 상태 불일치 0 |

## 4. v1 검토 반영 기록

Blocker와 Should-fix를 모두 반영했다. L-P3/L-C4 중복은 L-P3를 저장·동의 계약,
L-C3을 사용자 편의 회귀로 재구성했다. S-M2는 60개 과업의 95%인 57개로
산술적으로 정의했고, S-M3는 프레임 p99를 33.3ms로 현실화하며 도구와 반복 횟수를
정했다. 무시한 지적은 없다.

