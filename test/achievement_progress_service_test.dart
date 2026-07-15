import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/data/achievement_definitions.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/services/achievement_progress_service.dart';
import 'package:uuid/uuid.dart';

Quest _completedQuest({String? goalId}) => Quest(
  id: const Uuid().v4(),
  title: 'q',
  description: '',
  statRewards: const {'health': 10},
  status: QuestStatus.completed,
  goalId: goalId,
  createdAt: DateTime(2026, 1, 1),
  completedAt: DateTime(2026, 1, 1),
);

Goal _goal({
  required GoalStatus status,
  double? targetAmount,
  double currentAmount = 0,
}) => Goal(
  id: const Uuid().v4(),
  title: 'g',
  description: '',
  statId: 'wealth',
  status: status,
  targetAmount: targetAmount,
  currentAmount: currentAmount,
  createdAt: DateTime(2026, 1, 1),
);

AchievementContext _ctx({
  List<Stat> stats = const [],
  List<Quest> completedQuests = const [],
  int streak = 0,
  int overallLevel = 1,
  List<Goal> goals = const [],
}) => AchievementContext(
  stats: stats,
  completedQuests: completedQuests,
  streak: streak,
  overallLevel: overallLevel,
  goals: goals,
);

void main() {
  group(
    'measureAchievementProgress — count/streak/stat/goal parity with unlock thresholds',
    () {
      test(
        'first_quest reaches ratio 1.0 exactly when isUnlocked flips true',
        () {
          final def = achievementDefinitions.firstWhere(
            (d) => d.id == 'first_quest',
          );
          final below = _ctx(completedQuests: []);
          final at = _ctx(completedQuests: [_completedQuest()]);
          expect(measureAchievementProgress('first_quest', below)!.ratio, 0);
          expect(def.isUnlocked(below), isFalse);
          expect(measureAchievementProgress('first_quest', at)!.ratio, 1.0);
          expect(def.isUnlocked(at), isTrue);
        },
      );

      test(
        'quests_10/quests_50 track completed-quest count against threshold',
        () {
          final nine = _ctx(
            completedQuests: List.generate(9, (_) => _completedQuest()),
          );
          final ten = _ctx(
            completedQuests: List.generate(10, (_) => _completedQuest()),
          );
          expect(
            measureAchievementProgress('quests_10', nine)!.ratio,
            closeTo(0.9, 1e-9),
          );
          expect(measureAchievementProgress('quests_10', ten)!.ratio, 1.0);
          expect(
            measureAchievementProgress('quests_50', ten)!.ratio,
            closeTo(0.2, 1e-9),
          );
        },
      );

      test('quest-count progress never overshoots 1.0 past the threshold', () {
        final over = _ctx(
          completedQuests: List.generate(15, (_) => _completedQuest()),
        );
        final progress = measureAchievementProgress('quests_10', over)!;
        expect(progress.ratio, 1.0);
        expect(progress.current, progress.target);
      });

      test(
        'streak_3/streak_7 read ctx.streak directly, matching isUnlocked',
        () {
          final streak3 = achievementDefinitions.firstWhere(
            (d) => d.id == 'streak_3',
          );
          final ctx = _ctx(streak: 3);
          expect(measureAchievementProgress('streak_3', ctx)!.ratio, 1.0);
          expect(streak3.isUnlocked(ctx), isTrue);

          final almost = _ctx(streak: 6);
          expect(
            measureAchievementProgress('streak_7', almost)!.ratio,
            closeTo(6 / 7, 1e-9),
          );
        },
      );

      test('any_stat_lv5 uses the max stat level', () {
        final ctx = _ctx(
          stats: [
            Stat(id: 'health', name: 'h', icon: '❤', level: 3),
            Stat(id: 'mental', name: 'm', icon: '🧠', level: 5),
          ],
        );
        final progress = measureAchievementProgress('any_stat_lv5', ctx)!;
        expect(progress.ratio, 1.0);
        final def = achievementDefinitions.firstWhere(
          (d) => d.id == 'any_stat_lv5',
        );
        expect(def.isUnlocked(ctx), isTrue);
      });

      test(
        'all_stats_lv2 uses the min stat level and excludes when no stats exist',
        () {
          final ctx = _ctx(
            stats: [
              Stat(id: 'health', name: 'h', icon: '❤', level: 2),
              Stat(id: 'mental', name: 'm', icon: '🧠', level: 1),
            ],
          );
          expect(
            measureAchievementProgress('all_stats_lv2', ctx)!.ratio,
            closeTo(0.5, 1e-9),
          );
          expect(
            measureAchievementProgress('all_stats_lv2', _ctx(stats: [])),
            isNull,
          );
        },
      );

      test('overall_lv5 tracks ctx.overallLevel', () {
        final ctx = _ctx(overallLevel: 5);
        expect(measureAchievementProgress('overall_lv5', ctx)!.ratio, 1.0);
        final def = achievementDefinitions.firstWhere(
          (d) => d.id == 'overall_lv5',
        );
        expect(def.isUnlocked(ctx), isTrue);
      });

      test('first_goal_set counts all goals regardless of status', () {
        final ctx = _ctx(goals: [_goal(status: GoalStatus.active)]);
        expect(measureAchievementProgress('first_goal_set', ctx)!.ratio, 1.0);
      });

      test(
        'first_goal_completed/goals_completed_5 count only completed goals',
        () {
          final ctx = _ctx(
            goals: [
              _goal(status: GoalStatus.active),
              _goal(status: GoalStatus.completed),
            ],
          );
          expect(
            measureAchievementProgress('first_goal_completed', ctx)!.ratio,
            1.0,
          );
          expect(
            measureAchievementProgress('goals_completed_5', ctx)!.ratio,
            closeTo(0.2, 1e-9),
          );
        },
      );

      test(
        'financial_goal_reached is always excluded (null), even at 100% of an active goal',
        () {
          // An active financial goal sitting exactly at its target would
          // report ratio 1.0 if measured continuously — but isUnlocked
          // requires GoalStatus.completed, so that active goal does NOT
          // unlock the achievement. Reporting 100% here would contradict
          // isUnlocked's own threshold, so this must stay null regardless
          // of how close (or exactly at) target an active goal sits.
          final atTarget = _ctx(
            goals: [
              _goal(
                status: GoalStatus.active,
                targetAmount: 500,
                currentAmount: 500,
              ),
            ],
          );
          final def = achievementDefinitions.firstWhere(
            (d) => d.id == 'financial_goal_reached',
          );
          expect(def.isUnlocked(atTarget), isFalse);
          expect(
            measureAchievementProgress('financial_goal_reached', atTarget),
            isNull,
          );
        },
      );

      test(
        'financial_goal_reached stays excluded with no goals, and once truly completed',
        () {
          expect(
            measureAchievementProgress(
              'financial_goal_reached',
              _ctx(goals: []),
            ),
            isNull,
          );

          final completed = _ctx(
            goals: [
              _goal(
                status: GoalStatus.completed,
                targetAmount: 100,
                currentAmount: 100,
              ),
            ],
          );
          final def = achievementDefinitions.firstWhere(
            (d) => d.id == 'financial_goal_reached',
          );
          expect(def.isUnlocked(completed), isTrue);
          // Even where isUnlocked is actually true, this stays null — a
          // just-unlocked achievement is filtered out by the unlockedIds
          // set at the computeNextAchievementProgress layer, not by this
          // per-achievement measurement.
          expect(
            measureAchievementProgress('financial_goal_reached', completed),
            isNull,
          );
        },
      );

      test('unrecognized id returns null', () {
        expect(measureAchievementProgress('does_not_exist', _ctx()), isNull);
      });
    },
  );

  group('computeNextAchievementProgress', () {
    test('selects the locked achievement with the highest clamped ratio', () {
      final ctx = _ctx(
        completedQuests: List.generate(
          9,
          (_) => _completedQuest(),
        ), // quests_10 -> 0.9
        streak: 1, // streak_3 -> 0.33
      );
      final next = computeNextAchievementProgress(ctx, {'first_quest'});
      expect(next!.definition.id, 'quests_10');
      expect(next.ratio, closeTo(0.9, 1e-9));
    });

    test('ties break by achievementDefinitions order', () {
      // Every measurable achievement sits at ratio 0 (overallLevel forced to
      // 0 so overall_lv5 doesn't win outright); first_quest appears first in
      // achievementDefinitions among the tied candidates.
      final ctx = _ctx(overallLevel: 0);
      final next = computeNextAchievementProgress(ctx, {});
      expect(next!.definition.id, 'first_quest');
    });

    test('excludes already-unlocked achievements from selection', () {
      final ctx = _ctx(completedQuests: [_completedQuest()]);
      final next = computeNextAchievementProgress(ctx, {'first_quest'});
      expect(next!.definition.id, isNot('first_quest'));
    });

    test(
      'excludes financial_goal_reached from candidates when unmeasurable',
      () {
        final ctx = _ctx(); // no goals at all
        final next = computeNextAchievementProgress(ctx, {});
        expect(next, isNotNull);
        expect(next!.definition.id, isNot('financial_goal_reached'));
      },
    );

    test(
      'never selects financial_goal_reached even with an active goal sitting at its target',
      () {
        final ctx = _ctx(
          goals: [
            _goal(
              status: GoalStatus.active,
              targetAmount: 500,
              currentAmount: 500,
            ),
          ],
        );
        final next = computeNextAchievementProgress(ctx, {});
        expect(next, isNotNull);
        expect(next!.definition.id, isNot('financial_goal_reached'));
      },
    );

    test('returns null once every measurable achievement is unlocked', () {
      final allIds = achievementDefinitions.map((d) => d.id).toSet();
      final ctx = _ctx();
      final next = computeNextAchievementProgress(ctx, allIds);
      expect(next, isNull);
    });

    test('never mutates or marks anything — pure selection only', () {
      final ctx = _ctx(completedQuests: [_completedQuest()]);
      final before = Set<String>.from({'first_quest'});
      computeNextAchievementProgress(ctx, before);
      expect(before, {'first_quest'});
    });
  });
}
