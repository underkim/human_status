import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// 레벨업/업적 다이얼로그가 공유하는 표현 계층. 등장 애니메이션(페이드+
/// 스케일)은 호출자의 `showGeneralDialog` transition builder가 담당하고,
/// 이 위젯은 정적인 콘텐츠 레이아웃만 책임진다 — `Dialog`의 shape/
/// background는 `AppTheme.dialogTheme`를 그대로 상속받도록 여기서 따로
/// 지정하지 않는다.
class CelebrationDialogShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final String confirmLabel;

  const CelebrationDialogShell({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.confirmLabel = '확인',
  });

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;

    // AlertDialog가 내부적으로 쓰는 것과 같은 패턴: scopesRoute는 다이얼로그
    // 전체를 하나의 route로 스코프하고, namesRoute는 그 route의 이름을
    // 제목 텍스트로 announce한다. explicitChildNodes로 자식 semantics가
    // 하나로 뭉개지지 않게 한다.
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 장식용 아이콘 — 제목이 같은 의미를 텍스트로 전달하므로
              // 중복 낭독되지 않도록 접근성 트리에서 제외한다.
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: appColors.celebration,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: AppIconSize.xl,
                    color: appColors.onCelebration,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                namesRoute: true,
                container: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // 여러 항목/큰 글꼴에서도 화면을 넘치지 않도록 본문만 스크롤
              // 가능하게 한다.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
