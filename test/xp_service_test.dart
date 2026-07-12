import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/stat.dart';
import 'package:human_status/services/xp_service.dart';

void main() {
  group('XpService.applyXp', () {
    test('accumulates xp without leveling up when below threshold', () {
      final stat = Stat(id: 'health', name: '체력', icon: '💪');
      final result = XpService.applyXp(stat, 50);

      expect(result.leveledUp, isFalse);
      expect(result.levelsGained, 0);
      expect(stat.level, 1);
      expect(stat.currentXp, 50);
    });

    test('levels up once when xp meets the threshold exactly', () {
      final stat = Stat(id: 'health', name: '체력', icon: '💪');
      final result = XpService.applyXp(stat, 100);

      expect(result.leveledUp, isTrue);
      expect(result.levelsGained, 1);
      expect(stat.level, 2);
      expect(stat.currentXp, 0);
    });

    test('rolls over multiple level-ups from a single large xp gain', () {
      final stat = Stat(id: 'health', name: '체력', icon: '💪');
      // level 1->2 costs 100, level 2->3 costs 200: 100+200=300 exactly clears two levels.
      final result = XpService.applyXp(stat, 300);

      expect(result.leveledUp, isTrue);
      expect(result.levelsGained, 2);
      expect(stat.level, 3);
      expect(stat.currentXp, 0);
    });

    test('ignores non-positive xp', () {
      final stat = Stat(id: 'health', name: '체력', icon: '💪');
      final result = XpService.applyXp(stat, 0);

      expect(result.leveledUp, isFalse);
      expect(stat.currentXp, 0);
    });
  });

  group('XpService.overallLevel', () {
    test('returns 1 for an empty stat list', () {
      expect(XpService.overallLevel([]), 1);
    });

    test('floors the average of stat levels', () {
      final stats = [
        Stat(id: 'a', name: 'A', icon: '', level: 1),
        Stat(id: 'b', name: 'B', icon: '', level: 2),
        Stat(id: 'c', name: 'C', icon: '', level: 4),
      ];
      // average = 7/3 = 2.33 -> floors to 2
      expect(XpService.overallLevel(stats), 2);
    });
  });

  group('XpService.progress', () {
    test('returns fraction of xp toward next level', () {
      final stat = Stat(id: 'health', name: '체력', icon: '💪', currentXp: 25);
      expect(XpService.progress(stat), 0.25);
    });
  });
}
