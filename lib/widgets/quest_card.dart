import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';

String difficultyLabel(QuestDifficulty d) => switch (d) {
      QuestDifficulty.easy => '쉬움',
      QuestDifficulty.medium => '보통',
      QuestDifficulty.hard => '어려움',
    };

class QuestCard extends StatelessWidget {
  final Quest quest;
  final List<Stat> stats;
  final List<Widget> actions;
  final List<Goal> goals;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const QuestCard({
    super.key,
    required this.quest,
    required this.stats,
    this.actions = const [],
    this.goals = const [],
    this.onEdit,
    this.onDelete,
  });

  String _statName(String id) {
    for (final s in stats) {
      if (s.id == id) return '${s.icon} ${s.name}';
    }
    return id;
  }

  Goal? _linkedGoal() {
    if (quest.goalId == null) return null;
    for (final g in goals) {
      if (g.id == quest.goalId) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final goal = _linkedGoal();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quest.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (goal != null) ...[
                  Chip(
                    avatar: const Icon(Icons.flag, size: 14),
                    label: Text(goal.title),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  const SizedBox(width: 6),
                ],
                Chip(
                  label: Text(difficultyLabel(quest.difficulty)),
                  visualDensity: VisualDensity.compact,
                ),
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    tooltip: '더보기',
                    onSelected: (v) {
                      if (v == 'edit') onEdit?.call();
                      if (v == 'delete') onDelete?.call();
                    },
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        const PopupMenuItem(value: 'edit', child: Text('수정')),
                      if (onDelete != null)
                        const PopupMenuItem(value: 'delete', child: Text('삭제')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(quest.description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (quest.isRecurring)
                  const Chip(
                    label: Text('🔁 매일 반복'),
                    visualDensity: VisualDensity.compact,
                  ),
                ...quest.statRewards.entries.map((e) => Chip(
                      label: Text('${_statName(e.key)} +${e.value.toInt()}XP'),
                      visualDensity: VisualDensity.compact,
                    )),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
