import 'package:flutter/material.dart';

import '../models/stat.dart';
import '../services/xp_service.dart';

Future<void> showLevelUpDialog(
  BuildContext context,
  List<Stat> stats,
  Map<String, LevelUpResult> results,
) async {
  final leveledUp = results.entries.where((e) => e.value.leveledUp).toList();
  if (leveledUp.isEmpty) return;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('🎉 레벨업!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: leveledUp.map((e) {
          final stat = stats.where((s) => s.id == e.key).isNotEmpty
              ? stats.firstWhere((s) => s.id == e.key)
              : null;
          final name = stat != null ? '${stat.icon} ${stat.name}' : e.key;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('$name 스텟이 Lv.${e.value.newLevel}(으)로 올랐습니다!'),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}
