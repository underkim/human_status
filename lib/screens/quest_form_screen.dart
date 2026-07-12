import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/quest.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../widgets/quest_card.dart';

const _difficultyXp = {
  QuestDifficulty.easy: 15.0,
  QuestDifficulty.medium: 30.0,
  QuestDifficulty.hard: 50.0,
};

class QuestFormScreen extends ConsumerStatefulWidget {
  const QuestFormScreen({super.key});

  @override
  ConsumerState<QuestFormScreen> createState() => _QuestFormScreenState();
}

class _QuestFormScreenState extends ConsumerState<QuestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedStatId;
  QuestDifficulty _difficulty = QuestDifficulty.easy;
  bool _isRecurring = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    _selectedStatId ??= stats.isNotEmpty ? stats.first.id : null;

    return Scaffold(
      appBar: AppBar(title: const Text('퀘스트 추가')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '제목'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '제목을 입력해주세요' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: '설명'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedStatId,
              decoration: const InputDecoration(labelText: '연결 스텟'),
              items: stats
                  .map((s) => DropdownMenuItem(value: s.id, child: Text('${s.icon} ${s.name}')))
                  .toList(),
              onChanged: (v) => setState(() => _selectedStatId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<QuestDifficulty>(
              initialValue: _difficulty,
              decoration: const InputDecoration(labelText: '난이도'),
              items: QuestDifficulty.values
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text('${difficultyLabel(d)} (+${_difficultyXp[d]!.toInt()}XP)'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _difficulty = v ?? QuestDifficulty.easy),
            ),
            SwitchListTile(
              title: const Text('매일 반복'),
              value: _isRecurring,
              onChanged: (v) => setState(() => _isRecurring = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              child: const Text('추가하기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedStatId == null) return;

    final quest = Quest(
      id: const Uuid().v4(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      statRewards: {_selectedStatId!: _difficultyXp[_difficulty]!},
      difficulty: _difficulty,
      isRecurring: _isRecurring,
      status: QuestStatus.active,
      source: QuestSource.manual,
      createdAt: DateTime.now(),
    );

    await ref.read(questsProvider.notifier).addQuest(quest);
    if (mounted) Navigator.of(context).pop();
  }
}
