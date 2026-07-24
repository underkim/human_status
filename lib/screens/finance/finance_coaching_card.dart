import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/financial_advisor_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/loading_state.dart';

String _adviceIcon(String category) => switch (category) {
  'spending' => '💸',
  'goal' => '🎯',
  'networth' => '📈',
  _ => '💡',
};

/// 재무 코칭 카드 — 데이터 없음 / 갱신 중 / 정상 세 상태를 명시적으로
/// 구분한다(이전엔 advice가 비어있으면 카드 자체가 조용히 사라졌음).
class CoachingCard extends ConsumerStatefulWidget {
  const CoachingCard({super.key});

  @override
  ConsumerState<CoachingCard> createState() => _CoachingCardState();
}

class _CoachingCardState extends ConsumerState<CoachingCard> {
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await ref.read(financialAdviceProvider.notifier).refreshNow();
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final advice = ref.watch(financialAdviceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('재무 코칭', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.refresh, size: AppIconSize.md),
                  tooltip: '새로고침',
                  onPressed: _isRefreshing ? null : _refresh,
                ),
              ],
            ),
            Text(
              '지출 패턴·목표 진도·순자산 추이를 분석해 알려드려요',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_isRefreshing)
              const LoadingState(message: '코칭 내용을 분석하고 있어요...')
            else if (advice.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text('아직 코칭 내용이 없어요. 새로고침 버튼을 눌러보세요.'),
              )
            else
              ...advice.map(
                (a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_adviceIcon(a.category)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(a.message)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
