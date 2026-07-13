import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// 목록에 콘텐츠가 없을 때 공용으로 쓰는 안내 위젯. 화면마다 각자
/// "~가 없어요" 문구와 버튼을 새로 짜지 않도록 여기서 한 번만 정의한다.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onCta, child: Text(ctaLabel!)),
          ],
        ],
      ),
    );
  }
}
