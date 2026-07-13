import 'package:flutter/material.dart';

import '../models/stat.dart';
import '../services/xp_service.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class StatBar extends StatelessWidget {
  final Stat stat;

  const StatBar({super.key, required this.stat});

  @override
  Widget build(BuildContext context) {
    final progress = XpService.progress(stat);
    final needed = XpService.xpToNextLevel(stat.level).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(stat.icon, style: const TextStyle(fontSize: AppIconSize.md)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  stat.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('Lv.${stat.level}', style: AppTypography.dataMedium()),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.xs / 2),
          Text(
            '${stat.currentXp.toInt()} / $needed XP',
            style: AppTypography.dataSmall(color: Theme.of(context).textTheme.bodySmall?.color),
          ),
        ],
      ),
    );
  }
}
