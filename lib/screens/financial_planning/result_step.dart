import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/financial_planning_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/formatters.dart';

/// 마법사의 "결과" 단계 — 추천 카드를 보여주고, 각 추천을 재무 목표로 만들
/// 수 있게 한다. 생성 중 상태(`_creatingGoalTitles`)는 이 단계 밖 어떤
/// 상태도 참조하지 않는 자기 완결적 흐름이라 이 위젯이 직접 소유한다.
class ResultStep extends ConsumerStatefulWidget {
  final bool retirementEnabled;
  final bool homePurchaseEnabled;

  const ResultStep({
    super.key,
    required this.retirementEnabled,
    required this.homePurchaseEnabled,
  });

  @override
  ConsumerState<ResultStep> createState() => _ResultStepState();
}

class _ResultStepState extends ConsumerState<ResultStep> {
  Set<String> _creatingGoalTitles = {};

  @override
  Widget build(BuildContext context) {
    final recommendations = ref.watch(planRecommendationsProvider);
    if (recommendations.isEmpty) {
      final message = (widget.retirementEnabled || widget.homePurchaseEnabled)
          ? '입력한 값으로는 계산할 수 없어요. 이전 단계로 돌아가 필수 항목을 확인해주세요.'
          : '선택한 목표가 없어요. 첫 단계에서 하나 이상 선택해주세요.';
      return Text(message);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: recommendations
          .map(
            (rec) => Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.goalTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text('목표 금액: ${formatWon(rec.requiredTargetAmount)}'),
                    Text('필요 월 저축액: ${formatWon(rec.requiredMonthlySaving)}'),
                    Text(
                      '최근 평균 월 저축액: ${formatWon(rec.currentAverageMonthlySaving)}',
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          rec.isOnTrack
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          color: rec.isOnTrack
                              ? context.appColors.success
                              : context.appColors.warning,
                          size: AppIconSize.md,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            rec.isOnTrack
                                ? '현재 페이스로 충분해요'
                                : '월 ${formatWon(rec.requiredMonthlySaving - rec.currentAverageMonthlySaving)} 더 모아야 해요',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _creatingGoalTitles.contains(rec.goalTitle)
                            ? null
                            : () async {
                                setState(
                                  () => _creatingGoalTitles = {
                                    ..._creatingGoalTitles,
                                    rec.goalTitle,
                                  },
                                );
                                try {
                                  await ref
                                      .read(financialPlanProvider.notifier)
                                      .createGoalFrom(rec);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '"${rec.goalTitle}" 목표가 생성되었어요.',
                                      ),
                                    ),
                                  );
                                } catch (_) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '목표를 생성하지 못했어요. 잠시 후 다시 시도해주세요.',
                                      ),
                                    ),
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(
                                      () => _creatingGoalTitles = {
                                        ..._creatingGoalTitles,
                                      }..remove(rec.goalTitle),
                                    );
                                  }
                                }
                              },
                        child: const Text('재무 목표로 만들기'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
