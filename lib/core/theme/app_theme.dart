// Design system proprio do Painel do Dono (task_manager_admin_panel).
//
// Identidade "Control Room": dark-first, alta densidade de dados, contraste
// alto para grids longos. Deliberadamente distinto da paleta "fitness"
// (verde/laranja) do app cliente task_manager_flutter — conforme decisao
// aprovada pelo PO, a excecao de branding do CLAUDE.md nao se aplica aqui:
// este app tem identidade visual propria.
//
// Especificacao gerada pelo agente ui-ux-pro-max (ver .planning/research/
// e o relatorio da Fase 1 do card #578 para o detalhamento completo).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens de cor do design system. Mantidos como classe separada do
/// [ThemeData] para uso direto em widgets densos (grids/badges) que
/// precisam de cores semanticas nao expostas pelo ColorScheme padrao
/// (ex.: success/warning).
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryVariant,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onBackground,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.outline,
    required this.error,
    required this.onError,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.info,
  });

  final Color primary;
  final Color primaryVariant;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color onBackground;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color outline;
  final Color error;
  final Color onError;
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color info;

  static const dark = AppColors(
    primary: Color(0xFF3B82F6),
    primaryVariant: Color(0xFF60A5FA),
    onPrimary: Color(0xFF0B1220),
    secondary: Color(0xFFF59E0B),
    onSecondary: Color(0xFF1A1200),
    background: Color(0xFF0B1220),
    surface: Color(0xFF111A2E),
    surfaceVariant: Color(0xFF17233D),
    onBackground: Color(0xFFE6EBF5),
    onSurface: Color(0xFFDCE3F0),
    onSurfaceMuted: Color(0xFF8B99B3),
    outline: Color(0xFF26324A),
    error: Color(0xFFEF4444),
    onError: Color(0xFF1A0505),
    success: Color(0xFF22C55E),
    onSuccess: Color(0xFF052E11),
    warning: Color(0xFFF59E0B),
    onWarning: Color(0xFF1A1200),
    info: Color(0xFF38BDF8),
  );

  static const light = AppColors(
    primary: Color(0xFF1D4ED8),
    primaryVariant: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFFB45309),
    onSecondary: Color(0xFFFFFFFF),
    background: Color(0xFFF4F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEBEFF7),
    onBackground: Color(0xFF0F172A),
    onSurface: Color(0xFF0F172A),
    onSurfaceMuted: Color(0xFF5A6B85),
    outline: Color(0xFFD6DDEA),
    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    success: Color(0xFF16A34A),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFFB45309),
    onWarning: Color(0xFFFFFFFF),
    info: Color(0xFF0284C7),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// Espacamentos e raios padrao do design system (escala base 4px).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const double radiusDefault = 6;
  static const double radiusChip = 4;

  /// Altura de linha densa de grid (uso desktop/Windows).
  static const double gridRowHeightDense = 36;

  /// Altura de linha confortavel de grid (uso touch/mobile).
  static const double gridRowHeightComfortable = 44;

  static const double gridHeaderHeight = 40;
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => _build(AppColors.dark, Brightness.dark);
  static ThemeData get lightTheme => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final textTheme = _textTheme(colors);
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.secondary,
      onSecondary: colors.onSecondary,
      error: colors.error,
      onError: colors.onError,
      surface: colors.surface,
      onSurface: colors.onSurface,
      outline: colors.outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      textTheme: textTheme,
      dividerColor: colors.outline,
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: brightness == Brightness.dark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
          side: brightness == Brightness.dark
              ? BorderSide(color: colors.outline)
              : BorderSide.none,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
          borderSide: BorderSide(color: colors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
          borderSide: BorderSide(color: colors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
          borderSide: BorderSide(color: colors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(colors.surfaceVariant),
        headingRowHeight: AppSpacing.gridHeaderHeight,
        dataRowMinHeight: AppSpacing.gridRowHeightDense,
        dataRowMaxHeight: AppSpacing.gridRowHeightComfortable,
        headingTextStyle: textTheme.titleMedium,
        dataTextStyle: textTheme.bodyMedium,
        dividerThickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceVariant,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
      ),
      extensions: [colors],
    );
  }

  static TextTheme _textTheme(AppColors colors) {
    final base = GoogleFonts.interTextTheme();
    return base
        .copyWith(
          headlineLarge: base.headlineLarge?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: colors.onBackground,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: colors.onBackground,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          bodyLarge: base.bodyLarge?.copyWith(
            fontSize: 14,
            color: colors.onSurface,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            fontSize: 13,
            color: colors.onSurface,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: 12,
            color: colors.onSurfaceMuted,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceMuted,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(displayColor: colors.onBackground, bodyColor: colors.onSurface);
  }
}

/// Extensao de tema para acessar [AppColors] via `Theme.of(context)`.
extension AppThemeColorsX on ThemeData {
  AppColors get appColors =>
      extension<AppColors>() ?? AppColors.dark;
}
