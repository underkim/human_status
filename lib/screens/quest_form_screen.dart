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
  /// 값이 있으면 편집 모드 — 폼이 미리 채워지고 저장 시 이 퀘스트를 갱신한다.
  final Quest? existing;

  const QuestFormScreen({super.key, this.existing});

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

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _difficulty = existing.difficulty;
      _isRecurring = existing.isRecurring;
      // statRewards의 첫 스텟을 연결 스텟으로 되살린다(폼은 스텟 하나만 다룬다).
      _selectedStatId = existing.statRewards.keys.isNotEmpty ? existing.statRewards.keys.first : null;
    }
  }

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
      appBar: AppBar(title: Text(_isEditing ? '퀘스트 수정' : '퀘스트 추가')),
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
              child: Text(_isEditing ? '저장하기' : '추가하기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedStatId == null) return;

    final notifier = ref.read(questsProvider.notifier);
    final existing = widget.existing;
    if (existing != null) {
      // id·상태·생성시각·목표연결은 유지하고 편집 가능한 필드만 갱신한다.
      existing.title = _titleController.text.trim();
      existing.description = _descriptionController.text.trim();
      existing.statRewards = {_selectedStatId!: _difficultyXp[_difficulty]!};
      existing.difficulty = _difficulty;
      existing.isRecurring = _isRecurring;
      await notifier.updateQuest(existing);
    } else {
      await notifier.addQuest(Quest(
        id: const Uuid().v4(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        statRewards: {_selectedStatId!: _difficultyXp[_difficulty]!},
        difficulty: _difficulty,
        isRecurring: _isRecurring,
        status: QuestStatus.active,
        source: QuestSource.manual,
        createdAt: DateTime.now(),
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }
}
