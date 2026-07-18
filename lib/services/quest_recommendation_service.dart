import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/quest.dart';
import '../models/user_profile.dart';
import 'claude_quest_suggestion_source.dart';
import 'quest_suggestion_source.dart';
import 'storage_service.dart';

export 'quest_suggestion_source.dart';

class QuestRefreshRollbackException implements Exception {
  final Object refreshError;
  final StackTrace refreshStackTrace;
  final List<Object> rollbackErrors;

  const QuestRefreshRollbackException({
    required this.refreshError,
    required this.refreshStackTrace,
    required this.rollbackErrors,
  });

  @override
  String toString() =>
      'Quest refresh failed and rollback was incomplete: $refreshError '
      '(${rollbackErrors.length} rollback error(s))';
}

class QuestRecommendationService {
  static final Expando<_RefreshGate> _refreshGates = Expando<_RefreshGate>();

  final StorageService storage;
  final QuestSuggestionSource source;

  /// Passed through to a Claude-selected source; only ever set by tests so
  /// the API-key-triggered network call can be observed/mocked without a
  /// real request. Production code leaves this null.
  final http.Client? claudeHttpClient;

  static const refreshInterval = Duration(hours: 24);

  QuestRecommendationService({
    required this.storage,
    QuestSuggestionSource? source,
    this.claudeHttpClient,
  }) : source = source ?? LocalRuleQuestSuggestionSource();

  bool shouldRefresh(UserProfile profile) {
    final last = profile.lastQuestRefresh;
    if (last == null) return true;
    return DateTime.now().difference(last) >= refreshInterval;
  }

  /// Regenerates the "suggested" quest set if the refresh interval has
  /// elapsed since the last refresh. Un-adopted suggestions from the
  /// previous cycle are discarded, but only once a replacement batch has
  /// been generated successfully — a Claude timeout or other failure (with
  /// the local fallback also failing) leaves the prior suggestions intact
  /// rather than deleting them and coming back empty. If a Claude API key is
  /// configured, quest generation is delegated to Claude and falls back to
  /// the local rule engine on any failure (network error, timeout, bad
  /// response, missing key).
  Future<void> refreshIfNeeded() => _refreshGate.run(_refreshIfNeeded);

  _RefreshGate get _refreshGate => _refreshGates[storage] ??= _RefreshGate();

  Future<void> _refreshIfNeeded() async {
    final profile = storage.getProfile();
    if (!shouldRefresh(profile)) return;

    final allQuests = storage.getQuests();
    final staleSuggestions = allQuests
        .where((q) => q.status == QuestStatus.suggested)
        .toList();
    final remainingQuests = allQuests
        .where((q) => q.status != QuestStatus.suggested)
        .toList();

    final stats = storage.getStats();

    List<Quest> suggestions;
    try {
      suggestions = await _activeSource().generateSuggestions(
        stats: stats,
        // 직전 suggested 묶음도 생성 문맥에 포함해 제목·행동 패턴 반복을 막는다.
        // 저장 충돌 검증은 아래에서 실제로 유지할 remainingQuests만 사용한다.
        existingQuests: allQuests,
      );
      _validateSuggestions(suggestions, remainingQuests);
    } catch (_) {
      try {
        suggestions = await LocalRuleQuestSuggestionSource()
            .generateSuggestions(stats: stats, existingQuests: remainingQuests);
        _validateSuggestions(suggestions, remainingQuests);
      } catch (_) {
        // Both the configured source and the local fallback failed (e.g. the
        // fallback was already the source that threw). Skip this refresh
        // cycle silently rather than let the exception reach main() and
        // block app startup; lastQuestRefresh is left untouched so the next
        // launch retries. The previous suggestion batch is left untouched.
        return;
      }
    }

    final previousRefresh = profile.lastQuestRefresh;
    try {
      for (final q in staleSuggestions) {
        await storage.deleteQuest(q.id);
      }
      for (final q in suggestions) {
        await storage.saveQuest(q);
      }

      profile.lastQuestRefresh = DateTime.now();
      await storage.saveProfile(profile);
    } catch (refreshError, refreshStackTrace) {
      // Storage writes are individually atomic, but replacing a suggestion
      // batch spans several writes. Restore the complete previous batch when
      // any delete/save (including a write that throws after landing) fails.
      final rollbackErrors = <Object>[];
      for (final q in suggestions) {
        try {
          await storage.deleteQuest(q.id);
        } catch (error) {
          rollbackErrors.add(error);
        }
      }
      for (final q in staleSuggestions) {
        try {
          await storage.saveQuest(q);
        } catch (error) {
          rollbackErrors.add(error);
        }
      }
      profile.lastQuestRefresh = previousRefresh;
      try {
        await storage.saveProfile(profile);
      } catch (error) {
        rollbackErrors.add(error);
      }
      if (rollbackErrors.isNotEmpty) {
        throw QuestRefreshRollbackException(
          refreshError: refreshError,
          refreshStackTrace: refreshStackTrace,
          rollbackErrors: List.unmodifiable(rollbackErrors),
        );
      }
      Error.throwWithStackTrace(refreshError, refreshStackTrace);
    }
  }

  /// Uses the caller-supplied [source] as-is when overridden (e.g. in
  /// tests). Otherwise picks Claude when an API key is configured, falling
  /// back to the local rule engine.
  QuestSuggestionSource _activeSource() {
    if (source is! LocalRuleQuestSuggestionSource) return source;
    final apiKey = storage.claudeApiKey;
    if (apiKey == null || apiKey.trim().isEmpty) return source;
    return ClaudeQuestSuggestionSource(
      apiKey: apiKey,
      goals: storage.getGoals(),
      preferredStatId: storage.getProfile().preferredStatId,
      httpClient: claudeHttpClient,
    );
  }

  void _validateSuggestions(
    List<Quest> suggestions,
    List<Quest> existingQuests,
  ) {
    final reservedIds = existingQuests.map((quest) => quest.id).toSet();
    final seenIds = <String>{};
    for (final suggestion in suggestions) {
      if (suggestion.status != QuestStatus.suggested ||
          suggestion.source != QuestSource.suggested) {
        throw const FormatException(
          'Quest suggestion source returned a non-suggested quest',
        );
      }
      if (reservedIds.contains(suggestion.id) || !seenIds.add(suggestion.id)) {
        throw const FormatException(
          'Quest suggestion source returned a duplicate quest id',
        );
      }
    }
  }
}

class _RefreshGate {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() action) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!released.isCompleted) released.complete();
    });
  }
}
