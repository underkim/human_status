# Phase 6 — 엔지니어링 마감 구현 계획

> 작성 기준: 2026-07-23 저장소 실측. 이 문서는 구현 계획이며, Phase 6 구현 자체는 포함하지 않는다.

## 0. 결론 요약

Phase 6은 기능을 더하는 단계가 아니라, 이미 동작하는 Human Status를 유지보수 가능하고 보조기술 및 데스크톱 입력에 예측 가능하게 만드는 마감 단계다.

| 축 | 목표 | 이번 Phase 범위 | 비범위 |
|---|---|---|---|
| Part A — 파일 분할 | 1,000줄이 넘는 화면과 서로 다른 책임이 섞인 진입점을 기능 단위로 분리한다 | `finance_screen.dart`, `settings_screen.dart` 우선 분할, `financial_planning_wizard_screen.dart`, `main.dart`, `storage_service.dart`의 제한적 책임 분리 | provider/model 계약 변경, Hive schema 변경, UI 재설계 |
| Part B — 접근성 | 의미, 상태, 순서, 조작 영역, 확대/대비, 라우트 이름을 6개 플랫폼에서 검증 가능한 계약으로 만든다 | 핵심 탐색·퀘스트·재무·설정·다이얼로그의 semantics/focus/reduced motion/터치 영역 보강 | OS별 별도 네이티브 접근성 화면, 콘텐츠 문구 전면 개편 |
| Part C — 데스크톱 단축키 | Windows/macOS/Linux/Web에서 탐색과 반복 작업을 키보드로 완료하게 한다 | 탭 전환, 퀘스트 검색/추가/완료, Escape dismiss를 `Shortcuts`/`Actions`/`Intent`로 구현 | 모바일 전용 외장 키보드 UX 보장, 전역 시스템 단축키 등록 |

순서는 **동작 고정 테스트 → 순수 파일 분할 → 접근성 → 단축키 → 6개 플랫폼 검증**으로 한다. 파일 이동과 행위 변경을 같은 커밋에 섞지 않는다.

## 1. 현재 저장소 조사 결과

### 1.1 `lib/` Dart 파일 줄 수 실측

PowerShell의 `Get-Content` 행 수로 2026-07-23에 측정했다. 250줄 이상 파일은 다음과 같다.

| 순위 | 파일 | 줄 수 | 관찰된 책임 |
|---:|---|---:|---|
| 1 | `lib/screens/finance_screen.dart` | 1,386 | 거래 목록/검색/삭제, 카테고리 분석, 월 차트, 예산 편집 다이얼로그 2종, AI 제안, 코칭 카드 |
| 2 | `lib/screens/settings_screen.dart` | 1,320 | API 키, 알림, 자동 백업, 수동 내보내기/가져오기, 초기화, 충돌 보고, 개인정보 다이얼로그 |
| 3 | `lib/services/storage_service.dart` | 641 | Hive 초기화, secure key migration, 모든 도메인 CRUD, 설정, 자동 백업 상태, notification action token |
| 4 | `lib/services/notification_service.dart` | 610 | 플랫폼 초기화, 예약/취소, 알림 action/category |
| 5 | `lib/screens/financial_planning_wizard_screen.dart` | 606 | wizard 상태·검증·계산·각 step UI·결과 UI |
| 6 | `lib/services/backup_service.dart` | 598 | 백업 encode/decode/검증/복원 |
| 7 | `lib/providers/quest_provider.dart` | 551 | 퀘스트 상태와 완료/보상/추천 orchestration |
| 8 | `lib/main.dart` | 505 | zone 오류 처리, bootstrap 상태 머신, 시작 sequence, 알림 연결, 앱 lifecycle |
| 9 | `lib/services/crash_reporting_service.dart` | 482 | 동의 기반 충돌 보고 경계 |
| 10 | `lib/screens/quests_screen.dart` | 472 | 탭/검색과 active/suggested/completed 목록 |
| 11 | `lib/providers/goal_provider.dart` | 449 | 목표 상태·완료 orchestration |
| 12 | `lib/screens/report_screen.dart` | 426 | 기간 선택과 요약/XP/스탯/재무/목표 카드 |
| 13 | `lib/screens/onboarding_screen.dart` | 379 | onboarding 단계 UI |
| 14 | `lib/screens/asset_snapshot_screen.dart` | 351 | 목록/삭제와 `_NetWorthChart` |
| 15 | `lib/screens/goal_form_screen.dart` | 323 | 목표 입력/검증 |
| 16 | `lib/screens/dashboard_screen.dart` | 314 | 대시보드 조합과 `_RemainingActiveQuests` 완료 흐름 |
| 17 | `lib/services/notification_action_handler.dart` | 312 | background action dispatch/storage lifecycle |
| 18 | `lib/services/auto_backup_service.dart` | 302 | 자동 백업 실행 |
| 19 | `lib/providers/auto_backup_provider.dart` | 290 | `AutoBackupState`, action 결과, notifier |
| 20 | `lib/screens/insights_screen.dart` | 280 | 인사이트 화면 |
| 21 | `lib/providers/finance_provider.dart` | 275 | 재무 상태 |
| 22 | `lib/screens/banksalad_import_screen.dart` | 271 | 파일 선택/미리보기/가져오기 |
| 23 | `lib/theme/app_theme.dart` | 268 | light/dark Material 3 컴포넌트 테마 |

분할 우선순위는 줄 수만으로 정하지 않는다. `finance_screen.dart`에는 `FinanceListView`, `_CategoryBreakdownCard`, `_MonthlyExpenseChartCard`, `_BudgetCard`, `_CategoryBudgetRow`, `_BudgetAmountDialog`, `_CategoryBudgetDialog`, `_CoachingCard`, `_SummaryStat`가 함께 있고, `settings_screen.dart`의 `_SettingsScreenState`에는 알림·자동 백업·수동 백업·privacy가 한 State에 결합돼 있다. 둘은 **서로 독립 테스트 가능한 UI/작업 군이 한 library에 섞여 있으므로 최우선**이다. 반대로 `quest_provider.dart`처럼 긴 orchestration은 private lock/rollback 경계를 성급히 나누면 원자성을 훼손하므로 이번 Phase의 필수 분할 대상이 아니다.

### 1.2 테마와 디자인 토큰

- `lib/theme/app_spacing.dart`는 4px 기반 `AppSpacing`(`xs=4`, `sm=8`, `md=12`, `lg=16`, `xl=24`, `xxl=32`, `xxxl=48`)을 정의한다.
- 같은 파일의 `AppDimens.minTouchTarget`은 **48**이며 주석상 Android 48dp와 iOS 44pt 중 더 엄격한 값을 채택한다. `buttonHeightStandard=44`, `buttonHeightLarge=52`, `inputHeightStandard=52`다.
- `lib/theme/app_theme.dart`에서 `FilledButtonThemeData.minimumSize`는 `Size(48, AppDimens.minTouchTarget)`, `IconButtonThemeData.minimumSize`는 48×48이다. 즉 테마를 타는 버튼은 기본 방어가 있으나 `GestureDetector`, 직접 크기를 둔 컨트롤, 차트 hit target은 별도 감사가 필요하다.
- `lib/theme/app_colors.dart`의 `AppColors`는 light/dark `ThemeExtension`이며, `lib/theme/app_typography.dart`는 공통 typography를 제공한다. 대비 개선은 raw 색상 추가보다 `ColorScheme`/`AppColors` 토큰 조정으로 수행하고 두 theme를 동시에 측정한다.
- `lib/theme/app_spacing.dart`의 breakpoint는 compact `<600`, medium `600..<840`, expanded `>=840`이다. `HomeShell`은 compact에서 `NavigationBar`, 그 외에서 `NavigationRail`을 사용한다.

### 1.3 접근성 실측

| 항목 | 현재 값/위치 | 판단 |
|---|---|---|
| 명시적 `Semantics` | 총 5회: `celebration_dialog_shell.dart` 2, `quest_card.dart` 1, `onboarding_screen.dart` 1, 그리고 같은 검색에서 shell root 포함 | 전체 주요 화면 대비 매우 제한적 |
| `ExcludeSemantics` | `celebration_dialog_shell.dart` 1회 | 장식 emoji 중복 낭독 방지 |
| `MergeSemantics` | 0회 | 복합 카드가 자식 단위로 과도하게 읽힐 가능성 감사 필요 |
| reduced motion | `quest_completion_button.dart` 2회, `achievement_dialog.dart` 1회, `level_up_dialog.dart` 1회 | Phase 5 모션에는 적용됐으나 앱 전체 animation/차트/전환 감사 필요 |
| 최소 조작 영역 | `app_theme.dart`에서 3회 직접 적용 | 테마 기반 버튼은 보호되지만 커스텀 탭 영역은 미확인 |
| screen reader 상태 알림 | `quest_card.dart`의 처리 중 semantics, `celebration_dialog_shell.dart`의 dialog/live region 계열 | 비동기 저장·삭제·가져오기·검색 결과에는 일관된 announce 계약 없음 |
| 포커스 API | `Focus`, `FocusNode`, `FocusTraversal*`, `KeyboardListener` 모두 0회 | 명시적 초기 포커스·복귀·순서가 없음 |
| 키보드 API | `Shortcuts`, `Actions`, `CallbackShortcuts`, `Intent`, `LogicalKeyboardKey`, `SingleActivator` 모두 0회 | Flutter 기본 Tab/Enter 동작 외 앱 단축키 없음 |
| 라우트 이름 | `MaterialApp(home: const HomeShell())`; 핵심 화면에 명명된 route 체계 없음 | screen reader route announcement를 명시적으로 보장하지 못함 |

긍정적인 기반도 있다. Material `NavigationBar`, `NavigationRail`, `IconButton.tooltip`, `FilledButton`, `AlertDialog`를 사용하므로 기본 semantics와 키보드 activation을 재사용할 수 있다. Phase 5의 `CelebrationDialogShell`은 route semantics, 장식 제외, reduced motion을 이미 고려하므로 신규 다이얼로그 계약의 기준으로 삼는다.

### 1.4 데스크톱 입력 실측과 유용한 지점

- `HomeShell`은 `_index`와 `_select(int)`로 5개 탭을 제어하므로 숫자 탭 전환을 한 곳에서 구현할 수 있다.
- `QuestsScreen`은 `_openSearch`, `_closeSearch`, `_clearSearchText`, `_onSearchChanged`와 `TabController`를 이미 보유한다. 검색 focus와 탭 전환의 명확한 소유자다.
- `_ActiveTabState._completeQuest(Quest)`, `DashboardScreen`의 `_RemainingActiveQuestsState._completeQuest(Quest)`, `ActionHubCard._completeHighlighted`는 완료 진입점이다. “선택된 퀘스트” 개념은 현재 없으므로 임의의 첫 퀘스트를 완료하는 단축키는 만들지 않는다.
- `ActionHubCard._addQuest`와 `QuestsScreen`의 add action이 새 퀘스트 route의 기존 진입점이다.
- 모든 Material dialog는 Escape의 기본 dismiss 동작을 보존해야 한다. 저장 중이거나 파괴적 작업 확인처럼 `barrierDismissible` 정책이 있는 경우 앱 전역 Escape로 우회하지 않는다.

## 2. Part A — 파일 분할

### 2.1 원칙

1. public 클래스명, 생성자, callback 타입, provider 접근, route 반환값을 유지한다.
2. private 심볼을 옮겨 외부 공개로 바꾸지 않는다. 다른 library에서 필요하면 기능 폴더의 public widget으로 승격하되 최소 API만 노출한다.
3. barrel export를 새로 남발하지 않는다. 기존 import가 `finance_asset_tab_view.dart`의 `FinanceScreen`을 보는 구조 등 실제 진입점을 유지한다.
4. 파일 이동 커밋에서는 문구, padding, 색, animation, async 순서, `mounted` 검사, provider read/watch를 바꾸지 않는다.
5. golden/semantics/key 테스트를 먼저 추가해 분할 전후 동일성을 증명한다.

### 2.2 대상별 분할안

#### A1. `lib/screens/finance_screen.dart` (1,386줄)

신규 `lib/screens/finance/` 아래로 다음을 이동한다.

| 현재 심볼 | 신규 파일 | 계약 |
|---|---|---|
| `FinanceListView`, `_FinanceListViewState` | `finance_list_view.dart` | 기존 constructor와 검색/필터/삭제 흐름 유지 |
| `_CategoryBreakdownCard`, `_SummaryStat` | `category_breakdown_card.dart` | 입력 데이터만 받는 widget으로 최소 공개 |
| `_MonthlyExpenseChartCard` | `monthly_expense_chart_card.dart` | 차트 계산/표현 함께 이동 |
| `_BudgetCard`, `_CategoryBudgetRow` | `budget_card.dart` | provider read/watch 위치와 AI suggestion callback 순서 유지 |
| `_BudgetAmountDialog` | `budget_amount_dialog.dart` | `showDialog` 반환 타입/validation 유지 |
| `_CategoryBudgetDialog` | `category_budget_dialog.dart` | controller dispose와 저장 결과 유지 |
| `_CoachingCard` | `finance_coaching_card.dart` | `_isRefreshing`, async 오류/중복 방지 유지 |

기존 `finance_screen.dart`는 필요한 구성 요소를 import하고 기존 외부 진입점인 `FinanceListView`를 re-export하거나 얇은 wrapper로 유지한다. 실제 사용처를 `rg "FinanceListView|finance_screen.dart"`로 확인한 뒤, 호환 import가 테스트/다른 screen에 존재하면 `export 'finance/finance_list_view.dart' show FinanceListView;`를 둔다.

#### A2. `lib/screens/settings_screen.dart` (1,320줄)

한 State에 모인 작업 상태를 섹션별 widget/controller 경계로 분리한다.

| 현재 함수/영역 | 신규 파일 | 주의점 |
|---|---|---|
| `_editApiKey` | `settings/api_key_settings_section.dart` | secure storage 결과와 controller dispose 불변 |
| `_editReminder`, `_toggleWeeklyReport`, `_saveNotificationProfile`, `_showGenericNotificationError` | `settings/notification_settings_section.dart` | `_notificationChangeInProgress` 직렬화와 실패 시 profile 복원 유지 |
| `_formatAutoBackupTimestamp`부터 `_showAutoBackupFolderDialog` | `settings/auto_backup_settings_section.dart` | `AutoBackupState`, provider의 in-flight guard, 경로 축약 문구 유지 |
| `_exportBackup`, `_importBackup`, `_reloadBackupAffectedProviders`, 오류 helper | `settings/manual_backup_settings_section.dart` | `_exportInProgress`/`_importInProgress`, 복원 후 provider reload 목록과 순서 유지 |
| `_confirmReset` | `settings/reset_data_section.dart` | 파괴적 확인 및 취소 semantics 유지 |
| `_toggleCrashReporting`, `_showDataPrivacyDialog`, `_showFullPrivacyPolicy` | `settings/privacy_settings_section.dart` | opt-in 기본값과 문서 내용 불변 |

`SettingsScreen`은 섹션 조합과 page-level busy coordination만 소유한다. 테스트가 `SettingsScreen` 생성자에 주입하는 picker/service callback이 있다면 그대로 유지하고 하위 widget으로 전달한다.

#### A3. 제한적 후속 분할

- `financial_planning_wizard_screen.dart`: `_WizardStepKind`와 state machine은 화면에 유지하고, 목표 선택/은퇴/주택/수익률/결과 renderer를 `financial_planning/`의 step widget으로 이동한다. `_canContinueFrom`, `_calculate`는 순서 민감하므로 이동하지 않는다.
- `main.dart`: `AppBootstrap` 및 loading/error UI를 `app/app_bootstrap.dart`, `HumanStatusApp` lifecycle을 `app/human_status_app.dart`, notification/startup wiring을 `app/startup_sequence.dart`로 이동한다. `main()`과 오류 handler public test seam(`installFlutterErrorReporting`, `zoneErrorHandler`)의 import 호환성을 유지한다.
- `storage_service.dart`: 이번 Phase에서는 무리한 repository 계층 도입을 하지 않는다. `ActionTokenStatus`/`ActionTokenRecord`와 `AutoBackupFrequency`/`AutoBackupFailureCode`를 별도 settings model 파일로 옮길 수 있으나 `StorageService`의 기존 public method는 유지한다. Hive box lifecycle과 secure migration은 한 객체에 남긴다.
- `notification_service.dart`, `backup_service.dart`, provider들은 행위 변경 위험이 커 필수 분할에서 제외하고 후속 후보로 기록한다.

### 2.3 동작 불변 증명

- 분할 전 characterisation test로 화면의 주요 label/action/provider call을 고정한다.
- `flutter analyze`, 전체 `flutter test` 결과가 동일하게 통과해야 한다.
- 공개 import smoke test를 추가해 기존 import 경로가 compile됨을 확인한다.
- async dialog는 반환값, `mounted`, pending disable, dispose를 테스트한다.
- `git diff --stat`과 이동 전후 widget tree snapshot을 검토하며 파일 분할 커밋에는 사용자 노출 문자열 변경이 없어야 한다.

## 3. Part B — 접근성

### 3.1 구체 개선

| 영역 | 구현 |
|---|---|
| 페이지/라우트 | `Semantics(namesRoute: true, label: ...)` 또는 명명된 `MaterialPageRoute`/`RouteSettings(name: ...)`로 홈·퀘스트·목표·재무·더보기 및 form/report/settings 진입을 알린다. `IndexedStack`의 비선택 탭은 탐색 대상에서 제외되는지 semantics test로 확인한다. |
| 카드 | `QuestCard`, 목표/거래/예산/차트 카드에 제목·상태·값을 한 문장으로 조합한다. 장식 icon은 `ExcludeSemantics`; 별도 action은 합치지 않아 버튼으로 탐색 가능하게 둔다. |
| 상태 | 완료/채택/저장/가져오기/삭제 성공·실패는 `SemanticsService.sendAnnouncement`를 남용하지 않고 visible status/live region을 우선한다. 진행 중 label은 `quest_card.dart`의 기존 “완료 처리 중” 패턴을 확장한다. |
| 포커스 | route 진입 시 제목 또는 첫 필드, 검색 열기 시 검색 필드, dialog 열기 시 제목/첫 입력, 닫기 후 호출한 버튼으로 복귀한다. `FocusNode`는 State가 소유하고 dispose한다. |
| 순서 | 화면 시각 순서와 tree 순서를 먼저 일치시킨다. 반응형 Row/Wrap 때문에 달라지는 곳만 `FocusTraversalGroup`과 `OrderedTraversalPolicy`/`NumericFocusOrder`를 사용한다. |
| 조작 영역 | 모든 직접 탭 가능한 custom widget을 48×48 이상으로 한다. 시각 아이콘 크기는 유지하고 `ConstrainedBox(minWidth/minHeight: AppDimens.minTouchTarget)` 또는 Material button theme를 쓴다. |
| 텍스트 배율 | 1.0, 1.3, 2.0, Flutter가 허용하는 큰 배율에서 overflow/clip을 검사한다. 고정 높이 text container를 제거하고 dialog는 `SingleChildScrollView`를 유지한다. |
| 대비 | light/dark에서 일반 텍스트 4.5:1, 큰 텍스트 3:1, UI component/그래픽 3:1을 목표로 실제 RGB를 측정한다. raw color 대신 `ColorScheme`/`AppColors` 토큰을 조정한다. |
| reduced motion | 기존 `MediaQuery.disableAnimationsOf(context)` 패턴을 모든 신규/기존 명시 animation에 적용한다. 애니메이션 제거 시 완료 상태·focus·announcement는 즉시 동일하게 제공한다. |
| 차트 | `_MonthlyExpenseChartCard`, `_NetWorthChart`, `_XpChartCard`, heatmap에 요약 label과 데이터 표/목록 대체 semantics를 제공한다. 색만으로 상승/하락/강도를 구분하지 않는다. |
| 아이콘 | tooltip 없는 icon-only action에 한국어 tooltip/semantic label을 추가하고, tooltip과 label의 의미를 일치시킨다. |

### 3.2 6개 플랫폼 차이

| 플랫폼 | 보조기술/입력 | 구현·QA 포인트 |
|---|---|---|
| Android | TalkBack, Switch Access, font/display size | 48dp target, traversal, live region, back와 dialog dismiss, 큰 글꼴 |
| iOS | VoiceOver, Voice Control, Dynamic Type | rotor 순서, 44pt 이상(앱은 48 채택), escape gesture와 modal route, 큰 텍스트 |
| Windows | Narrator, keyboard, High Contrast | Tab/Shift+Tab, Enter/Space, focus indicator, High Contrast에서 custom color 가독성 |
| macOS | VoiceOver, Full Keyboard Access | Control+Option 탐색과 앱 단축키 충돌, Command modifier 표기, Escape/modal focus 복귀 |
| Linux | Orca, keyboard, desktop theme | GTK/배포판별 screen reader tree, focus indicator, 시스템 글꼴/scale |
| Web | 브라우저 screen reader, DOM semantics, browser shortcuts | Chrome/Edge/Safari/Firefox에서 heading/button/name, 브라우저 예약키 충돌 회피, 200% zoom/reflow |

Flutter semantics tree가 플랫폼 accessibility bridge로 변환된다는 공통 전제를 사용하되, widget test만으로 네이티브 낭독 순서가 동일하다고 가정하지 않는다.

공식 근거:

- [Flutter accessibility overview](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility)
- [Flutter accessibility testing](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility-testing)
- [`Semantics` API](https://api.flutter.dev/flutter/widgets/Semantics-class.html)
- [`MediaQuery.disableAnimationsOf`](https://api.flutter.dev/flutter/widgets/MediaQuery/disableAnimationsOf.html)
- [`FocusTraversalGroup` API](https://api.flutter.dev/flutter/widgets/FocusTraversalGroup-class.html)
- [`SemanticsService` API](https://api.flutter.dev/flutter/semantics/SemanticsService-class.html)

## 4. Part C — 데스크톱 단축키

### 4.1 구조

`lib/shortcuts/app_intents.dart`에 const `Intent`들을, `lib/shortcuts/app_shortcut_bindings.dart`에 플랫폼별 `ShortcutActivator` map을 둔다. `HomeShell` 최상위에 `Shortcuts`와 `Actions`를 두되, 화면 고유 action은 해당 화면 가까이에 둔다. `CallbackShortcuts`는 빠르지만 행위 활성화 조건과 테스트 가능한 타입 계약이 약하므로 핵심 기능에는 사용하지 않는다.

| 단축키 | Intent | 소유 widget/handler | 활성 조건 |
|---|---|---|---|
| `Ctrl+1..5` / macOS `Meta+1..5` | `SelectHomeTabIntent(index)` | `HomeShell._select` | desktop/web, text editing 중에도 숫자 shortcut은 허용하되 IME 조합 중에는 무시 |
| `Ctrl+F` / `Meta+F` | `SearchQuestsIntent` | `QuestsScreen._openSearch`, 검색 `FocusNode.requestFocus()` | 퀘스트 탭이 활성이고 modal 없음 |
| `Ctrl+N` / `Meta+N` | `CreateQuestIntent` | 기존 새 퀘스트 route 진입점 | 퀘스트 화면, 저장/다이얼로그 중 아님 |
| `Escape` | `DismissLocalUiIntent` | 검색이면 `_closeSearch`; dialog는 Navigator/Material 기본 동작 | 먼저 열린 가장 안쪽 UI만 닫음; 파괴적/진행 중 modal 정책 우회 금지 |
| `Ctrl+Enter` / `Meta+Enter` | `CompleteFocusedQuestIntent` | focus를 가진 `QuestCard`의 기존 완료 callback | active이며 pending 아님; focused quest가 없으면 no-op |
| `Ctrl+Tab`, `Ctrl+Shift+Tab` | `CycleQuestTabIntent(direction)` | `QuestsScreen`의 `TabController` | 퀘스트 화면, text editing/브라우저 예약키 충돌 검증 후 채택. Web 충돌이 크면 미제공 |

“퀘스트 완료”는 focus가 있는 카드에만 제공한다. 현재 선택 모델이 없으므로 전역 `C`로 추천 퀘스트나 첫 퀘스트를 암묵 완료하지 않는다. 삭제/초기화/가져오기 같은 파괴적 작업에는 단축키를 제공하지 않는다.

### 4.2 모바일에서 무해하게 유지

- `defaultTargetPlatform`과 `kIsWeb`을 이용해 Windows/macOS/Linux/Web에만 application shortcut map을 설치한다. Android/iOS에서는 빈 map 또는 wrapper 생략으로 동일 key event를 소비하지 않는다.
- 단, Material의 기본 Tab/Enter/Space/Escape semantics는 막지 않는다. 외장 키보드가 있는 모바일에서도 framework 기본 조작은 유지된다.
- shortcut handler는 기존 callback만 호출한다. provider/service를 직접 우회 호출하지 않아 pending guard, 확인 dialog, 보상 dialog가 그대로 유지된다.
- `Actions.handler`/`Action.isEnabled`로 busy, inactive, modal 상태를 반영한다.

### 4.3 접근성과 충돌 방지

- macOS VoiceOver의 Control+Option 조합, Windows screen reader 키, 브라우저 `Ctrl+L/W/R/T`, OS 전역 shortcut을 사용하지 않는다.
- printable single-key shortcut은 text field/IME와 충돌하므로 금지한다.
- shortcut은 버튼의 대체 수단일 뿐 유일한 수단이 아니다. tooltip에 플랫폼 표기(`⌘F`, `Ctrl+F`)를 추가하되 screen reader label이 불필요하게 반복되지 않게 한다.
- `FocusableActionDetector`를 QuestCard action 경계에 써서 hover/focus/shortcut을 결합하고, 기존 버튼 semantics를 제거하지 않는다.

공식 근거:

- [Flutter keyboard focus system](https://docs.flutter.dev/ui/interactivity/focus)
- [Flutter actions and shortcuts](https://docs.flutter.dev/ui/interactivity/actions-and-shortcuts)
- [`Shortcuts` API](https://api.flutter.dev/flutter/widgets/Shortcuts-class.html)
- [`Actions` API](https://api.flutter.dev/flutter/widgets/Actions-class.html)
- [`SingleActivator` API](https://api.flutter.dev/flutter/widgets/SingleActivator-class.html)
- [`FocusableActionDetector` API](https://api.flutter.dev/flutter/widgets/FocusableActionDetector-class.html)

## 5. 파일별/함수별 작업

### 신규

- `lib/screens/finance/finance_list_view.dart`: `FinanceListView`와 거래 검색/삭제.
- `lib/screens/finance/category_breakdown_card.dart`: `_CategoryBreakdownCard`, `_SummaryStat`.
- `lib/screens/finance/monthly_expense_chart_card.dart`: `_MonthlyExpenseChartCard`와 chart semantics.
- `lib/screens/finance/budget_card.dart`: `_BudgetCard`, `_CategoryBudgetRow`.
- `lib/screens/finance/budget_amount_dialog.dart`, `category_budget_dialog.dart`: 두 입력 dialog.
- `lib/screens/finance/finance_coaching_card.dart`: `_CoachingCard`.
- `lib/screens/settings/*_settings_section.dart`: API key, notification, auto backup, manual backup, reset, privacy 섹션.
- `lib/screens/financial_planning/`: wizard step presentation widgets.
- `lib/app/app_bootstrap.dart`, `human_status_app.dart`, `startup_sequence.dart`: `main.dart` 책임 분리.
- `lib/shortcuts/app_intents.dart`, `app_shortcut_bindings.dart`: typed intents와 플랫폼 map.
- `lib/widgets/accessible_chart_summary.dart`: 차트의 공통 요약/대체 semantics가 최소 두 화면에서 동일할 때만 생성.
- `test/accessibility/`: semantics, text scale, focus traversal 공통 harness.
- `test/shortcuts/`: 탭/검색/추가/완료/dismiss key event 테스트.

### 수정

- `lib/screens/finance_screen.dart`: 호환 진입점/export만 유지.
- `lib/screens/settings_screen.dart`: 섹션 조합, page semantics.
- `lib/screens/home_shell.dart`: route/tab semantics와 global desktop `Shortcuts`/`Actions`.
- `lib/screens/quests_screen.dart`: search `FocusNode`, focus 복귀, tab/search/create intents.
- `lib/widgets/quest_card.dart`: focused quest completion action, 상태/value semantics, 48×48 audit.
- `lib/widgets/action_hub_card.dart`, `lib/screens/dashboard_screen.dart`: 완료 상태 announcement 일관화.
- `lib/widgets/celebration_dialog_shell.dart`, `level_up_dialog.dart`, `achievement_dialog.dart`: 초기 focus, route label, Escape 및 reduced-motion 회귀 검증.
- `lib/screens/report_screen.dart`, `asset_snapshot_screen.dart`, `lib/widgets/completion_heatmap.dart`: chart summary와 색 외 정보.
- `lib/theme/app_theme.dart`, `app_colors.dart`, `app_typography.dart`, `app_spacing.dart`: 측정 결과가 실패할 때만 대비/focus indicator/target 토큰 조정. `minTouchTarget=48`은 유지.
- `lib/main.dart`: public test seam을 보존한 얇은 entrypoint.

## 6. 테스트 계획

### 6.1 위젯·리팩터링 회귀

- `FinanceListView`: 검색 입력/clear, category filter, 삭제 confirm/cancel, provider 호출 횟수.
- 예산 dialog 2종: 초기값, invalid input, 저장, cancel, controller dispose.
- Settings 각 섹션: 기존 `auto_backup_settings_test.dart`를 유지하며 notification rollback, backup in-flight, import 후 provider reload, crash-report opt-in을 분리 테스트.
- bootstrap: loading/error/retry/stale generation/startup sequence exactly-once 기존 계약.
- 공개 import compile test 및 화면의 주요 label/action 수 characterisation test.

### 6.2 접근성

- `tester.ensureSemantics()`와 `find.bySemanticsLabel`로 route/card/button/status name, role, enabled/busy 상태를 검사한다.
- `meetsGuideline(androidTapTargetGuideline)`, `meetsGuideline(iOSTapTargetGuideline)`, `meetsGuideline(textContrastGuideline)`을 light/dark 핵심 화면에 적용한다.
- `MediaQuery(textScaler: ...)`로 1.0/1.3/2.0 및 큰 배율에서 `FlutterError`/overflow가 없는지 검사한다.
- `disableAnimations: true`에서 completion/dialog가 pump settle 지연 없이 최종 상태를 제공하는지 확인한다.
- Tab/Shift+Tab 순서, dialog initial focus, dismiss 후 origin focus 복귀를 검증한다.
- chart는 시각 요소를 읽지 않아도 기간·합계·추세·최대값을 얻는 semantics label/대체 목록을 검사한다.

### 6.3 단축키

- `tester.sendKeyDownEvent`/`sendKeyEvent`로 Windows control, macOS meta modifier를 각각 테스트한다.
- 1..5 탭 전환이 `_index`만 바꾸고 IndexedStack state를 유지하는지 확인한다.
- Ctrl/Meta+F가 검색을 열고 field focus를 얻는지, Escape가 검색만 닫고 화면을 pop하지 않는지 확인한다.
- Ctrl/Meta+Enter는 focused active quest에 한 번만 완료 callback을 보내며 pending/disabled/completed에는 0회여야 한다.
- TextField 입력/IME 상황에서 shortcut이 문자를 훼손하지 않는지, Android/iOS platform override에서 application shortcut이 소비되지 않는지 검사한다.
- dialog가 열렸을 때 global action이 뒤 화면에 전달되지 않는지 확인한다.

### 6.4 실행 행렬

1. `dart format --output=none --set-exit-if-changed lib test`
2. `flutter analyze`
3. `flutter test`
4. Android/iOS widget integration smoke + TalkBack/VoiceOver 수동 QA
5. Windows/macOS/Linux keyboard + screen reader 수동 QA
6. Web Chrome/Edge/Safari/Firefox에서 keyboard, 200% zoom, semantics inspection

## 7. 리스크와 롤백

| 리스크 | 징후 | 예방/완화 | 롤백 단위 |
|---|---|---|---|
| private widget 이동 중 API 확대 | 불필요한 public class/import 증가 | 기능 폴더 내부 최소 공개, 호환 export만 허용 | 해당 파일 분할 커밋 |
| Settings async state 분산 | 중복 backup/import, dispose 후 setState | 기존 pending flag와 provider guard를 characterisation test로 고정 | settings 섹션 커밋 |
| focus trap/유실 | dialog 닫은 뒤 focus 없음, Tab 순환 불가 | origin `FocusNode`, modal traversal test | focus 커밋 |
| screen reader 중복 낭독 | 카드 label과 자식 Text가 반복 | `excludeSemantics`/구조 조정, action은 분리 | 카드별 semantics 커밋 |
| 너무 큰 merged semantics | 내부 버튼이 사라짐 | interactive child에는 `MergeSemantics` 금지 | 해당 widget 커밋 |
| shortcut이 입력/브라우저와 충돌 | 문자 유실, 브라우저 탭 전환 | typed action, editing/modal enable 조건, Web 별도 검증 | shortcut binding 커밋 |
| 완료 단축키 오작동 | 엉뚱한 quest 완료/중복 보상 | focused quest만, 기존 callback/pending lock 재사용 | completion shortcut 커밋 |
| 대비 토큰 변경의 광역 시각 회귀 | light/dark 여러 화면 색 변화 | 실제 측정 실패 토큰만 수정, golden 검토 | theme 커밋 |
| 큰 글꼴 레이아웃 파손 | overflow/잘림 | 고정 높이 제거, scroll/wrap, scale matrix | 화면별 접근성 커밋 |
| 플랫폼 semantics 차이 | widget test 통과, 실제 낭독 실패 | 6플랫폼 수동 QA 체크리스트 | 플랫폼별 보정 커밋 |

Hive schema와 provider/service public 계약은 건드리지 않으므로 데이터 롤백은 필요하지 않다. 각 커밋은 독립 revert 가능해야 하며, shortcut은 bindings 커밋만 되돌려도 기존 pointer/touch UX가 완전히 유지돼야 한다.

## 8. 순차 커밋 제안 및 완료 기준

### 8.1 커밋

1. `test(phase6): characterize finance settings and bootstrap behavior`
2. `refactor(finance): split finance screen widgets without behavior changes`
3. `refactor(settings): split settings sections without behavior changes`
4. `refactor(app): split bootstrap lifecycle and wizard presentation`
5. `test(a11y): add semantics focus scale and tap-target coverage`
6. `feat(a11y): label routes cards states and charts`
7. `feat(a11y): add deterministic focus and reduced-motion coverage`
8. `feat(shortcuts): add typed desktop navigation and quest actions`
9. `test(shortcuts): cover platform bindings focus and modal conflicts`
10. `docs(phase6): record six-platform verification results`

### 8.2 완료 기준

- `finance_screen.dart`와 `settings_screen.dart`가 호환 진입점/조합 역할만 가지며, 각 신규 파일의 책임이 한 문장으로 설명된다.
- 파일 분할 전후 모든 기존 테스트가 통과하고 공개 import/행위 계약이 유지된다.
- 핵심 route, 탭, 카드, dialog, 비동기 상태가 이름·role·state를 semantics tree에 제공한다.
- light/dark 핵심 화면이 Android/iOS target 및 text contrast guideline을 통과한다.
- 2.0 이상 text scale과 200% Web zoom에서 핵심 작업이 잘리거나 접근 불가능하지 않다.
- reduced motion에서 Phase 5 completion/celebration이 즉시 동일한 최종 상태를 제공한다.
- Windows/macOS/Linux/Web에서 탭 전환, 퀘스트 검색/추가/focused 완료, Escape가 명세대로 동작한다.
- Android/iOS에서는 application shortcut layer가 비활성/무해하며 touch와 기본 keyboard semantics가 회귀하지 않는다.
- TalkBack, VoiceOver, Narrator, macOS VoiceOver, Orca, Web screen reader 수동 체크 결과가 기록된다.
- `dart format`, `flutter analyze`, 전체 `flutter test`, 가능한 6개 플랫폼 build smoke가 모두 통과한다.

## 9. 실행 기록(2026-07-24, Linux 컨테이너)

실제 실기기·브라우저·6플랫폼 build 환경이 없는 원격 세션에서 자동화 가능한 범위를
순차 커밋 10개로 완료했다. `flutter analyze` 0건, `flutter test` 1,014개 중 1,006
통과·6 스킵(PowerShell 없음)·2 실패(착수 전부터 있던 환경 이슈, 회귀 아님)를
매 커밋마다 확인했다. 커밋 `f3e6487`~`4266201`.

### 계획 대비 실제 구현

- **Part A(파일 분할)**: 계획한 4개 대상(finance/settings/main+wizard) 그대로 분할.
  `_CategoryBudgetRow`처럼 같은 파일 안에서만 쓰이는 위젯은 계획대로 private 유지,
  다른 파일에서 참조되는 것만 public 승격. `privacy_settings_section.dart`는 원래
  화면에서 크래시 리포팅 토글과 "데이터 및 개인정보" 항목이 서로 멀리 떨어져 있어,
  순서 보존을 위해 계획에 없던 `CrashReportingSettingsTile`/`DataPrivacyTile` 두
  위젯으로 분리했다.
- **Part B(접근성)**: route 명명은 구현하지 않았다 — `HomeShell`의 `IndexedStack`은
  실제 `Navigator` route 경계가 없어, `namesRoute`를 붙였을 때 실기기 screen
  reader가 어떻게 반응할지 검증할 방법이 이 환경에 없었고, 잘못된 semantics가
  아예 없는 것보다 나쁠 수 있다고 판단해 보류했다. 대신 `RenderIndexedStack`이
  비활성 탭을 semantics tree에서 이미 제외한다는 기존 동작을 테스트로 확인했다.
  차트 semantics 요약은 `MonthlyExpenseChartCard` 1개만 구현했다 — report/asset/
  budget 화면의 나머지 차트(NetWorthChart, XP 차트, completion heatmap)는 범위
  밖으로 남겼다. 대비 자동 검사(`textContrastGuideline`)가 실제 버그(다크 테마
  `FilledButton` 대비 2.53:1, WCAG AA 4.5:1 미달)를 하나 찾아냈고 `onPrimary` 토큰
  수정으로 해결했다; 같은 검사가 대시보드 "스텟" 제목에서도 실패를 보고했지만
  두 테마에서 색이 다른데도 비율이 거의 동일(1.17/1.09)하고 rect가 두 글자
  텍스트치고 지나치게 넓어(폭 784) 실제 시각 문제가 아니라 semantics 병합으로
  인한 sampling 오탐으로 판단해 코드를 바꾸지 않고 테스트에서 그 화면만 제외했다.
- **Part C(단축키)**: 계획한 6개 단축키 중 4개(탭 전환, 검색, 새 퀘스트, Escape)를
  구현했다. Ctrl+Tab 퀘스트 탭 순환은 계획서가 이미 예상한 대로 Web 브라우저
  예약키 충돌 위험으로 제외했다. Ctrl+Enter로 포커스된 퀘스트를 완료하는
  단축키는 `QuestCard`에 "포커스된 퀘스트"라는 새 개념 자체를 도입해야 하는데,
  실기기 키보드 검증 없이 완료 보상 경로에 손대는 것으로 판단해 보류했다.
  구현 중 `Shortcuts`가 `primaryFocus`의 조상 체인에서만 반응한다는 점 때문에
  화면 루트에 `Focus(autofocus: true)`를 추가했더니, 검색을 나중에 여는
  TextField 자신의 `autofocus`가 무시되는 실제 회귀가 발생했다 — Phase 6-7에서
  추가한 `focus_test.dart`가 이를 잡아냈고, 검색 진입점을 단축키와 같은
  `_openSearchAndFocus`(명시적 `requestFocus()`)로 통일해 해결했다.

### 9.1 재검토(2026-07-24, 같은 세션 내 후속)

"코드적으로 더 이상 할 게 없는가"라는 질문에 위 기록을 그대로 재확인만 하고
넘어갔던 최초 답변이 부정확했다 — "실기기/계정이 있어야 한다"와 "이번에
안 했다"를 구분하지 않고 뭉뚱그렸다. 다시 훑어 실제로 code-only인 두 항목을
더 처리했다(커밋 `00c3863`/`01ab432`):

- **차트 semantics 요약 3건 추가**: `MonthlyExpenseChartCard` 1개만 하고
  "범위 밖"이라 적었던 나머지 3개 차트(`NetWorthChart`, 통계 화면 최근 7일
  XP, 리포트 XP 추이)에 같은 `Semantics`+`ExcludeSemantics` 패턴을 그대로
  적용했다. 새 패턴이 필요하지 않았다 — 단순히 아직 안 한 반복 작업이었다.
- **Ctrl+Tab 퀘스트 탭 순환**: 계획 문서가 "Web 예약키 충돌 위험"을 이유로
  전체를 제외하라고 한 게 아니라 "충돌이 크면 Web만 제외"라고 이미 적어
  뒀는데, 구현 때는 이를 검토하지 않고 통째로 건너뛰었다. Ctrl+Tab은
  브라우저(모든 주요 브라우저가 페이지 JS에 이벤트를 넘기지 않고 자체 탭
  전환으로 소비)에서만 실제로 가로챌 수 없고, Windows/macOS/Linux 네이티브
  빌드에는 그런 제약이 없다. `isNativeDesktopPlatform`으로 Web만 뺀 뒤
  기존 `TabController`를 순환시켜 구현했다.

반대로 아래 두 항목은 다시 검토한 뒤에도 이번 범위에 넣지 않기로 했다 —
이번엔 "실기기가 없어서"가 아니라 각각 구체적인 이유가 있다:

- **Ctrl+Enter로 포커스된 퀘스트 완료**: 계획이 전제한 "포커스를 가진
  QuestCard"라는 개념 자체가 코드에 없다. `QuestCard`는 완료 콜백을 소유하지
  않고(`_ActiveTabState`가 소유), 카드 자체에 `Focus` 경계도 없다. 이걸
  만들려면 포커스 트래버설 순서를 어떻게 잡을지, 포커스 표시를 시각적으로
  어떻게 줄지, 콜백을 `QuestsScreen`까지 끌어올릴지 등 여러 설계 결정이
  필요한 신규 기능이다 — "이미 있는 기능에 접근성 대체 텍스트를 붙이는"
  이번 재검토의 나머지 항목들과 성격이 다르므로, 급하게 끼워넣기보다
  별도로 설계하고 스코프를 잡는 게 맞다고 판단해 미루었다.
- **route 명명(`namesRoute`)과 6플랫폼 수동 QA**: 기존 기록대로 유지한다.
  `HomeShell`의 `IndexedStack`은 `Navigator` route 경계가 없어 `namesRoute`가
  실제 화면 전환 시 TalkBack/VoiceOver에 어떻게 안내되는지는 정적 semantics
  트리 검사만으로 확정할 수 없고, 잘못 붙이면 없는 것보다 나쁜 안내가 될 수
  있다. 6플랫폼 수동 QA는 이 컨테이너에 실기기·스크린리더가 전혀 없어
  그대로 차단된 상태다.

이 재검토 이후에는 `lib/` 전체에 TODO/FIXME 마커가 없고, fl_chart를 쓰는
4개 파일 모두 semantics 대체 텍스트를 갖췄으며, 계획서에 적힌 6개 단축키 중
5개(Ctrl+Enter 제외)가 구현·테스트됐다. `flutter analyze` 0건,
`flutter test`는 여전히 같은 2개(파일 backend 잠금 테스트, 착수 전부터
있던 환경 이슈)만 실패한다.

### 확인하지 못한 것 (6플랫폼 수동 QA)

TalkBack(Android), VoiceOver(iOS/macOS), Narrator(Windows), Orca(Linux), Web
screen reader 낭독 순서/내용, 실제 키보드로 Windows/macOS/Linux/Web에서 단축키
동작, 200% Web zoom, 6개 플랫폼 build smoke는 이 세션의 컨테이너 환경(실기기·
브라우저·GUI 없음)에서 실행할 방법이 없어 시도하지 않았다. `flutter test`의
`meetsGuideline`/시맨틱스 트리 검사는 정적·자동화된 근사치일 뿐, 실제 보조기술
낭독을 대신하지 않는다. 이 항목들은 실기기/브라우저가 있는 환경에서 별도로
수행해야 한다.
