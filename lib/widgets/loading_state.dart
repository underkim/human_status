import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// 짧은 비동기 작업(추천 갱신, 코칭 카드 분석 등) 중임을 알리는 공용 인라인
/// 로딩 표시. 화면 전체를 덮는 로딩과 달리 나머지 콘텐츠는 그대로 둔 채
/// 한 줄만 보여줄 때 쓴다.
class LoadingState extends StatelessWidget {
  final String? message;

  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          if (message != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
