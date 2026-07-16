import 'package:flutter/material.dart';

/// Aligns [child] to the top center and caps its width once the available width
/// exceeds [maxWidth], so wide desktop windows don't stretch body text and
/// actions edge to edge. Below [maxWidth] it is a no-op — [child] keeps
/// filling the available width exactly as it did before, so compact/mobile
/// layouts are unaffected.
///
/// Deliberately owns nothing beyond horizontal width and alignment: screens keep
/// returning their own scrollable/padded widget (e.g. a `ListView` with its
/// own `padding`) unchanged, so scroll behavior, height resolution, and
/// padding ownership all stay exactly where they already were.
class PageContentBounds extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const PageContentBounds({
    super.key,
    required this.child,
    required this.maxWidth,
  });

  /// Onboarding steps — a single linear flow, kept narrower for readability.
  static const double narrow = 960;

  /// Dashboard/Quests/Goals/Settings — denser card and list content.
  static const double wide = 1200;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
