import 'dart:async';

import 'financial_advisor_service.dart';
import 'quest_recommendation_service.dart';
import 'recurring_quest_service.dart';
import 'storage_service.dart';

/// Drives the daily state refresh (recurring-quest respawn, quest
/// recommendations, financial advice) both at app startup and whenever the
/// app resumes from the background. A resume only needs to redo this work
/// once the local calendar date has actually advanced past the last
/// *successfully completed* run — repeated same-day resumes are no-ops, and
/// overlapping calls (e.g. two resume events firing before the first
/// finishes) share a single in-flight run instead of duplicating it.
///
/// Two subtleties this class exists to handle:
///  - If a resume lands while a previous day's refresh is still running
///    (e.g. a 23:59 refresh still in flight when midnight passes and the app
///    resumes again), that resume must not just piggyback on the stale
///    in-flight run — it needs the new day's refresh to run once the first
///    finishes, without ever running two refreshes concurrently.
///  - If the local recurring-quest step fails, the day must not be recorded
///    as successfully refreshed, so the *next* same-day resume retries it.
///    Recommendation/advice failures are isolated but don't block that
///    day-completed marker — both services already fall back internally, so
///    treating a residual failure there as "retry forever" would just spin.
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

  /// The last local day the pipeline completed with the recurring-quest step
  /// succeeding. Null (or a day before today) means today is still due.
  DateTime? _lastCompletedDay;

  /// The currently-running refresh, and the local day it was started for.
  Future<void>? _inFlight;
  DateTime? _inFlightDay;

  /// Set while a refresh is in flight for an earlier day than a resume that
  /// just arrived: exactly one follow-up run for [_pendingDay] is chained
  /// after the in-flight run finishes, no matter how many resumes race in
  /// asking for it in the meantime.
  DateTime? _pendingDay;
  Future<void>? _pendingFuture;

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  /// True on the very first call, and again once the local calendar date has
  /// moved past the last successfully-completed refresh.
  bool get isDueForRefresh {
    final today = _dayOf(clock());
    return _lastCompletedDay == null || _lastCompletedDay!.isBefore(today);
  }

  /// Runs the refresh pipeline if due. The local day is captured once at the
  /// top of this call so every decision below is consistent about which day
  /// it's reasoning about, even if the wall clock ticks over mid-call.
  Future<void> refreshIfDue() {
    final today = _dayOf(clock());

    final inFlight = _inFlight;
    if (inFlight != null) {
      if (_inFlightDay != null && !_inFlightDay!.isBefore(today)) {
        // The running refresh already covers today (or a day at/after it) —
        // merge into it instead of starting a second one.
        return inFlight;
      }
      // The in-flight refresh started on an earlier day than this resume.
      // Chain exactly one follow-up run for `today` after it finishes;
      // further calls that arrive before it fires just update which day
      // that follow-up targets.
      _pendingDay = today;
      return _pendingFuture ??= inFlight.then((_) {
        final day = _pendingDay!;
        _pendingDay = null;
        _pendingFuture = null;
        return _startRun(day);
      });
    }

    if (_lastCompletedDay != null && !_lastCompletedDay!.isBefore(today)) {
      return Future.value();
    }

    return _startRun(today);
  }

  Future<void> _startRun(DateTime day) {
    _inFlightDay = day;
    final future = _runRefresh(day);
    _inFlight = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_inFlight, future)) {
          _inFlight = null;
          _inFlightDay = null;
        }
      }),
    );
    return future;
  }

  /// Each step is isolated in its own try/catch: a failing service (network
  /// error, bad local state, whatever) must not stop the remaining steps or
  /// let an exception escape into the caller (the app lifecycle callback).
  /// Only the recurring-quest step's success gates marking [day] as done —
  /// recommendation/advice already have their own internal fallbacks, so a
  /// residual failure there is treated as handled rather than retried.
  Future<void> _runRefresh(DateTime day) async {
    var recurringSucceeded = false;
    try {
      await _respawnRecurringQuests(day);
      recurringSucceeded = true;
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

    if (recurringSucceeded) {
      _lastCompletedDay = day;
    }
  }
}
