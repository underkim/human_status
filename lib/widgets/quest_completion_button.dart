import 'package:flutter/material.dart';

import 'quest_card.dart' show pendingActionIndicator;

/// 퀘스트/목표 완료 버튼 — 탭 직후 짧게 축소·복원되는 펄스를 재생하고,
/// 부모가 [isCompleting]을 true로 바꾸면 처리중 표시로 전환한다.
///
/// 완료 성공 여부가 확정되기 전에는 체크마크 등 낙관적 성공 표시를 하지
/// 않는다 — completeQuest가 provider 목록을 즉시 갱신해 이 버튼을 가진
/// 카드 자체가 사라지거나 다른 퀘스트로 바뀔 수 있으므로, 성공 체크 역할은
/// 뒤이어 뜨는 레벨업/업적 다이얼로그가 맡는다. 펄스와 처리중 전환만
/// 다루고 [isCompleting] 변화에 별도 컨트롤러를 돌리지 않아 provider
/// rebuild·경합에 강하다.
class QuestCompletionButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isCompleting;

  const QuestCompletionButton({
    super.key,
    required this.onPressed,
    required this.isCompleting,
  });

  @override
  State<QuestCompletionButton> createState() => _QuestCompletionButtonState();
}

class _QuestCompletionButtonState extends State<QuestCompletionButton>
    with SingleTickerProviderStateMixin {
  static const _pulseDuration = Duration(milliseconds: 90);
  static const _pulseScale = 0.92;
  static const _pulseCurve = Curves.easeOut;

  late final AnimationController _pulseController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
    _scale = Tween<double>(begin: 1, end: _pulseScale).animate(
      CurvedAnimation(parent: _pulseController, curve: _pulseCurve),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _pulseController.forward().then((_) {
        // TickerFuture는 dispose 이후에도 완료될 수 있으므로, 이미
        // 폐기된 컨트롤러를 건드리지 않도록 mounted를 먼저 확인한다.
        if (mounted) _pulseController.reverse();
      });
    }
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onPressed != null && !widget.isCompleting;
    return ScaleTransition(
      scale: _scale,
      child: FilledButton(
        onPressed: enabled ? _handleTap : null,
        child: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : _pulseDuration,
          child: widget.isCompleting
              ? pendingActionIndicator('완료 처리 중')
              : const Text('완료', key: ValueKey('questCompletionLabel')),
        ),
      ),
    );
  }
}
