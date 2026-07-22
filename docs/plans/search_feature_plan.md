# 퀘스트/거래 검색 기능 구현 계획

## 1. 목표와 범위

이 기능은 Hive에 저장된 기존 데이터를 변경하지 않고, Riverpod의 현재 메모리 상태를 화면에서 즉시 필터링하는 로컬 검색이다. 네트워크 검색, 검색 이력 저장, 자동완성, 날짜·금액 범위 검색, 정렬 방식 변경은 이번 범위에서 제외한다.

### 퀘스트 검색 UI

- 대상 화면은 `lib/screens/quests_screen.dart`의 `QuestsScreen`이다.
- `AppBar.actions`에 툴팁이 `퀘스트 검색`인 `Icons.search` 아이콘을 추가한다. 누르면 제목 영역이 `TextField` 기반 검색 입력으로 바뀌며, 기존 `AppBar.bottom`의 3개 `TabBar`(`진행중`, `추천`, `완료`)는 유지한다.
- 검색 모드에는 힌트 `퀘스트 검색`, 입력 지우기 버튼(`Icons.clear`, 툴팁 `검색어 지우기`), 검색 닫기 버튼(`Icons.close`, 툴팁 `검색 닫기`)을 둔다. 닫을 때 검색어와 입력 컨트롤러를 함께 비운다.
- 검색어는 세 탭에 동시에 적용한다. 사용자가 탭을 바꾸어도 같은 검색어가 유지되어 진행중/추천/완료에서 같은 조건을 비교할 수 있다.
- 탭의 건수는 평상시에는 현재처럼 원본 상태별 건수, 검색 중에는 각 탭의 검색 결과 건수를 표시한다. 따라서 `activeQuestsProvider`, `suggestedQuestsProvider`, `completedQuestsProvider` 자체의 기존 의미는 바꾸지 않는다.
- 결과 목록은 현재의 `_ActiveTab`, `_SuggestedTab`, `_CompletedTab`과 `QuestCard`를 그대로 사용한다. 검색으로 보이는 카드의 완료·수정·삭제·채택·무시 동작도 기존 흐름을 그대로 따른다.

### 거래 검색 UI

- 대상 화면은 `lib/screens/finance_screen.dart`의 `FinanceListView`이다. 상위 `FinanceScreen`은 `lib/screens/finance_asset_tab_view.dart`에서 `거래내역`과 `자산현황`을 함께 감싸므로, AppBar 검색을 넣지 않는다. 그래야 검색 UI와 상태가 `거래내역` 탭에만 속한다.
- 기존 `거래 내역` 제목/건수/추가/가져오기 `Wrap` 바로 아래, `_categoryFilter`의 `InputChip` 위에 항상 보이는 인라인 `TextField`를 추가한다. 힌트는 `거래 검색`, prefix는 `Icons.search`, 값이 있을 때 suffix는 `Icons.clear`와 툴팁 `검색어 지우기`를 사용한다.
- 검색은 거래 목록에만 적용한다. `monthlySummaryProvider`, `_BudgetCard`, `_MonthlyExpenseChartCard`, `_CategoryBreakdownCard`, 재무 목표와 코칭 카드는 전체 거래를 계속 사용하여 검색 입력 때문에 집계 수치가 바뀌지 않게 한다.
- 검색어와 기존 `_categoryFilter`는 AND 조건으로 합성한다. 즉 선택한 카테고리 안에서 검색하며, 검색어를 지워도 카테고리 필터는 유지되고 카테고리 필터를 해제해도 검색어는 유지된다.
- `N건`은 최종 합성 결과의 건수를 표시하고, `_groupedTransactionTiles`는 그 결과만 기존 날짜 내림차순과 월 구분 헤더로 렌더링한다.

두 입력 UI의 padding, 간격, 아이콘 크기, 최소 높이는 `lib/theme/app_spacing.dart`의 `AppSpacing`, `AppIconSize`, `AppDimens`를 사용하고, 색은 `Theme.of(context).colorScheme` 또는 `lib/theme/app_colors.dart`의 `context.appColors`를 사용한다. 임의의 색·간격 상수는 추가하지 않는다. 모든 신규 UI 문자열은 한국어로 작성한다.

## 2. 검색 대상과 매칭 규칙

### 퀘스트

`lib/models/quest.dart`의 실제 필드 중 다음만 검색한다.

- `Quest.title`
- `Quest.description`

`id`, `statRewards`, `difficulty`, `isRecurring`, `status`, `source`, `createdAt`, `completedAt`, `goalId`는 이번 텍스트 검색 대상에서 제외한다. 연결된 목표명과 스텟명은 각각 `goalsProvider`/`statsProvider`의 별도 모델을 조인해야 하고 `Quest` 자체 필드가 아니므로 제외한다.

### 거래

`lib/models/transaction.dart`에는 별도의 가맹점명 필드가 없다. 따라서 가상의 `merchantName` 등을 만들지 않고 다음 실제 필드만 검색한다.

- `Transaction.memo`: 뱅크샐러드 가져오기 또는 직접 입력에서 가맹점명이 메모에 들어온 경우도 이 필드 매칭으로 검색된다.
- `Transaction.category`

`id`, `type`, `amount`, `date`, `linkedGoalId`, `createdAt`는 텍스트 검색 대상에서 제외한다. 금액·날짜 검색은 포맷/로케일과 범위 조건 정의가 필요한 별도 기능으로 남긴다.

### 공통 매칭 규칙

- 입력 검색어는 `trim()` 후 `toLowerCase()`하고, 대상 필드도 `toLowerCase()`한 뒤 `contains`로 부분 일치시킨다.
- 검색어 앞뒤 공백만 제거한다. 내부 공백은 보존하므로 실제 제목·설명·메모의 연속 문자열과 일치해야 한다.
- Dart 문자열의 `toLowerCase()`를 사용해 영문 대소문자를 무시한다. 한글은 대소문자가 없으므로 원문 부분 일치로 동작한다.
- 초성 검색, 자모 분해/조합 정규화, 오타 교정은 수행하지 않는다. 예를 들어 `ㅁㅁ`이 `물 마시기`에 일치한다고 보장하지 않는다.
- 빈 문자열 또는 공백뿐인 문자열은 모든 항목과 일치하는 것으로 처리한다.

## 3. 상태관리 설계

검색 UI의 수명과 필터 계산을 명확히 분리한다.

1. `lib/providers/quest_provider.dart`에 제안 신규 타입 `QuestSearchQueryNotifier extends StateNotifier<String>`와 `questSearchQueryProvider = StateNotifierProvider<QuestSearchQueryNotifier, String>`를 추가한다. 공개 메서드는 `setQuery(String query)`와 `clear()`로 제한한다.
2. 같은 파일에 제안 신규 순수 함수 `questMatchesSearchQuery(Quest quest, String query)`를 둔다. 모델을 변경하지 않고 `title`/`description` 매칭만 담당한다.
3. 같은 파일에 제안 신규 파생 Provider `searchedActiveQuestsProvider`, `searchedSuggestedQuestsProvider`, `searchedCompletedQuestsProvider`를 둔다. 각각 기존 `activeQuestsProvider`, `suggestedQuestsProvider`, `completedQuestsProvider`와 `questSearchQueryProvider`를 `watch`하고 순수 함수로 필터링한다. 특히 `searchedCompletedQuestsProvider`는 이미 날짜 내림차순인 `completedQuestsProvider`의 순서를 보존한다.
4. `lib/providers/finance_provider.dart`에 제안 신규 타입 `TransactionSearchQueryNotifier extends StateNotifier<String>`와 `transactionSearchQueryProvider = StateNotifierProvider<TransactionSearchQueryNotifier, String>`를 추가하고 `setQuery`/`clear`를 제공한다.
5. 같은 파일에 제안 신규 순수 함수 `transactionMatchesSearchQuery(Transaction transaction, String query)`와 `searchedTransactionsProvider`를 추가한다. `searchedTransactionsProvider`는 `transactionsProvider`와 검색어만 합성하며 정렬이나 카테고리 필터는 담당하지 않는다.
6. `_FinanceListViewState.build`에서는 `searchedTransactionsProvider` 결과를 복사해 현재처럼 `date` 내림차순으로 정렬한 뒤 `_categoryFilter`를 적용한다. 요약·차트 계산에는 계속 `transactionsProvider` 원본을 넘긴다.

검색어를 `QuestsNotifier`나 `TransactionsNotifier`의 state에 섞지 않는 이유는 두 Notifier의 state가 각각 Hive의 `List<Quest>`, `List<Transaction>`을 대표하며 저장/롤백/reload 책임을 갖기 때문이다. 검색어는 별도의 `StateNotifierProvider`로 두어 기존 프로젝트의 StateNotifierProvider 패턴을 유지하고, 검색 입력이 Hive 쓰기나 `reload()`를 유발하지 않게 한다.

검색어는 영속 저장하지 않는다. 화면 위젯이 dispose될 때 `ref.read(...notifier).clear()`하여 다시 진입하면 빈 검색 상태로 시작하게 한다. 퀘스트 입력용 `TextEditingController`와 검색 모드 플래그, 거래 입력용 `TextEditingController`는 각 `ConsumerState`가 소유하고 `dispose()`한다. Provider의 문자열과 controller 값은 입력 이벤트 및 clear/close 동작에서 동시에 갱신한다.

## 4. 신규/수정 파일과 예상 diff

### 수정: `lib/providers/quest_provider.dart`

- `QuestSearchQueryNotifier`, `questSearchQueryProvider` 추가.
- `questMatchesSearchQuery(Quest, String)` 추가.
- 기존 `activeQuestsProvider`, `suggestedQuestsProvider`, `completedQuestsProvider` 아래에 검색 결과용 파생 Provider 3개 추가.
- 기존 Provider, `QuestsNotifier`, 저장/완료/삭제 로직은 수정하지 않는다.

### 수정: `lib/providers/finance_provider.dart`

- `TransactionSearchQueryNotifier`, `transactionSearchQueryProvider` 추가.
- `transactionMatchesSearchQuery(Transaction, String)`와 `searchedTransactionsProvider` 추가.
- `TransactionsNotifier`, `monthlySummaryProvider`, `FinanceService` 호출 및 Hive 저장 로직은 수정하지 않는다.

### 수정: `lib/screens/quests_screen.dart`

- `_QuestsScreenState`에 검색 모드 bool과 `TextEditingController`를 추가하고 `dispose()`에서 controller 및 `questSearchQueryProvider` 검색어를 정리한다.
- 검색 열기/입력 변경/지우기/닫기 처리를 각각 작은 private 메서드로 분리한다.
- `build`에서 기존 상태별 Provider 대신 검색 결과용 파생 Provider 3개를 `watch`한다. 원본 건수가 별도로 필요하지 않으므로 검색 중이 아닐 때도 빈 검색어의 파생 결과가 원본과 같다는 규칙을 사용한다.
- `AppBar.title`/`actions`를 검색 모드에 맞춰 전환하되 `TabController`, `TabBar`, `TabBarView`, FAB와 세 탭 위젯의 액션 로직은 유지한다.
- `_ActiveTab`, `_SuggestedTab`, `_CompletedTab`은 검색어가 비어 있는지 전달받도록 `bool isSearching`(제안 신규 파라미터)을 추가한다. 목록이 비었을 때 `isSearching`이면 공통 `EmptyState(icon: Icons.search_off, message: '검색 결과가 없어요.', ctaLabel: '검색어 지우기', ...)`를 표시하고, 아니면 현재 탭별 최초 빈 상태 문구를 그대로 표시한다.

### 수정: `lib/screens/finance_screen.dart`

- `_FinanceListViewState`에 거래 검색용 `TextEditingController`를 추가하고 `dispose()`에서 controller와 `transactionSearchQueryProvider`를 정리한다.
- 원본 `transactionsProvider`는 요약/분석용으로 유지하고, 목록용으로 `searchedTransactionsProvider`를 추가로 `watch`한다.
- 기존 `filteredTransactions` 계산을 “검색 결과 정렬 → `_categoryFilter` 적용” 순서로 바꾼다.
- `거래 내역` 헤더 아래에 인라인 검색 입력을 추가한다. 레이아웃 값은 `AppSpacing`, `AppIconSize`, `AppDimens`를 사용한다.
- 빈 상태를 세 경우로 분기한다.
  - 원본 `transactions.isEmpty`: 현재 `아직 기록된 거래가 없어요.` 유지.
  - 검색어 또는 카테고리 필터가 적용됐고 최종 결과가 비어 있음: `EmptyState`에 `검색 조건에 맞는 거래가 없어요.`와 `검색 및 필터 초기화` CTA를 표시하고 두 조건을 모두 해제한다.
  - 카테고리만 적용된 상태의 기존 세부 문구를 유지하려면 `"$_categoryFilter" 카테고리의 거래가 없어요.`를 사용하되, 검색어가 함께 있으면 일반 검색 조건 문구를 우선한다.
- `_groupedTransactionTiles`, `TransactionTile`, 삭제 흐름은 수정하지 않는다.

### 신규: `test/search_provider_test.dart`

- 두 공개 매칭 함수와 검색 파생 Provider의 단위 테스트를 한 파일에 둔다.
- `ProviderContainer`에서 검색어 Notifier를 갱신하고 원본 Provider를 override하거나 테스트 `StorageService`를 연결하여 동적 재계산을 검증한다.

### 신규: `test/search_feature_widget_test.dart`

- 퀘스트와 거래 검색 UI의 통합 위젯 테스트를 둔다.
- 반드시 `test/helpers/test_app.dart`의 `createTestStorage()`, `pumpApp()`, 필요한 경우 `setScreenSize()`를 사용한다.
- 실제 `StorageService.saveQuest`/`saveTransaction`으로 데이터를 시드하고 `QuestsScreen`, `Scaffold(body: FinanceListView())`를 기존 테스트 관행대로 pump한다.

모델, Hive adapter, `lib/widgets/quest_card.dart`, `lib/widgets/transaction_tile.dart`, `lib/widgets/empty_state.dart`, `lib/widgets/error_state.dart`, `test/helpers/test_app.dart`는 수정하지 않는다. 검색은 동기식 순수 필터이므로 별도 로딩/실패 상태가 없으며, 결과 없음에는 기존 `EmptyState`를 재사용한다. 향후 검색 소스가 비동기화되어 실패 가능성이 생길 때만 기존 `ErrorState`를 사용한다.

## 5. 엣지 케이스와 기대 동작

- **빈 검색어/공백뿐인 검색어:** 전체 목록을 반환한다. 공백 입력 때문에 “검색 결과 없음”으로 바뀌지 않는다.
- **결과 없음과 데이터 없음 구분:** 원본 목록 자체가 비었으면 기존 탭별/거래 빈 상태를 보여주고, 원본은 있지만 검색 결과만 없으면 검색 전용 `EmptyState`와 초기화 CTA를 보여준다.
- **대소문자:** `READ`는 `Read book`에 일치한다. 로케일별 고급 case folding은 범위 밖임을 단위 테스트로 현재 규칙에 고정한다.
- **한글:** `마시`는 `물 마시기`에 일치한다. 한글 초성 검색과 유니코드 정규화는 지원하지 않는다.
- **제목/설명 및 메모/카테고리:** 어느 한 필드만 일치해도 항목을 포함한다.
- **검색 중 데이터 변경:** 파생 Provider가 각각 `questsProvider`/`transactionsProvider`를 watch하므로 완료·삭제·채택·무시·추가·가져오기 또는 `reload()`가 일어나면 현재 검색어를 유지한 채 즉시 다시 필터링한다. 검색 결과에서 사라지는 것은 정상 동작이며 stale 복사본을 보관하지 않는다.
- **퀘스트 상태 변경:** 검색 중 진행중 퀘스트를 완료하면 진행중 검색 결과와 건수가 줄고 완료 탭 검색 결과와 건수가 늘어난다.
- **거래 정렬/월 헤더:** 필터 뒤에도 날짜 내림차순을 유지하며, 결과에 존재하는 월에 대해서만 월 헤더를 만든다. 검색 결과가 0건이면 월 헤더가 남지 않는다.
- **검색과 카테고리 필터:** AND 조건이다. 둘 중 하나만 초기화하면 나머지는 유지하며, 결과 없음 CTA만 두 조건을 한 번에 초기화한다.
- **IME 조합:** `TextField.onChanged`의 현재 조합 문자열로 필터링하며 debounce하지 않는다. 로컬 수백 건 수준의 단순 `contains` 검색이므로 프레임별 계산을 우선하고, 성능 측정에서 문제가 확인될 때 debounce를 후속 적용한다.
- **화면 이탈/재진입:** dispose 시 검색어를 지워 이전 화면 세션의 검색이 다시 나타나지 않는다. dispose 중 Provider 변경이 안전한지 위젯 테스트로 확인하고, Riverpod 생명주기 경고가 있으면 Provider를 `autoDispose`로 전환하는 방안을 우선 검토한다.

## 6. 테스트 계획

### 단위/Provider 테스트: `test/search_provider_test.dart`

테스트 설명 문구 수준의 시나리오는 다음과 같다.

- `questMatchesSearchQuery는 빈 문자열과 공백뿐인 검색어에 모든 퀘스트를 반환한다`
- `questMatchesSearchQuery는 title과 description을 부분 일치로 검색한다`
- `questMatchesSearchQuery는 영문 대소문자를 무시하고 한글 부분 문자열을 찾는다`
- `questMatchesSearchQuery는 id, difficulty, goalId를 검색 대상으로 사용하지 않는다`
- `transactionMatchesSearchQuery는 memo와 category를 부분 일치로 검색한다`
- `transactionMatchesSearchQuery는 영문 대소문자를 무시하고 한글 부분 문자열을 찾는다`
- `transactionMatchesSearchQuery는 amount, date, linkedGoalId를 검색 대상으로 사용하지 않는다`
- `searchedActiveQuestsProvider 등은 상태별 목록과 검색어를 합성하고 완료 목록의 기존 정렬을 보존한다`
- `searchedTransactionsProvider는 검색 중 transactionsProvider가 갱신되면 같은 검색어로 결과를 다시 계산한다`
- `검색어 Notifier의 clear는 state를 빈 문자열로 되돌린다`

### 위젯 테스트: `test/search_feature_widget_test.dart`

- `퀘스트 AppBar의 검색 아이콘을 누르면 한국어 힌트의 검색 입력과 닫기 버튼이 표시된다`
- `퀘스트 제목을 입력하면 일치하는 카드만 남고 진행중 탭 건수가 검색 결과 수로 바뀐다`
- `퀘스트 설명으로 검색해도 일치하며 추천과 완료 탭에도 같은 검색어가 유지된다`
- `검색 중 퀘스트를 완료하면 진행중 결과에서 사라지고 완료 탭 결과에 나타난다`
- `퀘스트 검색 결과가 없으면 검색 전용 EmptyState가 표시되고 검색어 지우기로 원본 목록이 복원된다`
- `퀘스트 검색 닫기는 검색어를 비우고 일반 AppBar와 원본 탭 건수를 복원한다`
- `거래 검색 입력은 memo와 category 각각으로 거래를 필터링하고 N건 표시를 갱신한다`
- `거래 검색은 영문 대소문자를 무시하고 한글 부분 문자열을 찾는다`
- `거래 검색과 카테고리 InputChip은 AND 조건으로 적용된다`
- `거래 검색어 지우기는 검색만 해제하고 선택된 카테고리 필터는 유지한다`
- `검색 및 필터 초기화 CTA는 두 조건을 모두 해제하고 전체 거래를 복원한다`
- `검색 결과의 거래는 날짜 내림차순과 해당 월 헤더를 유지한다`
- `검색 중 transactionsProvider가 추가 또는 삭제로 갱신되면 현재 검색어로 목록이 즉시 재계산된다`
- `화면을 나갔다 다시 열면 퀘스트와 거래 검색어가 남지 않는다`
- `좁은 화면에서도 거래 검색 입력과 기존 거래 액션 Wrap에 overflow 예외가 발생하지 않는다`

회귀 확인으로 기존 `test/quests_screen_flow_test.dart`와 `test/finance_transaction_ui_robustness_test.dart`를 함께 실행한다. 구현 완료 검증 명령은 `dart format`(수정 Dart 파일), `flutter analyze`, `flutter test test/search_provider_test.dart test/search_feature_widget_test.dart test/quests_screen_flow_test.dart test/finance_transaction_ui_robustness_test.dart`, 마지막으로 전체 `flutter test` 순서로 제안한다.

## 7. 예상 리스크와 대응/롤백

- **검색어 Provider 수명과 controller 불일치:** Provider만 지워지거나 controller만 지워지면 UI가 어긋날 수 있다. 모든 변경 경로를 private 메서드로 모으고 위젯 테스트로 열기/지우기/닫기/재진입을 검증한다.
- **dispose에서 Provider 갱신 시 생명주기 문제:** 테스트에서 Riverpod 예외가 나면 검색 Provider를 `autoDispose` 형태의 `StateNotifierProvider.autoDispose`로 바꾸고 화면별 수명에 맡긴다.
- **기존 Provider 의미 변경에 따른 회귀:** `activeQuestsProvider`, `suggestedQuestsProvider`, `completedQuestsProvider`, `transactionsProvider`, `monthlySummaryProvider`를 수정하지 않고 새 파생 Provider만 추가하여 홈 요약, 보상, 차트가 검색 상태에 영향받지 않게 한다.
- **카테고리 집계와 검색 목록의 혼동:** `transactions`(원본/집계), 검색된 목록, 최종 카테고리 적용 목록의 변수명을 명확히 분리하고 테스트에서 검색 후 요약 금액이 그대로인지 추가 확인한다.
- **긴 목록 입력 성능:** 매 키 입력마다 O(n) 필터링한다. 로컬 데이터 규모에서 먼저 측정하고, 문제가 있을 때만 200~300ms debounce 또는 정규화 문자열 캐시를 별도 커밋으로 도입한다. 이번 구현에서 premature cache는 두지 않는다.
- **AppBar/TabBar 레이아웃 및 접근성:** 긴 한국어 힌트와 큰 글자 배율에서 overflow가 날 수 있다. 입력은 `AppBar.title`의 가용 폭 안에 두고 아이콘 툴팁, 최소 터치 영역, 키보드 제출/clear 동작을 위젯 테스트와 수동 점검으로 확인한다.
- **가맹점명 기대 차이:** 실제 `Transaction`에는 가맹점명 필드가 없음을 UI/테스트 데이터에서 명확히 하고 `memo`만 검색한다. 모델 확장은 별도 마이그레이션 작업으로 분리한다.

롤백은 검색 기능이 기존 저장 포맷과 모델을 바꾸지 않는다는 점을 이용한다. 문제가 생기면 화면의 검색 UI/검색 Provider 참조를 제거한 뒤 두 provider 파일의 신규 검색 Notifier·파생 Provider·순수 함수와 신규 테스트 두 파일만 되돌리면 된다. Hive adapter/typeId/box migration이나 사용자 데이터 복구는 필요 없다. 부분 롤백이 필요하면 거래 검색과 퀘스트 검색이 서로 독립된 Provider/UI이므로 도메인별 커밋을 각각 revert할 수 있다.

## 8. 순차 커밋 제안

총 4개 커밋으로 나눈다.

1. **`test: 검색 매칭 및 파생 provider 테스트 추가`** — `test/search_provider_test.dart`에 실패하는 단위/Provider 테스트를 먼저 추가한다.
2. **`feat: 퀘스트 검색 상태와 3탭 검색 UI 추가`** — `quest_provider.dart`, `quests_screen.dart` 및 퀘스트 위젯 테스트 부분을 구현한다. 기존 퀘스트 흐름 테스트까지 통과시킨다.
3. **`feat: 거래 검색과 카테고리 필터 조합 추가`** — `finance_provider.dart`, `finance_screen.dart` 및 거래 위젯 테스트 부분을 구현한다. 집계 불변과 기존 삭제 견고성 테스트까지 확인한다.
4. **`test: 검색 통합 회귀 및 접근성 시나리오 보강`** — 재진입 초기화, 동적 목록 변경, 좁은 화면 overflow, 툴팁/빈 상태 회귀를 보강하고 `flutter analyze`와 전체 `flutter test`를 통과시킨다.

각 기능 커밋이 독립적으로 revert 가능하도록 퀘스트와 거래 구현을 섞지 않는다. 첫 테스트 커밋을 엄격히 red 상태로 유지하는 워크플로가 저장소 정책과 맞지 않으면 1번 테스트를 2·3번 구현 커밋에 각각 포함하되, 최종 4개 논리 단계와 검증 순서는 유지한다.
