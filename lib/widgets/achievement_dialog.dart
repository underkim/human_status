import 'package:flutter/material.dart';

import '../data/achievement_definitions.dart';
import '../theme/app_spacing.dart';
import 'celebration_dialog_shell.dart';

/// 이 파일에서만 쓰는 등장 애니메이션 길이/커브 — [LevelUpDialog]와 같은
/// 값이라도 각 파일에서 독립적으로 정의해 둘 중 하나만 바뀌어도 서로
/// 영향을 주지 않게 한다.
const _transitionDuration = Duration(milliseconds: 220);
const _transitionCurve = Curves.easeOut;

Future<void> showAchievementDialog(
  BuildContext context,
  List<AchievementDefinition> newAchievements,
) async {
  if (newAchievements.isEmpty) return;

  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final barrierLabel = MaterialLocalizations.of(
    context,
  ).modalBarrierDismissLabel;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
    transitionDuration: reduceMotion ? Duration.zero : _transitionDuration,
    pageBuilder: (context, animation, secondaryAnimation) {
      return AchievementDialog(achievements: newAchievements);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: _transitionCurve),
          child: child,
        ),
      );
    },
  );
}

/// 업적 다이얼로그 콘텐츠 — [CelebrationDialogShell] 위에 올라가는 부분만
/// 담당해 별도로 위젯 테스트할 수 있다.
class AchievementDialog extends StatelessWidget {
  final List<AchievementDefinition> achievements;

  const AchievementDialog({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    return CelebrationDialogShell(
      title: '🏆 업적 달성!',
      icon: Icons.emoji_events,
      children: achievements.map((a) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.icon, style: const TextStyle(fontSize: AppIconSize.lg)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(a.description),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
