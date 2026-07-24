# Human Status S급 기준 v1

> 상태: 라운드 1 초안. 이 문서는 검토 전이며 최종 기준이 아니다.

## 1. 판정 원칙

S급은 네 평가축을 모두 통과한 상태다. `통과`는 명시된 명령 또는 수동 절차의
증적이 임계치를 만족할 때만 부여한다. 실행하지 못했거나 증적이 없으면
`미통과`다. 로컬 개인 사용과 스토어 출시는 별도 판정한다.

## 2. 로컬 개인 사용 S급

### 엔지니어링 완성도

| ID | 기준 | 측정 방법 | 통과 임계치 |
|---|---|---|---|
| L-E1 | 정적 품질 | `flutter analyze --no-pub` | 종료 0, issue 0 |
| L-E2 | 전체 회귀 | `flutter test --no-pub` | 종료 0, 실패·스킵 0, 총 통과 수 1,024 이상 |
| L-E3 | 핵심 데이터 무결성 | `flutter test --no-pub test/financial_transaction_atomicity_test.dart test/goal_creation_atomicity_test.dart test/goal_edit_delete_atomicity_test.dart test/quest_edit_delete_atomicity_test.dart test/reward_transaction_test.dart test/completion_reward_integrity_test.dart` | 종료 0, 실패 0 |
| L-E4 | CI 재현성 | `.github/workflows/ci.yml`을 읽고 analyze/test/Web release/Windows release 단계 존재 확인 | 네 단계가 모두 존재하고 최신 `master` 실행이 성공 |

### 프로덕션 출시 준비도(로컬 범위)

| ID | 기준 | 측정 방법 | 통과 임계치 |
|---|---|---|---|
| L-P1 | Windows release 생성 | ASCII-only 경로의 동일 SHA에서 `flutter build windows --release --no-pub` | 종료 0, `build/windows/x64/runner/Release/human_status.exe` 존재 |
| L-P2 | 앱 실행 | Release 폴더 전체에서 exe 실행 후 프로세스·창 확인 | 프로세스가 30초 이상 유지되고 `Human Status` 창이 표시 |
| L-P3 | 로컬 데이터/백업 계약 | `flutter test --no-pub test/backup_service_test.dart test/auto_backup_service_test.dart test/storage_service_auto_backup_test.dart test/storage_service_secret_test.dart` | 종료 0, 실패 0 |
| L-P4 | 기본 비전송 | `flutter test --no-pub test/crash_reporting_service_test.dart test/observability_settings_test.dart test/app_bootstrap_test.dart` | 종료 0, 기본 off·DSN 없음·비동의 capture 0회 관련 테스트 전부 통과 |

### 시장 매력도

| ID | 기준 | 측정 방법 | 통과 임계치 |
|---|---|---|---|
| L-M1 | 완료 피드백과 중복 방지 | `flutter test --no-pub test/delight_animation_test.dart test/action_hub_card_test.dart test/dashboard_remaining_quest_test.dart test/quests_screen_flow_test.dart` | 종료 0, 실패 0 |
| L-M2 | 핵심 사용 여정 | `flutter test --no-pub test/onboarding_screen_test.dart test/dashboard_screen_test.dart test/goal_form_screen_test.dart test/quest_form_screen_test.dart test/finance_screen_characterization_test.dart test/report_screen_test.dart` | 종료 0, 실패 0 |
| L-M3 | 시각 품질 | Windows release에서 온보딩·대시보드·퀘스트·목표·재무·리포트·설정을 light/dark, 400×800과 1440×900으로 수동 확인 | 14개 조합에서 overflow, 잘림, 비가독 텍스트, 깨진 아이콘 0건 |

### 현대적 편의성

| ID | 기준 | 측정 방법 | 통과 임계치 |
|---|---|---|---|
| L-C1 | 접근성 자동 계약 | `flutter test --no-pub test/accessibility` | 종료 0, 실패·스킵 0 |
| L-C2 | 데스크톱 단축키 | `flutter test --no-pub test/shortcuts` 후 Windows release에서 Ctrl+1..5, Ctrl+F, Ctrl+N, Escape, Ctrl+Tab을 손으로 실행 | 자동 테스트 실패 0, 수동 9동작 모두 기대 상태 변화 |
| L-C3 | 반응형 UI | `flutter test --no-pub test/wide_layout_test.dart` | 종료 0, 실패 0 |
| L-C4 | 로컬 우선 편의 | 자동/수동 백업, 가져오기, 알림 설정 관련 전체 테스트 실행 | 종료 0, 실패 0 |

## 3. 스토어 출시 S급

스토어 기준은 로컬 기준 전 항목을 먼저 통과해야 한다.

### 엔지니어링 완성도

| ID | 기준 | 측정 방법 | 통과 임계치 |
|---|---|---|---|
| S-E1 | 로컬 품질 게이트 | L-E1~L-E4 재실행 | 전부 통과 |
| S-E2 | 6플랫폼 release compile | Android AAB, iOS IPA, macOS, Linux, Windows, Web release 명령 실행 | 같은 SHA에서 6개 모두 종료 0 |
| S-E3 | 보안 회귀 | `flutter test --no-pub test/gitignore_signing_secrets_test.dart test/android_release_signing_test.dart test/release_readiness_checker_test.dart test/storage_service_secret_test.dart` 및 `git grep`로 시크릿 패턴 검색 | 테스트 실패 0, 실제 시크릿 노출 0 |

### 프로덕션 출시 준비도

| ID | 기준 | 측정 방법 | 통과 임계치 |
|---|---|---|---|
| S-P1 | 저장소 release gate | 실제 release 자격 증명 환경에서 `dart run tool/check_release_readiness.dart --json` | 종료 0, `"ready": true`, issues 0 |
| S-P2 | 개인정보 | `rg -n "\\[TODO:|초안" docs/privacy_policy.md`; 공개 HTTPS 정책 URL 및 앱 내 문서 대조 | grep 0건, URL HTTP 200, 세 내용 불일치 0건 |
| S-P3 | Android 배포 | signed AAB fingerprint를 Play upload certificate와 대조하고 internal track에서 최소/최신 Android 기기 설치·핵심 여정 수행 | fingerprint 일치, 두 기기에서 blocker 0 |
| S-P4 | iOS 배포 | signed archive validation, TestFlight 업로드, 실제 iPhone 핵심 여정 수행 | 세 단계 성공, blocker 0 |
| S-P5 | 나머지 플랫폼 | Windows clean VM, Linux clean VM, macOS clean Mac, HTTPS Web에서 체크리스트 수행 | 각 플랫폼 필수 항목 100% 통과 |
| S-P6 | 관측성 | 6플랫폼에서 기본 off, opt-in synthetic error, opt-out, symbol/source map 확인 | off 요청 0, opt-in 이벤트 플랫폼당 정확히 1, opt-out 신규 0, stack 가독 100% |
| S-P7 | 릴리즈 체크리스트 | `docs/RELEASE_CHECKLIST.md`의 27개 항목과 owner/evidence/date/SHA 확인 | 27/27 `[x]`, 네 메타데이터 모두 존재 |

### 시장 매력도

| ID | 기준 | 측정 방법 | 통과 임계치 |
|---|---|---|---|
| S-M1 | 스토어 자산 완결 | Play/App Store 콘솔 required field와 validator 확인, 2인 검수 | required 0건, 기능 불일치·민감정보 노출 0건, 두 검수자 승인 |
| S-M2 | 실사용 완성도 | Android/iPhone 각 5명의 비개발자에게 온보딩→퀘스트 생성→완료→목표→거래→백업 과업 수행 | 과업 성공률 95% 이상, 중앙 완료시간 10분 이하, blocker 0 |
| S-M3 | 체감 성능 | 각 플랫폼 release/profile에서 시작 및 핵심 화면 프레임 측정 | cold start p95 3초 이하, 애니메이션 프레임의 99%가 16.7ms 이하 |

### 현대적 편의성

| ID | 기준 | 측정 방법 | 통과 임계치 |
|---|---|---|---|
| S-C1 | 6플랫폼 접근성 | TalkBack, iOS/macOS VoiceOver, Narrator, Orca, Web screen reader 수동 스크립트 | 플랫폼별 20개 과업 100% 완료, blocker 0 |
| S-C2 | 입력·반응형 | 지원 데스크톱/브라우저에서 키보드 전용 과업 및 200% zoom/reflow | 과업 100% 완료, 키보드 함정·수평 스크롤 0 |
| S-C3 | 모바일 알림 액션 | Android/iOS cross-isolate·중복 탭·stale payload·종료·저전력 행렬 | 전 케이스 통과, 중복 보상·cache 불일치 0; 아니면 플래그 false 및 자산에서 제외 |
| S-C4 | 복구 가능성 | 이전 버전 백업 fixture를 각 지원 플랫폼 RC에 복원하고 데이터 개수/합계 비교 | fixture 100% 복원, 핵심 개수·합계 불일치 0 |

