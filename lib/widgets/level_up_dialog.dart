import 'package:flutter/material.dart';

import '../models/stat.dart';
import '../services/xp_service.dart';
import '../theme/app_spacing.dart';
import 'celebration_dialog_shell.dart';

/// 이 파일에서만 쓰는 등장 애니메이션 길이/커브 — 색상·간격 토큰이 아니라
/// 지속시간이므로 named `static const`로 둔다.
const _transitionDuration = Duration(milliseconds: 220);
const _transitionCurve = Curves.easeOut;

Future<void> showLevelUpDialog(
  BuildContext context,
  List<Stat> stats,
  Map<String, LevelUpResult> results,
) async {
  final leveledUp = results.entries.where((e) => e.value.leveledUp).toList();
  if (leveledUp.isEmpty) return;

  final statsById = {for (final s in stats) s.id: s};
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
      return LevelUpDialog(statsById: statsById, leveledUp: leveledUp);
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

/// 레벨업 다이얼로그 콘텐츠 — [CelebrationDialogShell] 위에 올라가는 부분만
/// 담당해 별도로 위젯 테스트할 수 있다.
class LevelUpDialog extends StatelessWidget {
  final Map<String, Stat> statsById;
  final List<MapEntry<String, LevelUpResult>> leveledUp;

  const LevelUpDialog({
    super.key,
    required this.statsById,
    required this.leveledUp,
  });

  @override
  Widget build(BuildContext context) {
    return CelebrationDialogShell(
      title: '🎉 레벨업!',
      icon: Icons.celebration,
      children: leveledUp.map((e) {
        final stat = statsById[e.key];
        final name = stat != null ? '${stat.icon} ${stat.name}' : e.key;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text('$name 스텟이 Lv.${e.value.newLevel}(으)로 올랐습니다!'),
        );
      }).toList(),
    );
  }
}
