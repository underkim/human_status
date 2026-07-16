import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/goal_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/quest_provider.dart';
import '../screens/quest_form_screen.dart';
import '../screens/quests_screen.dart';
import '../services/daily_summary_service.dart';
import '../theme/app_spacing.dart';
import 'achievement_dialog.dart';
import 'level_up_dialog.dart';
import 'quest_card.dart';

/// 홈 상단 "오늘의 행동" 허브 — 지금 당장 할 일을 스크롤 없이 완료할 수
/// 있게 한다. 진행중 퀘스트가 있으면 [nextQuestProvider]가 고른 단 하나를
/// 강조하고, 없으면 추천 퀘스트 채택을, 그마저 없으면 퀘스트 추가 CTA를
/// 보여준다. 완료 처리 중에는 버튼을 잠가 중복 제출을 막고, 실패 시에는
/// 카드를 그대로 둔 채 재시도 가능한 스낵바만 띄운다(성공 시 피드백은
/// 퀘스트 탭과 동일하게 스낵바 + 레벨업/업적 다이얼로그).
class ActionHubCard extends ConsumerStatefulWidget {
  /// HomeShell 안에서는 이 콜백으로 퀘스트 탭으로 전환한다(중복 화면 push
  /// 방지). 독립 실행/테스트에서는 null이면 QuestsScreen을 직접 push한다.
  final VoidCallback? onViewAllQuests;

  const ActionHubCard({super.key, this.onViewAllQuests});

  @override
  ConsumerState<ActionHubCard> createState() => _ActionHubCardState();
}

class _ActionHubCardState extends ConsumerState<ActionHubCard> {
  // 강조 퀘스트가 완료 처리 도중 바뀔 수 있으므로(다른 화면에서 먼저
  // 완료/삭제하는 등), pending 상태를 전역 bool이 아니라 액션이 시작된
  // 퀘스트 id에 묶어둔다 — 그래야 예전 강조 퀘스트의 완료가 아직 진행중인
  // 채로 강조 퀘스트가 바뀌어도, 새로 강조된(별개 id의) 퀘스트 버튼까지
  // 엉뚱하게 잠기지 않는다.
  final Set<String> _completingIds = {};
  final Set<String> _adoptingIds = {};

  Future<void> _completeHighlighted(String id, String title) async {
    // 실패 스낵바의 재시도 액션은 ScaffoldMessenger(이 State보다 상위)가
    // 들고 있어서, 라우트/탭 전환으로 이 State가 이미 dispose된 뒤에도 그
    // 콜백이 호출될 수 있다 — setState를 부르기 전에 반드시 먼저 확인한다.
    if (!mounted) return;
    if (_completingIds.contains(id)) return;
    setState(() => _completingIds.add(id));
    try {
      final result = await ref.read(questsProvider.notifier).completeQuest(id);
      if (!mounted) return;
      // didComplete가 false라는 건 다른 화면이 먼저 이 퀘스트를 완료/삭제해
      // 이 호출은 조용한 무결과였다는 뜻 — 성공 UI도 에러 UI도 띄우지 않는다.
      if (!result.didComplete) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$title" 완료!')));
      await showLevelUpDialog(
        context,
        ref.read(statsProvider),
        result.levelUps,
      );
      if (!mounted) return;
      await showAchievementDialog(context, result.newAchievements);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('퀘스트 완료에 실패했어요. 다시 시도해주세요.'),
          action: SnackBarAction(
            label: '재시도',
            onPressed: () => _completeHighlighted(id, title),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _completingIds.remove(id));
    }
  }

  Future<void> _adoptSuggested(String id) async {
    // 위와 같은 이유(재시도 액션이 이 State보다 오래 살아남을 수 있음)로
    // setState 이전에 mounted를 먼저 확인한다.
    if (!mounted) return;
    if (_adoptingIds.contains(id)) return;
    setState(() => _adoptingIds.add(id));
    try {
      await ref.read(questsProvider.notifier).adoptSuggestion(id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('퀘스트를 채택하지 못했어요. 다시 시도해주세요.'),
          action: SnackBarAction(
            label: '재시도',
            onPressed: () => _adoptSuggested(id),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _adoptingIds.remove(id));
    }
  }

  void _viewAllQuests(BuildContext context) {
    final callback = widget.onViewAllQuests;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QuestsScreen()));
  }

  void _addQuest(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QuestFormScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = ref.watch(statsProvider);
    final goals = ref.watch(goalsProvider);
    final nextQuest = ref.watch(nextQuestProvider);
    final suggested = ref.watch(suggestedQuestsProvider);
    final summary = ref.watch(todaySummaryProvider);

    Widget body;
    if (nextQuest != null) {
      final completing = _completingIds.contains(nextQuest.id);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('다음 퀘스트', style: theme.textTheme.titleSmall),
          QuestCard(
            quest: nextQuest,
            stats: stats,
            goals: goals,
            actions: [
              FilledButton(
                onPressed: completing
                    ? null
                    : () => _completeHighlighted(nextQuest.id, nextQuest.title),
                child: completing
                    ? pendingActionIndicator('완료 처리 중')
                    : const Text('완료'),
              ),
            ],
          ),
        ],
      );
    } else if (suggested.isNotEmpty) {
      final top = suggested.first;
      final adopting = _adoptingIds.contains(top.id);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('추천 퀘스트', style: theme.textTheme.titleSmall),
          QuestCard(
            quest: top,
            stats: stats,
            goals: goals,
            actions: [
              FilledButton(
                onPressed: adopting ? null : () => _adoptSuggested(top.id),
                child: adopting
                    ? pendingActionIndicator('채택 처리 중')
                    : const Text('채택하고 시작'),
              ),
            ],
          ),
        ],
      );
    } else {
      // 이 지점에 도달했다는 건 DashboardScreen이 이미 진짜 첫 실행이
      // 아니라고 판단했다는 뜻(퀘스트나 목표를 만든 이력이 있음) — 지금
      // 당장 진행중/추천 항목이 없을 뿐이므로 다음 행동을 만들 CTA를 준다.
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '지금 진행중인 퀘스트가 없어요. 새 퀘스트를 추가해보세요.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () => _addQuest(context),
              icon: const Icon(Icons.add_task),
              label: const Text('퀘스트 추가'),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('오늘의 행동', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '오늘 완료 ${summary.completedCount}개 · +${formatXp(summary.xp)} XP',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            body,
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _viewAllQuests(context),
                child: const Text('전체 퀘스트 보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
