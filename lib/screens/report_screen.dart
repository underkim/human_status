import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/stat.dart';
import '../providers/finance_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../services/report_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';
import '../widgets/page_content_bounds.dart';

/// 주간/월간 활동 리포트 — 퀘스트·스텟·목표·재무를 한 기간 단위로 묶어
/// 직전 기간과 비교해준다. 매일의 개별 기록(통계 탭)과 달리 "이번 주가
/// 어땠는지"를 회고하는 화면.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ReportPeriod _period = ReportPeriod.weekly;

  String get _previousLabel => _period == ReportPeriod.weekly ? '지난주' : '지난달';

  String _periodLabel(PeriodReport report) {
    if (_period == ReportPeriod.monthly) {
      return DateFormat('yyyy년 M월').format(report.start);
    }
    final lastDay = report.end.subtract(const Duration(days: 1));
    final fmt = DateFormat('M.d');
    return '${fmt.format(report.start)} ~ ${fmt.format(lastDay)}';
  }

  @override
  Widget build(BuildContext context) {
    final quests = ref.watch(questsProvider);
    final goals = ref.watch(goalsProvider);
    final transactions = ref.watch(transactionsProvider);
    final stats = ref.watch(statsProvider);

    final now = DateTime.now();
    final (start, end) = ReportService.periodRange(_period, now);
    final (prevStart, prevEnd) = ReportService.periodRange(_period, now, periodsAgo: 1);
    final current = ReportService.build(
        quests: quests, goals: goals, transactions: transactions, start: start, end: end);
    final previous = ReportService.build(
        quests: quests, goals: goals, transactions: transactions, start: prevStart, end: prevEnd);
    // 주간은 하루 단위, 월간은 주 단위 버킷 — 한 달을 일 단위로 그리면 너무 촘촘하다.
    final chartData = _period == ReportPeriod.weekly
        ? ReportService.xpByDay(quests: quests, start: start, end: end)
        : ReportService.xpByWeek(quests: quests, start: start, end: end);

    return Scaffold(
      appBar: AppBar(title: const Text('리포트')),
      body: PageContentBounds(
        maxWidth: PageContentBounds.wide,
        child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Center(
            child: SegmentedButton<ReportPeriod>(
              segments: const [
                ButtonSegment(value: ReportPeriod.weekly, label: Text('주간')),
                ButtonSegment(value: ReportPeriod.monthly, label: Text('월간')),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SummaryCard(
            periodLabel: _periodLabel(current),
            current: current,
            previous: previous,
            previousLabel: _previousLabel,
          ),
          if (chartData.values.any((v) => v > 0)) ...[
            const SizedBox(height: AppSpacing.lg),
            _XpChartCard(period: _period, data: chartData),
          ],
          const SizedBox(height: AppSpacing.lg),
          _StatGrowthCard(current: current, stats: stats),
          const SizedBox(height: AppSpacing.lg),
          _FinanceCard(current: current, previous: previous, previousLabel: _previousLabel),
          if (current.completedGoalTitles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _CompletedGoalsCard(titles: current.completedGoalTitles),
          ],
        ],
      ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String periodLabel;
  final PeriodReport current;
  final PeriodReport previous;
  final String previousLabel;

  const _SummaryCard({
    required this.periodLabel,
    required this.current,
    required this.previous,
    required this.previousLabel,
  });

  @override
  Widget build(BuildContext context) {
    final questDelta = current.questsCompleted - previous.questsCompleted;
    final xpDelta = current.xpEarned - previous.xpEarned;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('요약', style: Theme.of(context).textTheme.titleMedium),
                Text(periodLabel, style: TextStyle(color: context.appColors.textMuted)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryNumber(label: '완료 퀘스트', value: '${current.questsCompleted}개'),
                _SummaryNumber(label: '획득 XP', value: formatNumber(current.xpEarned)),
                _SummaryNumber(label: '달성 목표', value: '${current.goalsCompleted}개'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '$previousLabel 대비 퀘스트 ${_signed(questDelta, '개')} · XP ${_signed(xpDelta, '')}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.appColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

String _signed(num delta, String suffix) {
  if (delta == 0) return '변화 없음';
  final rounded = delta.round();
  return rounded > 0 ? '+$rounded$suffix' : '$rounded$suffix';
}

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// 기간 내 XP 획득 추이 — 주간은 요일별, 월간은 주차별 막대.
class _XpChartCard extends StatelessWidget {
  final ReportPeriod period;
  final Map<DateTime, double> data;

  const _XpChartCard({required this.period, required this.data});

  String _label(int index) {
    if (period == ReportPeriod.weekly) {
      final day = data.keys.elementAt(index);
      return _weekdayLabels[(day.weekday - 1) % 7];
    }
    return '${index + 1}주';
  }

  @override
  Widget build(BuildContext context) {
    final maxXp = data.values.fold<double>(0, (a, b) => b > a ? b : a);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('XP 추이', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxXp <= 0 ? 10 : maxXp * 1.2,
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= data.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(_label(index),
                                style: Theme.of(context).textTheme.bodySmall),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: [
                    for (final (index, xp) in data.values.indexed)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: xp,
                            color: Theme.of(context).colorScheme.primary,
                            width: period == ReportPeriod.weekly ? 18 : 28,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
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

class _SummaryNumber extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryNumber({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.dataMedium(weight: FontWeight.bold)),
      ],
    );
  }
}

class _StatGrowthCard extends StatelessWidget {
  final PeriodReport current;
  final List<Stat> stats;

  const _StatGrowthCard({required this.current, required this.stats});

  @override
  Widget build(BuildContext context) {
    final entries = current.xpByStat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    String statLabel(String statId) {
      for (final s in stats) {
        if (s.id == statId) return '${s.icon} ${s.name}';
      }
      return statId;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('스텟 성장', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (entries.isEmpty)
              Text(
                '이 기간에 완료한 퀘스트가 없어요.',
                style: TextStyle(color: context.appColors.textMuted),
              )
            else
              ...entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(statLabel(e.key)),
                        Text(
                          '+${formatNumber(e.value)} XP',
                          style: AppTypography.dataSmall(weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _FinanceCard extends StatelessWidget {
  final PeriodReport current;
  final PeriodReport previous;
  final String previousLabel;

  const _FinanceCard({
    required this.current,
    required this.previous,
    required this.previousLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasAny =
        current.income != 0 || current.expense != 0 || previous.income != 0 || previous.expense != 0;
    final expenseDelta = current.expense - previous.expense;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('재무', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (!hasAny)
              Text('이 기간에 기록된 거래가 없어요.', style: TextStyle(color: colors.textMuted))
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MoneyStat(label: '수입', value: current.income, color: colors.success),
                  _MoneyStat(label: '지출', value: current.expense, color: colors.error),
                  _MoneyStat(
                      label: '순저축',
                      value: current.net,
                      color: Theme.of(context).colorScheme.primary),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                expenseDelta == 0
                    ? '$previousLabel과 지출이 같아요'
                    : expenseDelta > 0
                        ? '$previousLabel보다 ${formatWon(expenseDelta)} 더 썼어요'
                        : '$previousLabel보다 ${formatWon(-expenseDelta)} 덜 썼어요',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
              if (current.topExpenseCategory != null)
                Text(
                  '최다 지출: ${current.topExpenseCategory} (${formatWon(current.topExpenseAmount)})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MoneyStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MoneyStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(formatWonCompact(value),
            style: AppTypography.dataMedium(color: color, weight: FontWeight.bold)),
      ],
    );
  }
}

class _CompletedGoalsCard extends StatelessWidget {
  final List<String> titles;

  const _CompletedGoalsCard({required this.titles});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('달성한 목표', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            ...titles.map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      const Text('🏆'),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(t)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
