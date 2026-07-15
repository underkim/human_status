import 'dart:async';

import 'financial_advisor_service.dart';
import 'quest_recommendation_service.dart';
import 'recurring_quest_service.dart';
import 'storage_service.dart';

/// Drives the daily state refresh (recurring-quest respawn, quest
/// recommendations, financial advice) both at app startup and whenever the
/// app resumes from the background. A resume only needs to redo this work
/// once the local calendar date has actually advanced past the last run —
/// repeated same-day resumes are no-ops, and overlapping calls (e.g. two
/// resume events firing before the first finishes) share a single in-flight
/// run instead of duplicating it.
class DailyRefreshController {
  DailyRefreshController({
    required StorageService storage,
    DateTime Function()? clock,
    Future<void> Function(DateTime now)? respawnRecurringQuests,
    Future<void> Function()? refreshRecommendations,
    Future<void> Function()? refreshFinancialAdvice,
    this.onQuestsChanged,
    this.onAdviceChanged,
  }) : clock = clock ?? DateTime.now,
       _respawnRecurringQuests =
           respawnRecurringQuests ??
           ((now) =>
               RecurringQuestService(storage: storage).respawnDue(now: now)),
       _refreshRecommendations =
           refreshRecommendations ??
           (() =>
               QuestRecommendationService(storage: storage).refreshIfNeeded()),
       _refreshFinancialAdvice =
           refreshFinancialAdvice ??
           (() => FinancialAdvisorService(storage: storage).refreshIfNeeded());

  final DateTime Function() clock;
  final Future<void> Function(DateTime now) _respawnRecurringQuests;
  final Future<void> Function() _refreshRecommendations;
  final Future<void> Function() _refreshFinancialAdvice;

  /// Invoked after a step touches quest state, so callers can poke their
  /// quest provider/notifier to reload.
  final void Function()? onQuestsChanged;

  /// Invoked after the financial-advice step runs, so callers can poke
  /// their advice provider/notifier to reload.
  final void Function()? onAdviceChanged;

  DateTime? _lastRefreshDay;
  Future<void>? _inFlight;

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  /// True on the very first call, and again once the local calendar date has
  /// moved past whatever day the last refresh started on.
  bool get isDueForRefresh {
    final today = _dayOf(clock());
    return _lastRefreshDay == null || _lastRefreshDay!.isBefore(today);
  }

  /// Runs the refresh pipeline if [isDueForRefresh]. The due-check and the
  /// day marker update happen synchronously (no `await` between them), so
  /// calls that race in back-to-back — same-day repeats or genuinely
  /// concurrent resume events — see the marker already updated and reuse the
  /// same in-flight future rather than starting a second run.
  Future<void> refreshIfDue() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (!isDueForRefresh) return Future.value();

    _lastRefreshDay = _dayOf(clock());
    final future = _runRefresh();
    _inFlight = future;
    unawaited(future.whenComplete(() => _inFlight = null));
    return future;
  }

  /// Each step is isolated in its own try/catch: a failing service (network
  /// error, bad local state, whatever) must not stop the remaining steps or
  /// let an exception escape into the caller (the app lifecycle callback).
  Future<void> _runRefresh() async {
    try {
      await _respawnRecurringQuests(clock());
      onQuestsChanged?.call();
    } catch (_) {}

    try {
      await _refreshRecommendations();
      onQuestsChanged?.call();
    } catch (_) {}

    try {
      await _refreshFinancialAdvice();
      onAdviceChanged?.call();
    } catch (_) {}
  }
}
