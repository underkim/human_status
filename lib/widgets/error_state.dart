import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// 데이터를 못 불러왔거나 처리에 실패했을 때 쓰는 공용 인라인 배너.
/// 색만으로 오류임을 표시하지 않도록 아이콘+텍스트를 항상 함께 쓴다.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: colors.error),
        borderRadius: BorderRadius.circular(AppRadius.md),
        color: colors.error.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.error, size: AppIconSize.md),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: colors.error)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
