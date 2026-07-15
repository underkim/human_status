import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/financial_planning_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'asset_snapshot_screen.dart';
import 'banksalad_import_screen.dart';
import 'finance_screen.dart';
import 'financial_planning_wizard_screen.dart';

/// Top-level 재무 destination — Scaffold chrome around [FinanceAssetTabView].
class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('재무')),
      body: const FinanceAssetTabView(),
      floatingActionButton: FloatingActionButton(
        // 탭마다 고유 heroTag — quests_screen.dart의 FAB 주석 참고.
        heroTag: 'finance_fab',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BanksaladImportScreen()),
        ),
        child: const Icon(Icons.upload_file),
      ),
    );
  }
}

/// Merges the finance and asset-snapshot views into one outer "재무" tab,
/// switching between them via a small inner TabBar ([거래내역, 자산현황])
/// rather than separate top-level tabs.
class FinanceAssetTabView extends ConsumerStatefulWidget {
  const FinanceAssetTabView({super.key});

  @override
  ConsumerState<FinanceAssetTabView> createState() =>
      _FinanceAssetTabViewState();
}

class _FinanceAssetTabViewState extends ConsumerState<FinanceAssetTabView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recommendations = ref.watch(planRecommendationsProvider);
    final colors = context.appColors;

    String subtitle;
    Color? subtitleColor;
    if (recommendations.isEmpty) {
      subtitle = '은퇴·주택구입 목표를 세우고 필요한 월 저축액을 계산해요';
    } else {
      final behindCount = recommendations.where((r) => !r.isOnTrack).length;
      subtitle = behindCount == 0
          ? '설정한 목표 ${recommendations.length}개 모두 저축 페이스에 맞아요'
          : '설정한 목표 ${recommendations.length}개 중 $behindCount개가 페이스보다 부족해요';
      subtitleColor = behindCount == 0 ? colors.success : colors.warning;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('장기 재무계획'),
              subtitle: Text(
                subtitle,
                style: subtitleColor != null
                    ? TextStyle(color: subtitleColor)
                    : null,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FinancialPlanningWizardScreen(),
                ),
              ),
            ),
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '거래내역'),
            Tab(text: '자산현황'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [FinanceListView(), AssetSnapshotListView()],
          ),
        ),
      ],
    );
  }
}
