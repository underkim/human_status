import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quest.dart';
import '../models/stat.dart';
import '../models/user_profile.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../services/storage_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _editApiKey(BuildContext context, WidgetRef ref) async {
    final storage = ref.read(storageServiceProvider);
    final profile = ref.read(profileProvider);
    final controller = TextEditingController(text: profile.claudeApiKey ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Claude API 키'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('설정하면 추천 퀘스트가 Claude AI로 생성돼요. 비워두면 로컬 규칙 기반으로 동작합니다.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'sk-ant-...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('키 삭제')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result == null) return;

    profile.claudeApiKey = result.isEmpty ? null : result;
    await storage.saveProfile(profile);
    ref.read(profileProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.isEmpty ? 'API 키가 삭제되었습니다.' : 'API 키가 저장되었습니다.')),
      );
    }
  }

  Future<void> _editReminder(BuildContext context, WidgetRef ref) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림은 이 플랫폼(웹)에서는 지원되지 않아요.')),
      );
      return;
    }

    final storage = ref.read(storageServiceProvider);
    final profile = ref.read(profileProvider);
    final current = profile.reminderMinutesSinceMidnight;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알림 시간'),
        content: Text(
          current != null
              ? '매일 ${(current ~/ 60).toString().padLeft(2, '0')}:${(current % 60).toString().padLeft(2, '0')}에 알림을 보내드려요.'
              : '진행중인 퀘스트를 알려주는 매일 알림을 설정할 수 있어요.',
        ),
        actions: [
          if (current != null)
            TextButton(onPressed: () => Navigator.pop(context, 'off'), child: const Text('끄기')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, 'set'), child: const Text('시간 설정')),
        ],
      ),
    );
    if (action == null) return;

    final notificationService = ref.read(notificationServiceProvider);

    if (action == 'off') {
      profile.reminderMinutesSinceMidnight = null;
      await storage.saveProfile(profile);
      await notificationService.cancelReminder();
      ref.read(profileProvider.notifier).reload();
      return;
    }

    if (!context.mounted) return;
    final initial = current != null
        ? TimeOfDay(hour: current ~/ 60, minute: current % 60)
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;

    profile.reminderMinutesSinceMidnight = picked.hour * 60 + picked.minute;
    await storage.saveProfile(profile);
    await notificationService.scheduleDailyReminder(
      hour: picked.hour,
      minute: picked.minute,
      activeQuestCount: ref.read(activeQuestsProvider).length,
    );
    ref.read(profileProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('알림 시간이 저장되었습니다.')));
    }
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('데이터 초기화'),
        content: const Text('모든 스텟과 퀘스트 기록이 삭제되고 처음 상태로 돌아갑니다. 계속할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('초기화')),
        ],
      ),
    );
    if (confirmed != true) return;

    final storage = ref.read(storageServiceProvider);
    final preservedProfile = ref.read(profileProvider);
    await storage.statsBox.clear();
    await storage.questsBox.clear();
    await storage.profileBox.clear();
    await storage.achievementsBox.clear();
    for (final s in StorageService.defaultStats) {
      await storage.saveStat(Stat(id: s.id, name: s.name, icon: s.icon));
    }
    await storage.saveProfile(UserProfile(
      claudeApiKey: preservedProfile.claudeApiKey,
      reminderMinutesSinceMidnight: preservedProfile.reminderMinutesSinceMidnight,
      lastQuestRefresh: preservedProfile.lastQuestRefresh,
    ));
    ref.read(statsProvider.notifier).reload();
    ref.read(questsProvider.notifier).reload();
    ref.read(profileProvider.notifier).reload();
    ref.read(unlockedAchievementsProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('초기화되었습니다.')));
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final storage = ref.read(storageServiceProvider);
    final data = {
      'stats': storage.getStats().map((s) => s.toJson()).toList(),
      'quests': storage.getQuests().map((q) => q.toJson()).toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 내보내기'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(jsonStr)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jsonStr));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('클립보드에 복사되었습니다.')),
                );
              }
            },
            child: const Text('복사'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ],
      ),
    );
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final jsonStr = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 가져오기'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '백업 JSON을 붙여넣으세요'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('가져오기'),
          ),
        ],
      ),
    );
    if (jsonStr == null || jsonStr.trim().isEmpty) return;

    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final stats = (data['stats'] as List).map((e) => Stat.fromJson(e as Map<String, dynamic>)).toList();
      final quests = (data['quests'] as List).map((e) => Quest.fromJson(e as Map<String, dynamic>)).toList();

      final storage = ref.read(storageServiceProvider);
      await storage.statsBox.clear();
      await storage.questsBox.clear();
      for (final s in stats) {
        await storage.saveStat(s);
      }
      for (final q in quests) {
        await storage.saveQuest(q);
      }
      ref.read(statsProvider.notifier).reload();
      ref.read(questsProvider.notifier).reload();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('가져오기가 완료되었습니다.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('가져오기에 실패했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final apiKeySet = (profile.claudeApiKey ?? '').isNotEmpty;
    final reminderMinutes = profile.reminderMinutesSinceMidnight;
    final reminderSubtitle = kIsWeb
        ? '이 플랫폼(웹)에서는 지원되지 않아요'
        : reminderMinutes != null
            ? '매일 ${(reminderMinutes ~/ 60).toString().padLeft(2, '0')}:${(reminderMinutes % 60).toString().padLeft(2, '0')}'
            : '꺼짐 — 탭해서 설정';

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Claude API 키'),
            subtitle: Text(apiKeySet ? '설정됨 — AI 추천 사용 중' : '설정 안 됨 — 로컬 규칙 기반 추천 사용 중'),
            onTap: () => _editApiKey(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('알림 시간'),
            subtitle: Text(reminderSubtitle),
            onTap: () => _editReminder(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('추천 퀘스트 새로고침'),
            subtitle: const Text('보통 24시간마다 자동 갱신돼요. 지금 바로 새로고침할 수 있어요.'),
            onTap: () async {
              await ref.read(questsProvider.notifier).refreshSuggestions();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('추천 퀘스트를 새로고침했습니다.')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('백업 내보내기'),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('백업 가져오기'),
            onTap: () => _importBackup(context, ref),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('데이터 초기화', style: TextStyle(color: Colors.red)),
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    );
  }
}
