import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';
import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../theme/app_spacing.dart';
import '../widgets/achievement_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/level_up_dialog.dart';
import '../widgets/page_content_bounds.dart';
import '../widgets/quest_card.dart';
import 'quest_form_screen.dart';

class QuestsScreen extends ConsumerStatefulWidget {
  const QuestsScreen({super.key});

  @override
  ConsumerState<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends ConsumerState<QuestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    // questSearchQueryProvider는 autoDispose라서 이 화면(그리고 파생
    // Provider들)을 아무도 watch하지 않게 되는 즉시 스스로 폐기되고, 다시
    // 들어오면 초기값('')부터 새로 시작한다 — 여기서 직접 clear()를
    // 호출하지 않는다. 이 State 자신이 그 provider의 구독자이므로,
    // unmount 도중 상태를 갱신하면 이미 defunct된 자신의 Element를
    // rebuild하려는 어서션 실패가 난다.
    super.dispose();
  }

  void _openSearch() {
    setState(() => _isSearching = true);
  }

  /// 검색 입력과 검색 모드를 함께 닫는다. controller와 provider를 항상 같이
  /// 정리해 둘의 상태가 어긋나지 않게 한다.
  void _closeSearch() {
    _searchController.clear();
    ref.read(questSearchQueryProvider.notifier).clear();
    setState(() => _isSearching = false);
  }

  /// 검색 모드는 유지한 채 검색어만 비운다 — 입력창의 지우기 버튼과 결과
  /// 없음 EmptyState의 CTA가 함께 쓰는 경로.
  void _clearSearchText() {
    _searchController.clear();
    ref.read(questSearchQueryProvider.notifier).clear();
  }

  void _onSearchChanged(String value) {
    ref.read(questSearchQueryProvider.notifier).setQuery(value);
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    final active = ref.watch(searchedActiveQuestsProvider);
    final suggested = ref.watch(searchedSuggestedQuestsProvider);
    final completed = ref.watch(searchedCompletedQuestsProvider);
    // 탭별 원본(검색 전) 목록 — 검색 결과가 0건일 때 "원본 자체가 없음"과
    // "검색으로 다 걸러짐"을 구분하는 데만 쓰인다.
    final activeOriginal = ref.watch(activeQuestsProvider);
    final suggestedOriginal = ref.watch(suggestedQuestsProvider);
    final completedOriginal = ref.watch(completedQuestsProvider);
    final goals = ref.watch(goalsProvider);
    final query = ref.watch(questSearchQueryProvider);
    final isSearching = query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '퀘스트 검색',
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : const Text('퀘스트'),
        actions: _isSearching
            ? [
                if (query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: AppIconSize.md),
                    tooltip: '검색어 지우기',
                    onPressed: _clearSearchText,
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: AppIconSize.md),
                  tooltip: '검색 닫기',
                  onPressed: _closeSearch,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search, size: AppIconSize.md),
                  tooltip: '퀘스트 검색',
                  onPressed: _openSearch,
                ),
              ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '진행중 (${active.length})'),
            Tab(text: '추천 (${suggested.length})'),
            Tab(text: '완료 (${completed.length})'),
          ],
        ),
      ),
      body: PageContentBounds(
        maxWidth: PageContentBounds.wide,
        child: TabBarView(
          controller: _tabController,
          children: [
            _ActiveTab(
              quests: active,
              stats: stats,
              goals: goals,
              isSearching: isSearching && activeOriginal.isNotEmpty,
              onClearSearch: _clearSearchText,
            ),
            _SuggestedTab(
              quests: suggested,
              stats: stats,
              goals: goals,
              isSearching: isSearching && suggestedOriginal.isNotEmpty,
              onClearSearch: _clearSearchText,
            ),
            _CompletedTab(
              quests: completed,
              stats: stats,
              goals: goals,
              isSearching: isSearching && completedOriginal.isNotEmpty,
              onClearSearch: _clearSearchText,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        // HomeShell의 IndexedStack은 모든 탭을 동시에 마운트해두므로, 기본
        // heroTag를 쓰면 이 화면 밖으로/안으로 라우트 전환이 일어날 때 다른
        // 탭의 FAB과 태그가 겹쳐 Hero 어서션이 발생한다 — 탭마다 고유
        // heroTag를 줘서 피한다.
        heroTag: 'quests_fab',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const QuestFormScreen())),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 진행중 탭 — 퀘스트별 완료/삭제 가드는 재빌드 이전(첫 await/확인창 이전)에
/// 동기적으로 세팅되어 연타를 막고, 진행 중인 동작은 스피너로, 그 외
/// 액션은 비활성화로 보여준다. goals_screen.dart의 `_GoalsListViewState`와
/// 같은 패턴.
class _ActiveTab extends ConsumerStatefulWidget {
  final List<Quest> quests;
  final List<Stat> stats;
  final List<Goal> goals;
  final bool isSearching;
  final VoidCallback onClearSearch;

  const _ActiveTab({
    required this.quests,
    required this.stats,
    required this.goals,
    required this.isSearching,
    required this.onClearSearch,
  });

  @override
  ConsumerState<_ActiveTab> createState() => _ActiveTabState();
}

class _ActiveTabState extends ConsumerState<_ActiveTab> {
  final Set<String> _completingQuests = {};
  final Set<String> _pendingDeletes = {};

  bool _isBusy(String id) =>
      _completingQuests.contains(id) || _pendingDeletes.contains(id);

  Future<void> _completeQuest(Quest quest) async {
    if (_isBusy(quest.id)) return;
    setState(() => _completingQuests.add(quest.id));
    try {
      final result = await ref
          .read(questsProvider.notifier)
          .completeQuest(quest.id);
      if (!mounted) return;
      // 다른 화면이 먼저 완료/삭제해 이 호출이 조용한 무결과였다면
      // (didComplete == false) 성공 UI를 띄우지 않는다.
      if (!result.didComplete) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${quest.title}" 완료!')));
      await showLevelUpDialog(
        context,
        ref.read(statsProvider),
        result.levelUps,
      );
      if (!mounted) return;
      await showAchievementDialog(context, result.newAchievements);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퀘스트 완료 처리에 실패했어요. 잠시 후 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _completingQuests.remove(quest.id));
    }
  }

  Future<void> _confirmDelete(Quest quest) async {
    // 확인창이 뜨기도 전에 같은 퀘스트를 빠르게 두 번 눌러도 확인창은 하나만
    // 뜨도록, 다이얼로그를 열기 직전에(첫 await 이전에 동기적으로) pending
    // 집합에 넣는다.
    if (_isBusy(quest.id)) return;
    setState(() => _pendingDeletes.add(quest.id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('퀘스트 삭제'),
          content: Text('"${quest.title}" 퀘스트를 삭제할까요? 되돌릴 수 없어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await ref.read(questsProvider.notifier).deleteQuest(quest.id);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('퀘스트를 삭제하지 못했어요. 잠시 후 다시 시도해주세요.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _pendingDeletes.remove(quest.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.quests.isEmpty) {
      if (widget.isSearching) {
        return EmptyState(
          icon: Icons.search_off,
          message: '검색 결과가 없어요.',
          ctaLabel: '검색어 지우기',
          onCta: widget.onClearSearch,
        );
      }
      return const EmptyState(
        icon: Icons.checklist_outlined,
        message: '진행중인 퀘스트가 없어요.\n오른쪽 아래 + 버튼으로 추가해보세요.',
      );
    }
    return ListView(
      children: widget.quests.map<Widget>((q) {
        final completing = _completingQuests.contains(q.id);
        final busy = _isBusy(q.id);
        return QuestCard(
          quest: q,
          stats: widget.stats,
          goals: widget.goals,
          onEdit: busy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QuestFormScreen(existing: q),
                  ),
                ),
          onDelete: busy ? null : () => _confirmDelete(q),
          actions: [
            FilledButton(
              onPressed: busy ? null : () => _completeQuest(q),
              child: completing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('완료'),
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// 추천 탭 — 퀘스트별 채택/무시 가드는 첫 await 이전에 동기적으로 세팅되어
/// 연타로 같은 퀘스트가 두 번 상태 전이되는 일을 막는다.
class _SuggestedTab extends ConsumerStatefulWidget {
  final List<Quest> quests;
  final List<Stat> stats;
  final List<Goal> goals;
  final bool isSearching;
  final VoidCallback onClearSearch;

  const _SuggestedTab({
    required this.quests,
    required this.stats,
    required this.goals,
    required this.isSearching,
    required this.onClearSearch,
  });

  @override
  ConsumerState<_SuggestedTab> createState() => _SuggestedTabState();
}

class _SuggestedTabState extends ConsumerState<_SuggestedTab> {
  final Set<String> _adoptingQuests = {};
  final Set<String> _dismissingQuests = {};

  bool _isBusy(String id) =>
      _adoptingQuests.contains(id) || _dismissingQuests.contains(id);

  Future<void> _adopt(Quest quest) async {
    if (_isBusy(quest.id)) return;
    setState(() => _adoptingQuests.add(quest.id));
    try {
      await ref.read(questsProvider.notifier).adoptSuggestion(quest.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퀘스트를 채택하지 못했어요. 잠시 후 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _adoptingQuests.remove(quest.id));
    }
  }

  Future<void> _dismiss(Quest quest) async {
    if (_isBusy(quest.id)) return;
    setState(() => _dismissingQuests.add(quest.id));
    try {
      await ref.read(questsProvider.notifier).dismissSuggestion(quest.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퀘스트를 무시하지 못했어요. 잠시 후 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _dismissingQuests.remove(quest.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.quests.isEmpty) {
      if (widget.isSearching) {
        return EmptyState(
          icon: Icons.search_off,
          message: '검색 결과가 없어요.',
          ctaLabel: '검색어 지우기',
          onCta: widget.onClearSearch,
        );
      }
      return const EmptyState(
        icon: Icons.auto_awesome_outlined,
        message: '추천 퀘스트가 없어요.\n하루가 지나면 새로운 추천이 생성돼요.',
      );
    }
    return ListView(
      children: widget.quests.map<Widget>((q) {
        final busy = _isBusy(q.id);
        final adopting = _adoptingQuests.contains(q.id);
        final dismissing = _dismissingQuests.contains(q.id);
        return QuestCard(
          quest: q,
          stats: widget.stats,
          goals: widget.goals,
          actions: [
            TextButton(
              onPressed: busy ? null : () => _dismiss(q),
              child: dismissing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('무시'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: busy ? null : () => _adopt(q),
              child: adopting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('채택'),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _CompletedTab extends StatelessWidget {
  final List<Quest> quests;
  final List<Stat> stats;
  final List<Goal> goals;
  final bool isSearching;
  final VoidCallback onClearSearch;

  const _CompletedTab({
    required this.quests,
    required this.stats,
    required this.goals,
    required this.isSearching,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    if (quests.isEmpty) {
      if (isSearching) {
        return EmptyState(
          icon: Icons.search_off,
          message: '검색 결과가 없어요.',
          ctaLabel: '검색어 지우기',
          onCta: onClearSearch,
        );
      }
      return const EmptyState(
        icon: Icons.task_alt_outlined,
        message: '아직 완료한 퀘스트가 없어요.',
      );
    }
    return ListView(
      children: quests
          .map<Widget>((q) => QuestCard(quest: q, stats: stats, goals: goals))
          .toList(),
    );
  }
}
