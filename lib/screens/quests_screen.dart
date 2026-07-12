import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quest.dart';
import '../models/stat.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../widgets/achievement_dialog.dart';
import '../widgets/level_up_dialog.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _completeQuest(String id) async {
    final result = await ref.read(questsProvider.notifier).completeQuest(id);
    if (!mounted) return;
    await showLevelUpDialog(context, ref.read(statsProvider), result.levelUps);
    if (!mounted) return;
    await showAchievementDialog(context, result.newAchievements);
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    final active = ref.watch(activeQuestsProvider);
    final suggested = ref.watch(suggestedQuestsProvider);
    final completed = ref.watch(completedQuestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('퀘스트'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '진행중 (${active.length})'),
            Tab(text: '추천 (${suggested.length})'),
            Tab(text: '완료 (${completed.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ActiveTab(quests: active, stats: stats, onComplete: _completeQuest),
          _SuggestedTab(quests: suggested, stats: stats),
          _CompletedTab(quests: completed, stats: stats),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuestFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ActiveTab extends StatelessWidget {
  final List<Quest> quests;
  final List<Stat> stats;
  final Future<void> Function(String id) onComplete;

  const _ActiveTab({required this.quests, required this.stats, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    if (quests.isEmpty) {
      return const Center(child: Text('진행중인 퀘스트가 없어요.\n오른쪽 아래 + 버튼으로 추가해보세요.', textAlign: TextAlign.center));
    }
    return ListView(
      children: quests
          .map<Widget>((q) => QuestCard(
                quest: q,
                stats: stats,
                actions: [
                  FilledButton(
                    onPressed: () => onComplete(q.id),
                    child: const Text('완료'),
                  ),
                ],
              ))
          .toList(),
    );
  }
}

class _SuggestedTab extends ConsumerWidget {
  final List<Quest> quests;
  final List<Stat> stats;

  const _SuggestedTab({required this.quests, required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (quests.isEmpty) {
      return const Center(child: Text('추천 퀘스트가 없어요.\n하루가 지나면 새로운 추천이 생성돼요.', textAlign: TextAlign.center));
    }
    return ListView(
      children: quests
          .map<Widget>((q) => QuestCard(
                quest: q,
                stats: stats,
                actions: [
                  TextButton(
                    onPressed: () => ref.read(questsProvider.notifier).dismissSuggestion(q.id),
                    child: const Text('무시'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () => ref.read(questsProvider.notifier).adoptSuggestion(q.id),
                    child: const Text('채택'),
                  ),
                ],
              ))
          .toList(),
    );
  }
}

class _CompletedTab extends StatelessWidget {
  final List<Quest> quests;
  final List<Stat> stats;

  const _CompletedTab({required this.quests, required this.stats});

  @override
  Widget build(BuildContext context) {
    if (quests.isEmpty) {
      return const Center(child: Text('아직 완료한 퀘스트가 없어요.'));
    }
    return ListView(
      children: quests.map<Widget>((q) => QuestCard(quest: q, stats: stats)).toList(),
    );
  }
}
