import 'package:flutter/material.dart';

/// Paleta neutra placeholder para task_manager_flutter_merged_final.
///
/// Este arquivo foi removido anteriormente (commit 7d7c698) por conter
/// a identidade visual específica do cliente (task_manager_flutter),
/// o que viola a regra do CLAUDE.md de não replicar cores/tema entre
/// os dois projetos. Porém código deste projeto ainda depende da API
/// GridColors/CustomColors para compilar — este placeholder restaura
/// a compilação com cores neutras (Material blue/gray) até que a
/// paleta definitiva do merged_final seja definida em tarefa de design.
class GridColors {
  // ── Cores adaptadas para dark theme (AppColors.dark) ──
  // O app roda em ThemeMode.dark — todas as cores seguem a paleta
  // "Control Room" definida em app_theme.dart (AppColors.dark).
  static const Color primary = Color(0xFF3B82F6);       // AppColors.dark.primary
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF60A5FA);   // AppColors.dark.primaryVariant
  static const Color primarySoft = Color(0xFF1A2744);    // primary 10% sobre fundo escuro
  static const Color secondary = Color(0xFFF59E0B);      // AppColors.dark.secondary
  static const Color secondaryLight = Color(0xFFFBBF24);
  static const Color secondarySoft = Color(0xFF1A1A0D);  // secondary 10% sobre fundo escuro
  static const Color secondaryDark = Color(0xFFB45309);
  static const Color accent = Color(0xFFF59E0B);         // = secondary (dark)
  static const Color accentDark = Color(0xFFB45309);
  static const Color textPrimary = Color(0xFFFFFFFF);    // branco — texto sobre botões/snackbars
  static const Color textPrimaryMuted = Color(0xB3FFFFFF);
  static const Color textSecondary = Color(0xFFDCE3F0);  // AppColors.dark.onSurface
  static const Color textMuted = Color(0xFF8B99B3);      // AppColors.dark.onSurfaceMuted
  static const Color link = Color(0xFF60A5FA);           // primaryVariant (legível no escuro)
  static const Color inputBackground = Color(0xFF17233D); // AppColors.dark.surfaceVariant
  static const Color inputBorder = Color(0xFF26324A);    // AppColors.dark.outline
  static const Color buttonBackground = Color(0xFF3B82F6);
  static const Color buttonText = Color(0xFFFFFFFF);
  static const Color background = Color(0xFF0B1220);     // AppColors.dark.background
  static const Color shellBackground = Color(0xFF0B1220);
  static const Color card = Color(0xFF111A2E);           // AppColors.dark.surface
  static const Color error = Color(0xFFEF4444);          // AppColors.dark.error
  static const Color warning = Color(0xFFF59E0B);        // AppColors.dark.warning
  static const Color success = Color(0xFF22C55E);        // AppColors.dark.success
  static const Color successLight = Color(0xFF052E11);   // AppColors.dark.onSuccess (dark bg)
  static const Color info = Color(0xFF38BDF8);           // AppColors.dark.info
  static const Color divider = Color(0xFF26324A);        // AppColors.dark.outline
  static const Color filterBackground = Color(0xFF17233D); // surfaceVariant
  static const Color gridHeader = Color(0xFF17233D);     // surfaceVariant
  static const Color rowEven = Color(0xFF111A2E);        // surface
  static const Color rowOdd = Color(0xFF0E1628);         // ligeiramente mais escuro que surface
  static const Color hover = Color(0x1A3B82F6);          // primary 10%
  static const Color selectedRow = Color(0xFF1A2744);    // primary bem suave
  static const Color errorLight = Color(0xFF1A0505);     // AppColors.dark.onError
  static const Color errorDark = Color(0xFFDC2626);
  static const Color successDark = Color(0xFF16A34A);
  static const Color warningDark = Color(0xFFB45309);
  static const Color neutral = Color(0xFF8B99B3);        // onSurfaceMuted
  static const Color borderSubtle = Color(0xFF26324A);   // outline
  static const Color statusHoliday = Color(0xFF3B82F6);
  static const Color statusClosed = Color(0xFF9333EA);
  static const Color statusNew = Color(0xFFF59E0B);
  // WCAG AA FIX — valor clareado pra contraste sobre fundo escuro.
  static const Color statusUnknown = Color(0xFFFBBF24);
  static const Color pageBackground = Color(0xFF0B1220); // background
  static const Color surfaceMuted = Color(0xFF17233D);   // surfaceVariant
  static const Color disabledBackground = Color(0xFF1A2336);
  static const Color suggestionHigh = Color(0xFF052E11);
  static const Color suggestionMedium = Color(0xFF1A1A0D);
  static const Color dialogBackground = Color(0xFF111A2E); // surface
  static const Color shadow = Color(0x40000000);

  /// Texto padrão de campos/valores — claro sobre fundo escuro.
  static const Color textDefault = Color(0xFFDCE3F0);   // onSurface

  /// Fundo alternativo (cards/inputs desabilitados) — tom escuro.
  static const Color surfaceAlt = Color(0xFF0E1628);

  // Cores por tipo de arquivo (GED) — tons claros/vibrantes legíveis no dark
  static const Color fileTypePdf = Color(0xFFEF4444);
  static const Color fileTypeImage = Color(0xFF38BDF8);
  static const Color fileTypeSheet = Color(0xFF22C55E);
  static const Color fileTypeWord = Color(0xFF818CF8);
  static const Color fileTypeDefault = Color(0xFF8B99B3);
}

class CustomColors {
  final Color _lightGreenBackground = GridColors.card;
  final Color _darkGreenBorder = GridColors.primary;
  final Color _buttonBackground = GridColors.buttonBackground;
  final Color _textColorDesc = GridColors.textMuted;
  final Color _borderInput = GridColors.inputBorder;
  final Color _textColor = GridColors.textSecondary;
  final Color _negotiationCardBackground = GridColors.card;
  final Color _confirmButtonColor = GridColors.success;
  final Color _cancelButtonColor = GridColors.error;
  final Color _buttonTextColor = GridColors.buttonText;
  final Color _darkBlue = GridColors.shellBackground;
  final Color _headerTable = GridColors.filterBackground;
  final Color _showSnackBarError = GridColors.error;
  final Color _showSnackBarSuccess = GridColors.success;
  final Color _showSnackBarWarning = GridColors.warning;
  final Color _showSnackBarInfo = GridColors.info;
  final Color _showSnackBarText = GridColors.textPrimary;

  Color getShowSnackBarText() {
    return _showSnackBarText;
  }

  Color getShowSnackBarInfo() {
    return _showSnackBarInfo;
  }

  Color getShowSnackBarWarning() {
    return _showSnackBarWarning;
  }

  Color getShowSnackBarSuccess() {
    return _showSnackBarSuccess;
  }

  Color getShowSnackBarError() {
    return _showSnackBarError;
  }

  getBorderInput() {
    return _borderInput;
  }

  getLightGreenBackground() {
    return _lightGreenBackground;
  }

  getDarkBlue() {
    return _darkBlue;
  }

  getDarkGreenBorder() {
    return _darkGreenBorder;
  }

  getButtonBackground() {
    return _buttonBackground;
  }

  getTextColorDesc() {
    return _textColorDesc;
  }

  getTextColor() {
    return _textColor;
  }

  getNegotiationCardBackground() {
    return _negotiationCardBackground;
  }

  getConfirmButtonColor() {
    return _confirmButtonColor;
  }

  getCancelButtonColor() {
    return _cancelButtonColor;
  }

  getButtonTextColor() {
    return _buttonTextColor;
  }

  getHeaderTable() {
    return _headerTable;
  }
}
