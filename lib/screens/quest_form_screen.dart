import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/quest.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../widgets/page_content_bounds.dart';
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
  bool _isSubmitting = false;

  // 생성 모드에서 재시도까지 안정적으로 같은 id를 쓰기 위한 draft id — 폼이
  // 다시 그려져도(예: setState) 바뀌지 않도록 initState에서 한 번만 정한다.
  // 실패 후 재시도가 addQuest의 충돌 검사에 걸리지 않고, 롤백으로 지워진
  // 같은 id 자리에 정확히 하나만 다시 쓰이게 한다.
  late final String _draftId;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _draftId = const Uuid().v4();
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
      body: PageContentBounds(
        maxWidth: PageContentBounds.narrow,
        child: AbsorbPointer(
        absorbing: _isSubmitting,
        child: Form(
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
              if (_isSubmitting)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_isEditing ? '저장하고 있어요...' : '추가하고 있어요...')),
                    ],
                  ),
                ),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: Text(_isEditing ? '저장하기' : '추가하기'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _submit() async {
    // 폼이 리빌드되기 전(버튼이 아직 활성 상태로 보이는 동안) 연타해도 두 번째
    // 호출은 여기서 곧장 막힌다 — AbsorbPointer/onPressed null은 리빌드 이후에만
    // 효과가 있으므로 이 동기 체크가 실제 가드다.
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate() || _selectedStatId == null) return;

    setState(() => _isSubmitting = true);
    try {
      final notifier = ref.read(questsProvider.notifier);
      final existing = widget.existing;
      if (existing != null) {
        // 편집: widget.existing/살아있는 Hive 객체는 절대 건드리지 않고, 그
        // 복사본 위에 편집 가능한 필드만 바꾼 detached proposed quest를
        // 만든다 — id·상태·생성시각·목표연결 등은 그대로 두어 저장이
        // 실패해도 existing이 절대 변형되지 않는다.
        final proposed = existing.copy()
          ..title = _titleController.text.trim()
          ..description = _descriptionController.text.trim()
          ..statRewards = {_selectedStatId!: _difficultyXp[_difficulty]!}
          ..difficulty = _difficulty
          ..isRecurring = _isRecurring;
        await notifier.updateQuest(proposed);
      } else {
        await notifier.addQuest(Quest(
          id: _draftId,
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
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      // 원인은 노출하지 않는다 — 입력한 값은 그대로 남고 화면은 열려 있어
      // 사용자가 바로 다시 시도할 수 있다.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퀘스트를 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
