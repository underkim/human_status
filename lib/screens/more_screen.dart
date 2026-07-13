import 'package:flutter/material.dart';

import 'insights_screen.dart';
import 'settings_screen.dart';

/// Low-frequency features (통계·설정) live behind this thin hub instead of
/// occupying their own top-level bottom-nav destinations — see the IA
/// redesign's rationale for collapsing a 6-tab bar down to 5.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('더보기')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('통계'),
            subtitle: const Text('스트릭 · XP 추이 · 업적'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InsightsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('설정'),
            subtitle: const Text('API 키 · 알림 · 백업 · 초기화'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
