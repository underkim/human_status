# Human Status S급 기준 v3 FINAL

> **이 문서는 v1→v1검토→v2→v2검토→v3 과정을 거쳐 확정되었으며,
> `docs/plans/S_GRADE_MASTER_PLAYBOOK.md`보다 이 문서가 기준 세부사항에 대해
> 우선한다.**

## 1. 판정 규칙

1. S급은 네 평가축의 모든 필수 항목을 통과한 상태다. 점수 평균으로 상쇄하지 않는다.
2. 판정은 `통과 / 미통과 / 해당없음` 중 하나다. 실행하지 않았거나 증적을 열어
   확인할 수 없으면 미통과다. 과거 계획·주장·테스트 파일 존재만으로 통과하지 않는다.
3. 해당없음은 기능/플랫폼이 공식 지원 범위 밖이고 코드·UI·배포 자산 어디에서도
   제공을 약속하지 않을 때만 허용한다.
4. 자동 증적은 평가 SHA에서 실행한다. 이 저장소 경로의 한글 때문에 Flutter
   analysis/build 도구가 실패하면 같은 SHA의 ASCII-only clean clone에서 실행하고
   양쪽 SHA가 같음을 기록한다.
5. 외부·수동 증적은 `owner, date, SHA, environment/device, evidence`가 모두
   있어야 한다. artifact는 SHA-256도 기록한다. 코드 변경 후 영향 분석에 따른
   재사용 승인이 없으면 이전 수동 증적은 무효다.
6. 테스트 수 1,024는 회귀 감시 기준선이지 품질 점수가 아니다. 감소는 삭제된
   테스트와 동등·상위 대체 테스트를 리뷰에서 승인한 기록이 있을 때만 허용한다.

## 2. 로컬 개인 사용 S급

현재 목표 플랫폼은 Windows다.

### 2.1 엔지니어링 완성도

| ID | 기준과 측정 방법 | 통과 임계치 |
|---|---|---|
| L-E1 | 동일 SHA의 ASCII-only clone에서 `flutter analyze --no-pub` | 종료 0, issue 0 |
| L-E2 | 평가 checkout에서 `flutter test --no-pub` | 종료 0, 실패·스킵 0, 1,024개 이상 통과. 감소 시 1절 6항 승인 필요 |
| L-E3 | `flutter test --no-pub test/financial_transaction_atomicity_test.dart test/goal_creation_atomicity_test.dart test/goal_edit_delete_atomicity_test.dart test/quest_edit_delete_atomicity_test.dart test/reward_transaction_test.dart test/completion_reward_integrity_test.dart test/backup_service_test.dart test/transaction_import_service_test.dart test/storage_service_secret_test.dart` | 열거한 파일 전부 존재, 종료 0 |
| L-E4 | `.github/workflows/ci.yml`에서 analyze/전체 test/Web release/Windows release 단계 확인 후 `gh run list --commit <SHA> --workflow CI --limit 10 --json headSha,status,conclusion,url` | 네 단계 존재. 해당 SHA run이 `completed/success` |

### 2.2 프로덕션/운영 안정성(로컬 범위)

| ID | 기준과 측정 방법 | 통과 임계치 |
|---|---|---|
| L-P1 | 동일 SHA ASCII clone에서 `flutter build windows --release --no-pub`; exe 존재 및 `Get-FileHash ... -Algorithm SHA256` | 종료 0, exe 존재, hash 기록 |
| L-P2 | Release bundle 수동 스모크: (a) 프로세스/`Human Status` 창 30초 유지, (b) 설정 진입, (c) 퀘스트 생성, (d) 완료, (e) 종료·재시작 후 완료 상태 유지 | 5/5 성공, crash·데이터 유실 0. 각 단계 체크/화면 증적 필요 |
| L-P3 | `flutter test --no-pub test/backup_service_test.dart test/auto_backup_service_test.dart test/storage_service_auto_backup_test.dart test/storage_service_secret_test.dart test/crash_reporting_service_test.dart test/observability_settings_test.dart test/app_bootstrap_test.dart` | 파일 전부 존재, 종료 0 |

### 2.3 시장 매력도

| ID | 기준과 측정 방법 | 통과 임계치 |
|---|---|---|
| L-M1 | `flutter test --no-pub test/delight_animation_test.dart test/action_hub_card_test.dart test/dashboard_remaining_quest_test.dart test/quests_screen_flow_test.dart test/completion_reward_integrity_test.dart test/goal_completion_claim_test.dart` | 완료→XP→레벨업/업적/목표 연쇄, reduced motion, 중복 방지 관련 테스트 실패 0 |
| L-M2 | `flutter test --no-pub test/onboarding_screen_test.dart test/dashboard_screen_test.dart test/goal_form_screen_test.dart test/quest_form_screen_test.dart test/finance_screen_characterization_test.dart test/report_screen_test.dart` | 6개 핵심 여정 파일 전부 존재, 종료 0 |
| L-M3 | Windows release에서 온보딩·대시보드·퀘스트·목표·재무·리포트·설정의 7화면을 light/dark 및 400×800/1440×900으로 검사하고 조합별 체크 행 또는 screenshot 보존 | 28/28에서 overflow, clip, 깨진 icon, 읽을 수 없는 텍스트 0 |

### 2.4 현대적 편의성

| ID | 기준과 측정 방법 | 통과 임계치 |
|---|---|---|
| L-C1 | `flutter test --no-pub test/accessibility` | 디렉터리 내 테스트 존재, 종료 0, 실패·스킵 0 |
| L-C2 | `flutter test --no-pub test/shortcuts`; Windows release에서 Ctrl+1..5, Ctrl+F, Ctrl+N, Escape, Ctrl+Tab 수동 실행 | 자동 실패 0, 수동 9동작 전부 기대 상태 변화 |
| L-C3 | `flutter test --no-pub test/wide_layout_test.dart test/backup_service_test.dart test/auto_backup_service_test.dart test/auto_backup_settings_test.dart test/asset_snapshot_import_service_test.dart test/transaction_import_service_test.dart` | 파일 전부 존재, 종료 0 |

## 3. 스토어 출시 S급

같은 RC SHA에서 L-* 전부를 먼저 통과해야 한다. Store S급의 플랫폼 범위는
Play Store Android와 App Store iOS이며, 함께 공개한다고 선언한 Windows/Web/
Linux/macOS도 S-P5 대상이다.

### 3.1 엔지니어링 완성도

| ID | 기준과 측정 방법 | 통과 임계치 |
|---|---|---|
| S-E1 | OS별 runner에서 같은 SHA·Flutter 3.44.6으로 `flutter build appbundle --release --no-pub`, `flutter build ios --release --no-codesign --no-pub`, `flutter build macos --release --no-pub`, `flutter build linux --release --no-pub`, `flutter build windows --release --no-pub`, `flutter build web --release --no-pub` | 6/6 종료 0, 각 environment와 artifact SHA-256 기록. no-codesign은 compile 증적일 뿐 S-P4를 대체하지 않음 |
| S-E2 | `flutter test --no-pub test/gitignore_signing_secrets_test.dart test/android_release_signing_test.dart test/release_readiness_checker_test.dart test/storage_service_secret_test.dart`; `git ls-files`에서 `key.properties`, `*.jks`, `*.keystore`, `*.p12`, `*.p8`, `*.mobileprovision` 검사; tracked Dart/YAML의 실제 DSN/token literal 검토 | 테스트 종료 0, tracked credential/keystore/실제 DSN·token 0 |

### 3.2 프로덕션 출시 준비도

| ID | 기준과 측정 방법 | 통과 임계치 |
|---|---|---|
| S-P1 | 실제 Android release 자격 증명 환경에서 `dart run tool/check_release_readiness.dart --json` | 종료 0, `"ready": true`, issues 0 |
| S-P2 | `rg -n "\\[TODO:|초안" docs/privacy_policy.md`; 공개 HTTPS 정책을 비로그인 브라우저에서 열고 앱 asset과 문단별 대조 | grep 0건, HTTP 200, 앱/웹 내용 불일치 0, 운영 승인 증적 1건 |
| S-P3 | signed AAB의 `keytool -printcert -jarfile ...` fingerprint를 Play upload certificate와 대조; internal track에서 최소/최신 지원 Android 기기로 온보딩·퀘스트·목표·거래·백업·알림 수행 | fingerprint 일치, 두 기기 각 6/6, blocker 0 |
| S-P4 | Xcode signed archive validate, App Store Connect/TestFlight upload, 실제 iPhone에서 S-P3의 6과업 수행 | archive/upload 성공, iPhone 6/6, blocker 0 |
| S-P5 | 공개 선언한 Windows/Linux/macOS/Web clean 환경에서 시작·재시작·핵심 여정·백업 왕복·알림/설정·기본 crash-report off 수행 | 플랫폼별 7/7, blocker·데이터 유실 0. 미공개 플랫폼만 1절 3항에 따라 해당없음 가능 |
| S-P6 | 플랫폼별 고유 synthetic event ID로 프록시/Sentry 대시보드에서 기본 off, opt-in, opt-out, source/symbol mapping 확인 | off 요청 0; ID 1개가 1회 도달; opt-out 이후 신규 0; source file/line 식별 |
| S-P7 | `docs/RELEASE_CHECKLIST.md`의 기존 27개 항목을 사람이 전수 검사 | 27/27 `[x]`, 각 항목에 owner/date/SHA/environment/evidence 존재. 단순 `[x]`는 미통과 |

### 3.3 시장 매력도

| ID | 기준과 측정 방법 | 통과 임계치 |
|---|---|---|
| S-M1 | Play/App Store 실제 console required 표시와 validator를 확인하고 두 명이 RC UI·설명·icon·screenshot·privacy·등급을 독립 검수 | required 0, RC 불일치·민감정보 0, 검수 2/2 승인 |
| S-M2 | Android/iPhone 각 5명에게 동일한 6과업(온보딩, 퀘스트 생성, 완료 결과 이해, 목표 연결, 거래 기록, 백업 내보내기)을 수행시키고 사용자/과업/시간/도움/실패를 표로 기록 | 총 60과업 중 57 이상 무도움 성공, 모든 사용자가 blocker 0, 사용자별 완료시간 중앙값 10분 이하 |
| S-M3 | 대표 Android/iPhone/Windows release/profile에서 30회 cold start와 완료 animation 100회를 DevTools performance로 측정 | cold start p95 ≤3.0초, animation frame p99 ≤33.3ms, crash 0 |

### 3.4 현대적 편의성

| ID | 기준과 측정 방법 | 통과 임계치 |
|---|---|---|
| S-C1 | TalkBack, iOS VoiceOver, Narrator, macOS VoiceOver, Orca, Web screen reader에서 20과업: 앱/탭 이름, 5탭 이동, 퀘스트 생성·검색·완료, 목표 생성, 거래 생성, 리포트 기간 변경, 설정 토글, 백업 내보내기/가져오기, 다이얼로그 닫기, 오류 읽기, 200% text, reduced motion | 각 보조기술 20/20, blocker·focus trap 0 |
| S-C2 | Windows/macOS/Linux/Web에서 키보드만으로 12과업: Tab/Shift+Tab, Enter/Space, 5탭 이동, 검색, 새 퀘스트, Escape, 탭 순환, form 저장, dialog 취소, backup action, Web 200% zoom/reflow | 플랫폼별 12/12, keyboard trap·가려진 콘텐츠·페이지 수평 스크롤 0 |
| S-C3 | Android/iOS에서 cross-isolate, 동시/중복 탭, stale payload, 종료 상태, 저전력 행렬 | 기능 노출 시 전 케이스 통과, 중복 보상·cache 불일치 0. `kQuestCompletionNotificationActionEnabled == false`이고 UI/스토어 자산에 약속이 없으면 해당없음 |
| S-C4 | 버전이 고정된 이전 백업 fixture를 각 공개 지원 RC에서 복원하고 stats/quests/goals/transactions/assets/plan/achievements의 개수·금액 합계·완료 상태 대조 | 공개 지원 플랫폼 100%, 불일치 0 |

## 4. 최종 판정 형식

평가 보고서는 모든 ID를 한 번씩 포함하고 실제 출력, 파일/라인 또는 외부 증적을
연결한다. 로컬과 스토어 각각 축별 결과와 전체 `S급/비S급`을 쓴다. 미통과가
하나라도 있으면 전체는 비S급이다.

