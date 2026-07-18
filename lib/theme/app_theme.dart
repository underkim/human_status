import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// 앱 전체 ThemeData 조립 지점. 화면마다 버튼·여백·모서리를 따로 정하지
/// 않도록, 컴포넌트 단위 스타일(Button/IconButton/TextField/Checkbox/Radio/
/// Tabs/Card/Modal(Dialog)/Drawer/Toast(SnackBar)/Tooltip)을 전부 여기서
/// 한 번만 정의한다. List/Table/Select/SearchField는 Flutter 기본 위젯
/// (ListView/DataTable/DropdownButtonFormField/TextField)을 그대로 쓰되
/// 이 테마를 상속받으므로 별도 컴포넌트 클래스가 필요 없다. Pagination은
/// 현재 앱에 페이지네이션이 필요한 목록이 없어 아직 만들지 않는다.
class AppTheme {
  static final ThemeData light = _build(Brightness.light, AppColors.light);
  static final ThemeData dark = _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors ext) {
    final isDark = brightness == Brightness.dark;

    final background = isDark
        ? const Color(0xFF0B101B)
        : const Color(0xFFF7F8FC);
    final surface = isDark ? const Color(0xFF121A28) : const Color(0xFFFFFFFF);
    final primary = isDark ? const Color(0xFF8B9CFF) : const Color(0xFF5B5FEF);
    final onPrimary = Colors.white;

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          surface: surface,
          error: ext.error,
          outline: ext.outline,
          outlineVariant: ext.outline,
        );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      extensions: [ext],
    );

    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: ext.outline),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: ext.textMuted),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: ext.textMuted,
          letterSpacing: 0.4,
        ),
      ),

      // Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, AppDimens.buttonHeightStandard),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          disabledBackgroundColor: ext.outline,
          disabledForegroundColor: ext.textMuted,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, AppDimens.buttonHeightStandard),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          disabledBackgroundColor: ext.outline,
          disabledForegroundColor: ext.textMuted,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, AppDimens.buttonHeightStandard),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          side: BorderSide(color: ext.outlineStrong),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, AppDimens.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
      ),

      // IconButton — minimumSize enforces the 48dp touch target even when
      // the visual icon itself is smaller (AppIconSize.md/lg).
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            AppDimens.minTouchTarget,
            AppDimens.minTouchTarget,
          ),
        ),
      ),

      // TextField / Select(DropdownButtonFormField) / SearchField share this.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: ext.error),
        ),
        focusedErrorBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: ext.error, width: 2),
        ),
        disabledBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: ext.outline),
        ),
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: ext.outlineStrong, width: 1.5),
      ),

      // Radio
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return ext.outline;
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return ext.outlineStrong;
        }),
      ),

      // Tabs
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: ext.textMuted,
        indicatorColor: colorScheme.primary,
        dividerColor: ext.outline,
      ),

      // Card / Table 컨테이너
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        shadowColor: const Color(0xFF101828).withValues(alpha: 0.08),
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: ext.outline),
        ),
      ),

      // List
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        iconColor: ext.textMuted,
        minVerticalPadding: AppSpacing.sm,
      ),

      // Table
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: ext.textMuted,
          letterSpacing: 0.4,
        ),
        dataTextStyle: const TextStyle(fontSize: 13),
        dividerThickness: 1,
      ),

      // Modal(Dialog)
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      // Drawer
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(),
      ),

      // Toast(SnackBar)
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? ext.outlineStrong : const Color(0xFF201E1A),
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF17181A) : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ext.outlineStrong,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: TextStyle(
          color: isDark ? const Color(0xFF17181A) : Colors.white,
          fontSize: 12,
        ),
      ),

      // 바텀 내비게이션 (Compact) / NavigationRail은 화면 쪽에서 폭에 따라 전환
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: isDark ? 0.28 : 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      dividerTheme: DividerThemeData(
        color: ext.outline,
        thickness: 1,
        space: 1,
      ),

      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: ext.outlineStrong),
        shape: const StadiumBorder(),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: ext.surfaceAlt,
      ),
    );
  }
}
