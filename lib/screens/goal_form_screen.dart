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

const _financialHorizonsMonths = [6, 12, 36];

class GoalFormScreen extends ConsumerStatefulWidget {
  const GoalFormScreen({super.key});

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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  List<GoalIdea> _recommendedIdeas(List<Stat> stats) {
    if (stats.isEmpty) return [];
    final weakest = ([...stats]..sort((a, b) => a.level.compareTo(b.level))).first;
    return goalIdeaBank.where((i) => i.statId == weakest.id).take(3).toList();
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

    final recommendedIdeas = _recommendedIdeas(stats);
    final avgMonthlySaving = _isFinancial
        ? FinancialPlanningService.recentAverageMonthlySaving(ref.watch(storageServiceProvider))
        : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('목표 추가')),
      body: AbsorbPointer(
        absorbing: _isSubmitting,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '목표를 저장하면 AI가 실행할 작은 퀘스트로 자동으로 나눠드려요.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.appColors.textMuted),
              ),
              const SizedBox(height: 16),
              if (recommendedIdeas.isNotEmpty) ...[
                Text('추천 목표 (약한 스텟 기준)', style: Theme.of(context).textTheme.titleSmall),
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
              SwitchListTile(
                title: const Text('재무 목표예요'),
                subtitle: const Text('저축·투자처럼 금액으로 진행률을 추적해요.'),
                value: _isFinancial,
                onChanged: (v) => setState(() {
                  _isFinancial = v;
                  if (v) _selectedStatId = 'wealth';
                }),
                contentPadding: EdgeInsets.zero,
              ),
              if (_isFinancial) ...[
                const SizedBox(height: 8),
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
                onChanged: (v) => setState(() => _selectedStatId = v),
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
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Expanded(child: Text('AI가 목표를 퀘스트로 분해하고 있어요...')),
                    ],
                  ),
                ),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: const Text('추가하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedStatId == null) return;
    setState(() => _isSubmitting = true);

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
  }
}
