import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The instant "now" is evaluated at for progression snapshots and quest
/// completion timestamps alike, so both agree on which calendar day "today"
/// is. Like any Riverpod [Provider], the value this computes is cached until
/// invalidated — it does NOT call [DateTime.now] again on every read.
///
/// Production call sites that need a fresh, current instant (an app resume,
/// or the start of a quest-completion transaction) must call
/// `ref.invalidate(nowProvider)` immediately before reading it. Left alone,
/// a session spanning midnight would otherwise keep reporting yesterday's
/// snapshot, or stamp a completion with a stale cached instant.
///
/// Overridden with a fixed value (or a mutable closure) in widget tests for
/// determinism. Lives in its own file (rather than progression_provider.dart)
/// so quest_provider.dart can depend on it without a circular import;
/// progression_provider.dart re-exports it to preserve existing imports.
final nowProvider = Provider<DateTime>((ref) => DateTime.now());
