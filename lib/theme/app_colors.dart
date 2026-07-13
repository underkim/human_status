import 'package:flutter/material.dart';

/// Semantic and stat colors that sit outside Flutter's [ColorScheme] slots.
/// Access via `Theme.of(context).extension<AppColors>()!` or the
/// `context.appColors` shortcut below.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color surfaceAlt;
  final Color textMuted;
  final Color outline;
  final Color outlineStrong;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color statHealth;
  final Color statIntelligence;
  final Color statWealth;
  final Color statRelationships;
  final Color statMental;
  final Color celebration;
  final Color onCelebration;

  const AppColors({
    required this.surfaceAlt,
    required this.textMuted,
    required this.outline,
    required this.outlineStrong,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.statHealth,
    required this.statIntelligence,
    required this.statWealth,
    required this.statRelationships,
    required this.statMental,
    required this.celebration,
    required this.onCelebration,
  });

  static const light = AppColors(
    surfaceAlt: Color(0xFFEFECE3),
    textMuted: Color(0xFF756F62),
    outline: Color(0xFFE1DCCF),
    outlineStrong: Color(0xFFC7C0AE),
    success: Color(0xFF3D6B4F),
    warning: Color(0xFF8A5A2B),
    error: Color(0xFF9A3F3F),
    info: Color(0xFF3A5F7D),
    statHealth: Color(0xFFC1552F),
    statIntelligence: Color(0xFF3A6693),
    statWealth: Color(0xFFA87820),
    statRelationships: Color(0xFFA14568),
    statMental: Color(0xFF6B5490),
    celebration: Color(0xFFC98A2E),
    onCelebration: Color(0xFF3A2408),
  );

  static const dark = AppColors(
    surfaceAlt: Color(0xFF2A2622),
    textMuted: Color(0xFFA39C8C),
    outline: Color(0xFF34302A),
    outlineStrong: Color(0xFF4A443B),
    success: Color(0xFF7FBD97),
    warning: Color(0xFFD99A5C),
    error: Color(0xFFE19A9A),
    info: Color(0xFF8FB8D9),
    statHealth: Color(0xFFE08363),
    statIntelligence: Color(0xFF7CA7D6),
    statWealth: Color(0xFFD1A756),
    statRelationships: Color(0xFFD488A8),
    statMental: Color(0xFFA98FD1),
    celebration: Color(0xFFF0BD63),
    onCelebration: Color(0xFF3A2408),
  );

  /// Looks up a stat's accent color by [Stat.id] (health/intelligence/wealth/
  /// relationships/mental). Falls back to [textMuted] for unknown ids.
  Color statColor(String statId) => switch (statId) {
        'health' => statHealth,
        'intelligence' => statIntelligence,
        'wealth' => statWealth,
        'relationships' => statRelationships,
        'mental' => statMental,
        _ => textMuted,
      };

  @override
  AppColors copyWith({
    Color? surfaceAlt,
    Color? textMuted,
    Color? outline,
    Color? outlineStrong,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? statHealth,
    Color? statIntelligence,
    Color? statWealth,
    Color? statRelationships,
    Color? statMental,
    Color? celebration,
    Color? onCelebration,
  }) {
    return AppColors(
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      textMuted: textMuted ?? this.textMuted,
      outline: outline ?? this.outline,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      statHealth: statHealth ?? this.statHealth,
      statIntelligence: statIntelligence ?? this.statIntelligence,
      statWealth: statWealth ?? this.statWealth,
      statRelationships: statRelationships ?? this.statRelationships,
      statMental: statMental ?? this.statMental,
      celebration: celebration ?? this.celebration,
      onCelebration: onCelebration ?? this.onCelebration,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      statHealth: Color.lerp(statHealth, other.statHealth, t)!,
      statIntelligence: Color.lerp(statIntelligence, other.statIntelligence, t)!,
      statWealth: Color.lerp(statWealth, other.statWealth, t)!,
      statRelationships: Color.lerp(statRelationships, other.statRelationships, t)!,
      statMental: Color.lerp(statMental, other.statMental, t)!,
      celebration: Color.lerp(celebration, other.celebration, t)!,
      onCelebration: Color.lerp(onCelebration, other.onCelebration, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
