import 'package:flutter/material.dart';

import '../data/achievement_definitions.dart';

Future<void> showAchievementDialog(
  BuildContext context,
  List<AchievementDefinition> newAchievements,
) async {
  if (newAchievements.isEmpty) return;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('🏆 업적 달성!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: newAchievements.map((a) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(a.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(a.description),
                    ],
                  ),
                ),
              ],
            ),
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
