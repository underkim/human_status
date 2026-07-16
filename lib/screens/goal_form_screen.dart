import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/goal_idea_bank.dart';
import '../models/goal.dart';
import '../models/stat.dart';
import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../services/financial_planning_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/achievement_dialog.dart';
import '../widgets/level_up_dialog.dart';
import '../widgets/page_content_bounds.dart';

const _financialHorizonsMonths = [6, 12, 36];

class GoalFormScreen extends ConsumerStatefulWidget {
  /// 값이 있으면 편집 모드 — 폼이 미리 채워지고 저장 시 이 목표를 갱신한다.
  /// 편집은 퀘스트를 다시 분해하지 않으므로 연결 스텟·재무 여부는 잠긴다.
  final Goal? existing;

  const GoalFormScreen({super.key, this.existing});

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String? _selectedStatId;
  DateTime? _targetDate;
  bool _isFinancial = false;
  bool _isSubmitting = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _selectedStatId = existing.statId;
      _targetDate = existing.targetDate;
      _isFinancial = existing.targetAmount != null;
      if (existing.targetAmount != null) {
        _amountController.text = existing.targetAmount!.round().toString();
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// 온보딩에서 고른 우선 스탯을 우선 적용하고, 그 선호가 없거나(구버전
  /// 프로필) 존재하지 않는 스탯 id를 가리키면(데이터 손상) 기존
  /// weakest-stat 추천으로 폴백한다.
  List<GoalIdea> _recommendedIdeas(List<Stat> stats, String? preferredStatId) {
    if (stats.isEmpty) return [];
    final preferredMatches = preferredStatId == null
        ? const <Stat>[]
        : stats.where((s) => s.id == preferredStatId).toList();
    final target = preferredMatches.isNotEmpty
        ? preferredMatches.first
        : ([...stats]..sort((a, b) => a.level.compareTo(b.level))).first;
    return goalIdeaBank.where((i) => i.statId == target.id).take(3).toList();
  }

  void _applyIdea(GoalIdea idea) {
    setState(() {
      _titleController.text = idea.title;
      _descriptionController.text = idea.description;
      _selectedStatId = idea.statId;
      if (idea.statId != 'wealth') _isFinancial = false;
    });
  }

  void _applyFinancialHorizon(int months, double avgMonthlySaving) {
    final now = DateTime.now();
    setState(() {
      _targetDate = DateTime(now.year, now.month + months, now.day);
      if (avgMonthlySaving > 0) {
        _amountController.text = (avgMonthlySaving * months).toInt().toString();
      }
    });
  }

  String _horizonLabel(int months) => months < 12 ? '$months개월 후' : '${months ~/ 12}년 후';

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    _selectedStatId ??= stats.isNotEmpty ? stats.first.id : null;

    final preferredStatId = ref.watch(profileProvider).preferredStatId;
    final recommendedIdeas = _recommendedIdeas(stats, preferredStatId);
    final hasPreferred = preferredStatId != null && stats.any((s) => s.id == preferredStatId);
    final avgMonthlySaving = _isFinancial
        ? FinancialPlanningService.recentAverageMonthlySaving(ref.watch(storageServiceProvider))
        : 0.0;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '목표 수정' : '목표 추가')),
      body: PageContentBounds(
        maxWidth: PageContentBounds.narrow,
        child: AbsorbPointer(
        absorbing: _isSubmitting,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 추천 아이디어·분해 안내는 새 목표를 만들 때만 도움이 되는
              // 요소라 편집 모드에서는 숨긴다.
              if (!_isEditing) ...[
                Text(
                  '목표를 저장하면 AI가 실행할 작은 퀘스트로 자동으로 나눠드려요.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.appColors.textMuted),
                ),
                const SizedBox(height: 16),
                if (recommendedIdeas.isNotEmpty) ...[
                  Text(
                    hasPreferred ? '추천 목표 (관심 분야 기준)' : '추천 목표 (약한 스텟 기준)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: recommendedIdeas
                        .map((idea) => ActionChip(
                              label: Text(idea.title),
                              onPressed: () => _applyIdea(idea),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '목표'),
                validator: (v) => (v == null || v.trim().isEmpty) ? '목표를 입력해주세요' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: '설명 (선택)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              // 편집 중 재무/일반 성격을 바꾸면 진행률·연결 퀘스트 의미가
              // 어긋나므로 편집 모드에서는 토글을 잠근다.
              SwitchListTile(
                title: const Text('재무 목표예요'),
                subtitle: const Text('저축·투자처럼 금액으로 진행률을 추적해요.'),
                value: _isFinancial,
                onChanged: _isEditing
                    ? null
                    : (v) => setState(() {
                          _isFinancial = v;
                          if (v) _selectedStatId = 'wealth';
                        }),
                contentPadding: EdgeInsets.zero,
              ),
              if (_isFinancial) ...[
                const SizedBox(height: 8),
                if (!_isEditing) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _financialHorizonsMonths
                        .map((months) => ActionChip(
                              label: Text(_horizonLabel(months)),
                              onPressed: () => _applyFinancialHorizon(months, avgMonthlySaving),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '최근 평균 월 저축액 ${formatWon(avgMonthlySaving)} 기준으로 기한·금액을 추천해요.',
                    style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '목표 금액'),
                  validator: (v) {
                    if (!_isFinancial) return null;
                    final n = double.tryParse(v ?? '');
                    if (n == null || n <= 0) return '올바른 금액을 입력해주세요';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedStatId,
                decoration: const InputDecoration(labelText: '연결 스텟'),
                items: stats
                    .map((s) => DropdownMenuItem(value: s.id, child: Text('${s.icon} ${s.name}')))
                    .toList(),
                // 연결 스텟은 목표 완료 보너스가 갈 곳이라 편집 중엔 잠근다.
                onChanged: _isEditing ? null : (v) => setState(() => _selectedStatId = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('목표 기한 (선택)'),
                subtitle: Text(_targetDate != null ? _targetDate!.toString().split(' ').first : '설정 안 됨'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) setState(() => _targetDate = picked);
                },
              ),
              const SizedBox(height: 16),
              if (_isSubmitting)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      // AI 분해는 생성 시에만 일어난다 — 편집 저장에는 다른, 사실에
                      // 맞는 문구를 보여준다.
                      Expanded(child: Text(_isEditing ? '저장하고 있어요...' : 'AI가 목표를 퀘스트로 분해하고 있어요...')),
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
      final existing = widget.existing;
      if (existing != null) {
        // 편집: widget.existing/살아있는 Hive 객체는 절대 건드리지 않고, 그
        // 복사본 위에 편집 가능한 필드만 바꾼 detached proposed goal을 만든다
        // — id·상태·생성시각·연결 스텟·currentAmount 등은 그대로 두어 진행률·
        // 연결 퀘스트가 깨지지 않게 하고, 저장이 실패해도 existing이 절대
        // 변형되지 않는다.
        final proposed = existing.copy()
          ..title = _titleController.text.trim()
          ..description = _descriptionController.text.trim()
          ..targetDate = _targetDate
          ..targetAmount = _isFinancial ? double.tryParse(_amountController.text) : null;
        final completion = await ref.read(goalsProvider.notifier).updateGoal(proposed);
        if (!mounted) return;
        // 목표액을 낮춰 이미 모은 금액이 목표에 도달하면 그 자리에서 완료 처리된다.
        if (completion != null) {
          await showLevelUpDialog(context, ref.read(statsProvider), {existing.statId: completion.levelUp});
          if (!mounted) return;
          await showAchievementDialog(context, completion.newAchievements);
          if (!mounted) return;
        }
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text(completion != null ? '목표를 달성했어요!' : '목표를 수정했어요.'),
        ));
        return;
      }

      final goal = Goal(
        id: const Uuid().v4(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        statId: _selectedStatId!,
        targetDate: _targetDate,
        targetAmount: _isFinancial ? double.tryParse(_amountController.text) : null,
        createdAt: DateTime.now(),
      );

      final result = await ref.read(goalsProvider.notifier).createGoal(goal);
      if (!mounted) return;
      // '목표 설정' 같은 생성 기반 업적은 화면을 떠나기 전에 축하한다.
      await showAchievementDialog(context, result.newAchievements);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('퀘스트 ${result.quests.length}개가 생성되었어요.')));
    } catch (_) {
      // 원인은 노출하지 않는다 — 입력한 값은 그대로 남고 화면은 열려 있어
      // 사용자가 바로 다시 시도할 수 있다.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목표를 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
