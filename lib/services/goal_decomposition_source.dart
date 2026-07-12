import 'package:uuid/uuid.dart';

import '../data/quest_templates.dart';
import '../models/goal.dart';
import '../models/quest.dart';
import '../models/stat.dart';

/// Pluggable source of quests that break a Goal down into actionable steps.
/// Mirrors QuestSuggestionSource's Claude-primary/local-fallback split (see
/// ClaudeGoalDecompositionSource / GoalService).
abstract class GoalDecompositionSource {
  Future<List<Quest>> decompose({
    required Goal goal,
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  });
}

/// Generates a bespoke "kick-off" quest referencing the goal's own title,
/// then fills the remainder from the curated template bank for the goal's
/// linked stat. Used when no Claude API key is configured, or as a fallback
/// if the Claude-backed source fails.
class LocalRuleGoalDecompositionSource implements GoalDecompositionSource {
  final Uuid _uuid;

  LocalRuleGoalDecompositionSource({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  @override
  Future<List<Quest>> decompose({
    required Goal goal,
    required List<Stat> stats,
    required List<Quest> existingQuests,
    int count = 4,
  }) async {
    final now = DateTime.now();
    final existingTitles = existingQuests.map((q) => q.title).toSet();

    final kickoff = Quest(
      id: _uuid.v4(),
      title: '"${goal.title}" 목표를 위한 첫 걸음 내딛기',
      description: '이 목표를 향해 오늘 할 수 있는 작은 행동을 하나 실행해보세요.',
      statRewards: {goal.statId: 20},
      difficulty: QuestDifficulty.easy,
      status: QuestStatus.active,
      source: QuestSource.manual,
      createdAt: now,
      goalId: goal.id,
    );

    final templates = questTemplateBank
        .where((t) => t.statId == goal.statId && !existingTitles.contains(t.title))
        .toList();

    final chosen = <Quest>[kickoff];
    for (final t in templates) {
      if (chosen.length >= count) break;
      chosen.add(Quest(
        id: _uuid.v4(),
        title: t.title,
        description: t.description,
        statRewards: {t.statId: t.baseXp},
        difficulty: t.difficulty,
        status: QuestStatus.active,
        source: QuestSource.manual,
        createdAt: now,
        goalId: goal.id,
      ));
    }

    return chosen;
  }
}
