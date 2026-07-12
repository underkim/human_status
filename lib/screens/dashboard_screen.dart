import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../widgets/quest_card.dart';
import '../widgets/stat_bar.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final overallLevel = ref.watch(overallLevelProvider);
    final activeQuests = ref.watch(activeQuestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Human Status')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('종합 레벨', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Lv.$overallLevel',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('스텟', style: Theme.of(context).textTheme.titleLarge),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: stats.map((s) => StatBar(stat: s)).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('진행중인 퀘스트', style: Theme.of(context).textTheme.titleLarge),
              Text('${activeQuests.length}개'),
            ],
          ),
          if (activeQuests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('진행중인 퀘스트가 없어요. 퀘스트 탭에서 추가해보세요.'),
            )
          else
            ...activeQuests.take(3).map((q) => QuestCard(quest: q, stats: stats)),
        ],
      ),
    );
  }
}
