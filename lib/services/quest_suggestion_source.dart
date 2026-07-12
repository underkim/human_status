import 'package:uuid/uuid.dart';

import '../data/quest_templates.dart';
import '../models/quest.dart';
import '../models/stat.dart';

/// Pluggable source of quest suggestions. A local rule-based implementation
/// is used today; an AI-backed implementation (e.g. calling the Claude API,
/// see ClaudeQuestSuggestionSource) can be swapped in without touching any
/// calling code.
abstract class QuestSuggestionSource {
  Future<List<Quest>> generateSuggestions({
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  });
}

/// Generates suggestions from a curated local template bank, prioritizing
/// the user's weakest stats and avoiding recently seen/completed titles.
class LocalRuleQuestSuggestionSource implements QuestSuggestionSource {
  final Uuid _uuid;

  LocalRuleQuestSuggestionSource({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  @override
  Future<List<Quest>> generateSuggestions({
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  }) async {
    final statsByWeakest = [...stats]
      ..sort((a, b) => a.level.compareTo(b.level));

    final recentTitles = existingQuests
        .where((q) =>
            q.source == QuestSource.suggested ||
            q.status == QuestStatus.completed)
        .map((q) => q.title)
        .toSet();

    // One queue of eligible templates per stat, so we can round-robin across
    // stats (weakest first) instead of exhausting one stat before moving on.
    final templatesByStat = {
      for (final stat in statsByWeakest)
        stat.id: questTemplateBank
            .where((t) => t.statId == stat.id && !recentTitles.contains(t.title))
            .toList(),
    };

    final chosen = <QuestTemplate>[];
    final seenTitles = <String>{};
    var addedInPass = true;
    while (chosen.length < count && addedInPass) {
      addedInPass = false;
      for (final stat in statsByWeakest) {
        if (chosen.length >= count) break;
        final queue = templatesByStat[stat.id]!;
        while (queue.isNotEmpty) {
          final template = queue.removeAt(0);
          if (seenTitles.contains(template.title)) continue;
          seenTitles.add(template.title);
          chosen.add(template);
          addedInPass = true;
          break;
        }
      }
    }

    final now = DateTime.now();
    return chosen
        .map((t) => Quest(
              id: _uuid.v4(),
              title: t.title,
              description: t.description,
              statRewards: {t.statId: t.baseXp},
              difficulty: t.difficulty,
              status: QuestStatus.suggested,
              source: QuestSource.suggested,
              createdAt: now,
            ))
        .toList();
  }
}
