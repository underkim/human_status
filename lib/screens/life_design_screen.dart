import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'finance_screen.dart';
import 'goal_form_screen.dart';
import 'goals_screen.dart';

class LifeDesignScreen extends ConsumerStatefulWidget {
  const LifeDesignScreen({super.key});

  @override
  ConsumerState<LifeDesignScreen> createState() => _LifeDesignScreenState();
}

class _LifeDesignScreenState extends ConsumerState<LifeDesignScreen> with SingleTickerProviderStateMixin {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('인생설계'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '목표'), Tab(text: '재무')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [GoalsListView(), FinanceListView()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _tabController.index == 0
            ? Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoalFormScreen()))
            : showAddTransactionDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
