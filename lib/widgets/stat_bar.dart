import 'package:flutter/material.dart';

import '../models/stat.dart';
import '../services/xp_service.dart';

class StatBar extends StatelessWidget {
  final Stat stat;

  const StatBar({super.key, required this.stat});

  @override
  Widget build(BuildContext context) {
    final progress = XpService.progress(stat);
    final needed = XpService.xpToNextLevel(stat.level).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(stat.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stat.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('Lv.${stat.level}', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${stat.currentXp.toInt()} / $needed XP',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
