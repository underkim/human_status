import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';

String difficultyLabel(QuestDifficulty d) => switch (d) {
  QuestDifficulty.easy => '쉬움',
  QuestDifficulty.medium => '보통',
  QuestDifficulty.hard => '어려움',
};

/// 버튼 안 스피너 자리를 대신하는 접근성 있는 진행중 표시 — 스피너 자체는
/// 별도로 말해줄 의미 있는 정보가 없으므로 [label] 하나만 읽히도록
/// excludeSemantics로 스피너의 기본 시맨틱스를 지운다(중복 낭독 방지).
Widget pendingActionIndicator(String label) {
  return Semantics(
    label: label,
    excludeSemantics: true,
    child: const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

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
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
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
            Text(
              quest.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
                ...quest.statRewards.entries.map(
                  (e) => Chip(
                    label: Text('${_statName(e.key)} +${e.value.toInt()}XP'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
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
