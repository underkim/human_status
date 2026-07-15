import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'dashboard_screen.dart';
import 'finance_asset_tab_view.dart';
import 'goals_screen.dart';
import 'more_screen.dart';
import 'quests_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _questsTabIndex = 1;

  static const _destinations = [
    (icon: Icons.home_outlined, selectedIcon: Icons.home, label: '홈'),
    (
      icon: Icons.checklist_outlined,
      selectedIcon: Icons.checklist,
      label: '퀘스트',
    ),
    (icon: Icons.flag_outlined, selectedIcon: Icons.flag, label: '목표'),
    (
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      label: '재무',
    ),
    (
      icon: Icons.more_horiz_outlined,
      selectedIcon: Icons.more_horiz,
      label: '더보기',
    ),
  ];

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final screens = [
      DashboardScreen(onViewAllQuests: () => _select(_questsTabIndex)),
      const QuestsScreen(),
      const GoalsScreen(),
      const FinanceScreen(),
      const MoreScreen(),
    ];
    final body = IndexedStack(index: _index, children: screens);

    // Compact(<600dp): 바텀 내비게이션 5개.
    if (AppBreakpoints.isCompact(width)) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    // Medium/Expanded(>=600dp): 좌측 레일. Expanded에서는 라벨을 항상 노출해
    // 목적지 5개를 그대로 유지한다(더보기를 해체하지 않음 — 창 크기를 조절해도
    // 선택 인덱스가 깨지지 않도록 목적지 개수를 브레이크포인트 전체에서 고정).
    final extended = AppBreakpoints.isExpanded(width);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _select,
            extended: extended,
            minExtendedWidth: 180,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
