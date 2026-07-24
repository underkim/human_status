import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/goal_idea_bank.dart';
import '../models/goal.dart';
import '../models/stat.dart';
import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/page_content_bounds.dart';

/// 완전한 신규 설치의 첫 화면. 게임 루프(퀘스트=현실 행동, 완료=XP/스탯
/// 성장, 목표=퀘스트 묶음)를 짧게 안내하고, 우선 성장 스탯 선택 → 스타터
/// 목표 선택 → 생성까지 이어진다. 완료/건너뛰기 모두 UserProfile에
/// onboardingCompleted=true를 저장할 뿐, 화면 전환 자체는 하지 않는다 —
/// HumanStatusApp이 profileProvider를 watch해 그 변화를 보고 스스로
/// HomeShell로 다시 빌드하므로(reactive gate), 이 화면은 그 상태 변경 이후
/// 자신이 트리에서 교체되는 것을 기다리기만 하면 된다.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.standalone = false});

  final bool standalone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _OnboardingStep { intro, chooseStat, chooseGoal }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _OnboardingStep _step = _OnboardingStep.intro;
  String? _selectedStatId;
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _finishOnboarding({String? preferredStatId}) async {
    final storage = ref.read(storageServiceProvider);
    final profile = ref.read(profileProvider);
    if (!widget.standalone) profile.onboardingCompleted = true;
    if (preferredStatId != null) {
      profile.preferredStatId = preferredStatId;
    }
    await storage.saveProfile(profile);
    ref.read(profileProvider.notifier).reload();
    if (widget.standalone && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _skip() async {
    await _finishOnboarding(preferredStatId: _selectedStatId);
  }

  void _selectStat(String statId) {
    setState(() {
      _selectedStatId = statId;
      _step = _OnboardingStep.chooseGoal;
    });
  }

  Future<void> _startGoal(GoalIdea idea) async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final goal = Goal(
      id: const Uuid().v4(),
      title: idea.title,
      description: idea.description,
      statId: idea.statId,
      createdAt: DateTime.now(),
    );

    try {
      // requireQuests: 스타터 목표는 실행할 퀘스트가 하나도 없으면 의미가
      // 없으므로, GoalsNotifier가 그 경우 아무것도 저장하지 않고 예외를
      // 던지게 한다 — 재시도해도 중복 goal이 생기지 않는다.
      await ref
          .read(goalsProvider.notifier)
          .createGoal(goal, requireQuests: true);
      await _finishOnboarding(preferredStatId: idea.statId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '목표를 만들지 못했어요. 다시 시도해주세요.';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.standalone ? 'AI 퀘스트 설계' : '시작하기'),
        automaticallyImplyLeading: widget.standalone,
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _skip,
            child: Text(widget.standalone ? '닫기' : '나중에 하기'),
          ),
        ],
      ),
      body: SafeArea(
        child: PageContentBounds(
          maxWidth: PageContentBounds.narrow,
          child: switch (_step) {
            _OnboardingStep.intro => _IntroStep(
              standalone: widget.standalone,
              onNext: () => setState(() => _step = _OnboardingStep.chooseStat),
            ),
            _OnboardingStep.chooseStat => _ChooseStatStep(
              stats: ref.watch(statsProvider),
              selectedStatId: _selectedStatId,
              onSelect: _selectStat,
            ),
            _OnboardingStep.chooseGoal => _ChooseGoalStep(
              statId: _selectedStatId!,
              isSubmitting: _isSubmitting,
              errorMessage: _errorMessage,
              onStart: _startGoal,
              onBack: () => setState(() {
                _step = _OnboardingStep.chooseStat;
                _errorMessage = null;
              }),
            ),
          },
        ),
      ),
    );
  }
}

class _IntroStep extends StatelessWidget {
  final VoidCallback onNext;
  final bool standalone;

  const _IntroStep({required this.onNext, required this.standalone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            standalone ? '나에게 맞는 퀘스트를 설계해요' : 'Human Status에 오신 걸 환영해요',
            style: theme.textTheme.headlineSmall,
          ),
          if (standalone) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '성장하고 싶은 영역과 목표를 고르면 AI가 실행 가능한 행동으로 나눠드려요.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _InfoRow(
            icon: Icons.checklist,
            title: '퀘스트 = 현실 행동',
            body: '앱은 오늘 할 수 있는 작은 행동을 퀘스트로 보여줘요.',
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.bolt,
            title: '완료하면 XP와 스탯이 자라요',
            body: '퀘스트를 완료할 때마다 관련 스탯이 성장하고 레벨이 올라요.',
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.flag,
            title: '목표 = 퀘스트 묶음',
            body: '장기 목표를 만들면 실행 가능한 퀘스트로 자동으로 나눠드려요.',
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(onPressed: onNext, child: const Text('다음')),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoRow({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChooseStatStep extends StatelessWidget {
  final List<Stat> stats;
  final String? selectedStatId;
  final ValueChanged<String> onSelect;

  const _ChooseStatStep({
    required this.stats,
    required this.selectedStatId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('먼저 키우고 싶은 영역을 골라주세요', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '고른 영역을 기준으로 목표를 추천해드려요. 나중에 언제든 다른 영역도 키울 수 있어요.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final stat in stats)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Semantics(
                button: true,
                selected: selectedStatId == stat.id,
                label: '${stat.name} 선택',
                child: OutlinedButton(
                  onPressed: () => onSelect(stat.id),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                      horizontal: AppSpacing.lg,
                    ),
                    alignment: Alignment.centerLeft,
                    backgroundColor: selectedStatId == stat.id
                        ? theme.colorScheme.primaryContainer
                        : null,
                  ),
                  child: Row(
                    children: [
                      Text(stat.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          stat.name,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (selectedStatId == stat.id)
                        Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChooseGoalStep extends StatelessWidget {
  final String statId;
  final bool isSubmitting;
  final String? errorMessage;
  final ValueChanged<GoalIdea> onStart;
  final VoidCallback onBack;

  const _ChooseGoalStep({
    required this.statId,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onStart,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ideas = goalIdeaBank.where((i) => i.statId == statId).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: isSubmitting ? null : onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: '이전 단계로',
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '스타터 목표를 골라주세요',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '고르면 바로 목표가 만들어지고, 실행할 퀘스트도 함께 준비돼요.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final idea in ideas)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                title: Text(idea.title),
                subtitle: Text(idea.description),
                trailing: FilledButton(
                  onPressed: isSubmitting ? null : () => onStart(idea),
                  child: const Text('시작하기'),
                ),
              ),
            ),
          if (isSubmitting) ...[
            const SizedBox(height: AppSpacing.md),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ],
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              errorMessage!,
              style: TextStyle(color: context.appColors.error),
            ),
          ],
        ],
      ),
    );
  }
}
