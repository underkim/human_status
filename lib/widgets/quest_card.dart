import 'package:flutter/material.dart';

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

  const QuestCard({
    super.key,
    required this.quest,
    required this.stats,
    this.actions = const [],
  });

  String _statName(String id) {
    for (final s in stats) {
      if (s.id == id) return '${s.icon} ${s.name}';
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
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
                Chip(
                  label: Text(difficultyLabel(quest.difficulty)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(quest.description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: quest.statRewards.entries
                  .map((e) => Chip(
                        label: Text('${_statName(e.key)} +${e.value.toInt()}XP'),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
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
