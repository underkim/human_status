import 'package:http/http.dart' as http;

import '../models/goal.dart';
import '../models/quest.dart';
import 'claude_goal_decomposition_source.dart';
import 'goal_decomposition_source.dart';
import 'storage_service.dart';

export 'goal_decomposition_source.dart';

class GoalService {
  final StorageService storage;
  final GoalDecompositionSource source;

  /// Passed through to a Claude-selected source; only ever set by tests so
  /// the API-key-triggered network call can be observed/mocked without a
  /// real request. Production code leaves this null.
  final http.Client? claudeHttpClient;

  GoalService({
    required this.storage,
    GoalDecompositionSource? source,
    this.claudeHttpClient,
  }) : source = source ?? LocalRuleGoalDecompositionSource();

  /// Breaks [goal] down into quests. Tries Claude first if an API key is
  /// configured, falling back to the local rule engine on any failure
  /// (network error, bad response, missing key) — same pattern as
  /// QuestRecommendationService.refreshIfNeeded. Returns an empty list
  /// (rather than throwing) if both sources fail, so the goal itself is
  /// still created even without generated quests.
  Future<List<Quest>> decompose(Goal goal, {int count = 4}) async {
    final stats = storage.getStats();
    final existingQuests = storage.getQuests();

    try {
      return await _activeSource().decompose(
        goal: goal,
        stats: stats,
        existingQuests: existingQuests,
        count: count,
      );
    } catch (_) {
      try {
        return await LocalRuleGoalDecompositionSource().decompose(
          goal: goal,
          stats: stats,
          existingQuests: existingQuests,
          count: count,
        );
      } catch (_) {
        return [];
      }
    }
  }

  GoalDecompositionSource _activeSource() {
    if (source is! LocalRuleGoalDecompositionSource) return source;
    final apiKey = storage.claudeApiKey;
    if (apiKey == null || apiKey.trim().isEmpty) return source;
    return ClaudeGoalDecompositionSource(
      apiKey: apiKey,
      httpClient: claudeHttpClient,
    );
  }

  /// Progress toward [goal], from 0.0 to 1.0. Financial goals (targetAmount
  /// set) are driven by currentAmount; other goals are driven by the
  /// completion ratio of quests linked to this goal via Quest.goalId.
  double progress(Goal goal, List<Quest> allQuests) {
    if (goal.targetAmount != null) {
      final target = goal.targetAmount!;
      if (target <= 0) return 0;
      return (goal.currentAmount / target).clamp(0, 1).toDouble();
    }

    final linked = allQuests.where((q) => q.goalId == goal.id).toList();
    if (linked.isEmpty) return 0;
    final completed = linked.where((q) => q.status == QuestStatus.completed).length;
    return completed / linked.length;
  }

  /// True when every quest linked to [goal] has been resolved (completed or
  /// dismissed) with at least one actually completed. Financial goals are
  /// never auto-completable this way — they complete via amount tracking
  /// (see checkFinancialGoalCompletion in GoalsNotifier).
  bool isAutoCompletable(Goal goal, List<Quest> allQuests) {
    if (goal.status != GoalStatus.active) return false;
    if (goal.targetAmount != null) return false;

    final linked = allQuests.where((q) => q.goalId == goal.id).toList();
    if (linked.isEmpty) return false;

    final anyCompleted = linked.any((q) => q.status == QuestStatus.completed);
    final allResolved = linked.every(
      (q) => q.status == QuestStatus.completed || q.status == QuestStatus.dismissed,
    );
    return anyCompleted && allResolved;
  }
}
