import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_snapshot.dart';
import '../providers/asset_snapshot_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';
import '../widgets/empty_state.dart';

class AssetSnapshotListView extends ConsumerStatefulWidget {
  const AssetSnapshotListView({super.key});

  @override
  ConsumerState<AssetSnapshotListView> createState() =>
      _AssetSnapshotListViewState();
}

class _AssetSnapshotListViewState extends ConsumerState<AssetSnapshotListView> {
  // 스냅샷별 삭제 가드 — quests_screen.dart/goals_screen.dart의 _pendingDeletes와
  // 같은 패턴. 확인창이 뜨기도 전에(첫 await 이전에 동기적으로) pending
  // 집합에 넣어, 같은 항목을 빠르게 두 번 눌러도 확인창이 두 개 겹쳐 뜨지
  // 않도록 한다.
  final Set<String> _pendingDeletes = {};

  Future<void> _confirmDelete(String id, String dateLabel) async {
    if (_pendingDeletes.contains(id)) return;
    setState(() => _pendingDeletes.add(id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('자산현황 삭제'),
          content: Text('$dateLabel에 가져온 자산현황을 삭제할까요? 되돌릴 수 없어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref.read(assetSnapshotsProvider.notifier).deleteSnapshot(id);
    } finally {
      if (mounted) setState(() => _pendingDeletes.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = ref.watch(latestAssetSnapshotProvider);
    final snapshots = [...ref.watch(assetSnapshotsProvider)]
      ..sort((a, b) => b.importedAt.compareTo(a.importedAt));

    if (latest == null) {
      return const EmptyState(
        icon: Icons.account_balance_outlined,
        message: '아직 가져온 자산 현황이 없어요.\n재무 탭의 가져오기 버튼으로 뱅크샐러드 파일을 가져와보세요.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Text('순자산', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  formatWon(latest.netWorth),
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '자산 총합 − 부채 총합',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '가져온 날짜: ${latest.importedAt.toString().split(' ').first}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (snapshots.length >= 2) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('순자산 추이', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _NetWorthChart(
                snapshots: [...snapshots]
                  ..sort((a, b) => a.importedAt.compareTo(b.importedAt)),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('자산', style: Theme.of(context).textTheme.titleLarge),
        Card(
          child: Column(
            children: latest.assetsByCategory.entries
                .map(
                  (e) => ListTile(
                    title: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      formatWon(e.value),
                      style: AppTypography.dataMedium(),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        if (latest.liabilitiesByCategory.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('부채', style: Theme.of(context).textTheme.titleLarge),
          Card(
            child: Column(
              children: latest.liabilitiesByCategory.entries
                  .map(
                    (e) => ListTile(
                      title: Text(
                        e.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        formatWon(e.value),
                        style: AppTypography.dataMedium(),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('가져온 이력', style: Theme.of(context).textTheme.titleLarge),
            Text('${snapshots.length}건'),
          ],
        ),
        ...snapshots.map((s) {
          final dateLabel = s.importedAt.toString().split(' ').first;
          final deleting = _pendingDeletes.contains(s.id);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: ListTile(
              title: Text(dateLabel),
              subtitle: Text('순자산 ${formatWon(s.netWorth)}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: deleting
                    ? null
                    : () => _confirmDelete(s.id, dateLabel),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// 순자산 추이 라인 차트. 단일 시리즈라 범례 없이 섹션 제목이 이름을 대신하고,
/// 색은 앱의 단일 액센트 하나만 쓴다. 축 라벨은 처음/끝 날짜와 3단계 금액만 —
/// 격자·축은 물러나고 선이 말하게 한다.
class _NetWorthChart extends StatelessWidget {
  final List<AssetSnapshot> snapshots; // importedAt 오름차순

  const _NetWorthChart({required this.snapshots});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = Theme.of(context).colorScheme.primary;

    final spots = snapshots
        .map(
          (s) => FlSpot(
            s.importedAt.millisecondsSinceEpoch.toDouble(),
            s.netWorth,
          ),
        )
        .toList();

    var minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    var maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    if (minY == maxY) {
      // 값이 전부 같으면 위아래 10% 여유를 만들어 0 간격 crash를 막는다.
      final pad = (minY.abs() * 0.1).clamp(1.0, double.infinity);
      minY -= pad;
      maxY += pad;
    } else {
      final pad = (maxY - minY) * 0.12;
      minY -= pad;
      maxY += pad;
    }

    final minX = spots.first.x;
    final maxX = spots.last.x;

    String dateLabel(double ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
      return '${d.month}/${d.day}';
    }

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 2,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: colors.outline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: (maxY - minY) / 2,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    formatWonCompact(value),
                    style: AppTypography.dataSmall(color: colors.textMuted),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                // 라벨 충돌을 피하기 위해 처음/끝 날짜만 표시.
                interval: maxX - minX,
                getTitlesWidget: (value, meta) {
                  if (value != minX && value != maxX) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dateLabel(value),
                      style: AppTypography.dataSmall(color: colors.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => touched
                  .map(
                    (t) => LineTooltipItem(
                      '${dateLabel(t.x)}\n${formatWon(t.y)}',
                      TextStyle(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                        fontSize: 12,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: accent,
              barWidth: 2,
              isCurved: false,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, index) => FlDotCirclePainter(
                  radius: 3,
                  color: accent,
                  strokeWidth: 2,
                  strokeColor: Theme.of(context).colorScheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: accent.withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
