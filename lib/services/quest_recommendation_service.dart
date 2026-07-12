import '../models/quest.dart';
import '../models/user_profile.dart';
import 'claude_quest_suggestion_source.dart';
import 'quest_suggestion_source.dart';
import 'storage_service.dart';

export 'quest_suggestion_source.dart';

class QuestRecommendationService {
  final StorageService storage;
  final QuestSuggestionSource source;

  static const refreshInterval = Duration(hours: 24);

  QuestRecommendationService({
    required this.storage,
    QuestSuggestionSource? source,
  }) : source = source ?? LocalRuleQuestSuggestionSource();

  bool shouldRefresh(UserProfile profile) {
    final last = profile.lastQuestRefresh;
    if (last == null) return true;
    return DateTime.now().difference(last) >= refreshInterval;
  }

  /// Regenerates the "suggested" quest set if the refresh interval has
  /// elapsed since the last refresh. Un-adopted suggestions from the
  /// previous cycle are discarded. If a Claude API key is configured, quest
  /// generation is delegated to Claude and falls back to the local rule
  /// engine on any failure (network error, bad response, missing key).
  Future<void> refreshIfNeeded() async {
    final profile = storage.getProfile();
    if (!shouldRefresh(profile)) return;

    final staleSuggestions = storage
        .getQuests()
        .where((q) => q.status == QuestStatus.suggested)
        .toList();
    for (final q in staleSuggestions) {
      await storage.deleteQuest(q.id);
    }

    final stats = storage.getStats();
    final remainingQuests = storage.getQuests();

    List<Quest> suggestions;
    try {
      suggestions = await _activeSource(profile).generateSuggestions(
        stats: stats,
        existingQuests: remainingQuests,
      );
    } catch (_) {
      try {
        suggestions = await LocalRuleQuestSuggestionSource().generateSuggestions(
          stats: stats,
          existingQuests: remainingQuests,
        );
      } catch (_) {
        // Both the configured source and the local fallback failed (e.g. the
        // fallback was already the source that threw). Skip this refresh
        // cycle silently rather than let the exception reach main() and
        // block app startup; lastQuestRefresh is left untouched so the next
        // launch retries.
        return;
      }
    }

    for (final q in suggestions) {
      await storage.saveQuest(q);
    }

    profile.lastQuestRefresh = DateTime.now();
    await storage.saveProfile(profile);
  }

  /// Uses the caller-supplied [source] as-is when overridden (e.g. in
  /// tests). Otherwise picks Claude when an API key is configured, falling
  /// back to the local rule engine.
  QuestSuggestionSource _activeSource(UserProfile profile) {
    if (source is! LocalRuleQuestSuggestionSource) return source;
    final apiKey = profile.claudeApiKey;
    if (apiKey == null || apiKey.trim().isEmpty) return source;
    return ClaudeQuestSuggestionSource(apiKey: apiKey);
  }
}
