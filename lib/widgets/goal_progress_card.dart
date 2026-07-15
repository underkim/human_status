import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared progress card for a single goal — used by both the 목표 tab and
/// the 재무 tab's financial-goal list, which previously each hand-rolled a
/// near-identical title+progress-bar+amount card.
class GoalProgressCard extends StatelessWidget {
  final String title;
  final String? description;
  final double progress;
  final String trailingInfo;
  final String? statLabel;
  final String? targetDateLabel;
  final bool isCompleted;
  final VoidCallback? onComplete;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// 이 목표가 왜/어떻게 완료되는지 짧게 설명하는 캡션 — 금액이 차면
  /// 자동으로 완료되는 재무 목표와, 연결된 퀘스트를 다 마쳐야 수동으로
  /// "목표 달성" 버튼을 눌러야 하는 일반 목표가 겉보기엔 똑같은 카드라
  /// 구분이 안 됐던 것을 보완한다.
  final String? completionHint;

  const GoalProgressCard({
    super.key,
    required this.title,
    this.description,
    required this.progress,
    required this.trailingInfo,
    this.statLabel,
    this.targetDateLabel,
    this.isCompleted = false,
    this.onComplete,
    this.onEdit,
    this.onDelete,
    this.completionHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (statLabel != null)
                  Chip(label: Text(statLabel!), visualDensity: VisualDensity.compact),
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    tooltip: '더보기',
                    onSelected: (v) {
                      if (v == 'edit') onEdit?.call();
                      if (v == 'delete') onDelete?.call();
                    },
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        const PopupMenuItem(value: 'edit', child: Text('수정')),
                      if (onDelete != null)
                        const PopupMenuItem(value: 'delete', child: Text('삭제')),
                    ],
                  ),
              ],
            ),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(description!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: isCompleted ? colors.success : null,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(trailingInfo, style: theme.textTheme.bodySmall),
                if (targetDateLabel != null)
                  Text(
                    targetDateLabel!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: targetDateLabel!.startsWith('기한') ? colors.warning : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (completionHint != null) ...[
              const SizedBox(height: 2),
              Text(
                completionHint!,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted, fontSize: 11),
              ),
            ],
            if (onComplete != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: onComplete, child: const Text('목표 달성')),
              ),
            ],
            if (isCompleted) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: colors.success),
                  const SizedBox(width: AppSpacing.xs),
                  Text('달성 완료', style: theme.textTheme.bodySmall?.copyWith(color: colors.success)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
