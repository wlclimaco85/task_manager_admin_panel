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
  static const Color primary = Color(0xFF1565C0);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color primaryLight = Color(0xFF5E92F3);
  static const Color primarySoft = Color(0xFFE3F2FD);
  static const Color secondary = Color(0xFF37474F);
  static const Color secondaryLight = Color(0xFF62727B);
  static const Color secondarySoft = Color(0xFFECEFF1);
  static const Color secondaryDark = Color(0xFF102027);
  static const Color accent = Color(0xFF37474F);
  static const Color accentDark = Color(0xFF102027);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textPrimaryMuted = Color(0xB3FFFFFF);
  static const Color textSecondary = Color(0xFF212121);
  static const Color textMuted = Color(0xFF757575);
  static const Color link = Color(0xFF1565C0);
  static const Color inputBackground = Color(0xFFFFFFFF);
  static const Color inputBorder = Color(0xFF1565C0);
  static const Color buttonBackground = Color(0xFF1565C0);
  static const Color buttonText = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F5F5);
  static const Color shellBackground = Color(0xFF0D47A1);
  static const Color card = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFFFA000);
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color info = Color(0xFF1976D2);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color filterBackground = Color(0xFFF3F3F3);
  static const Color gridHeader = Color(0xFFF3F3F3);
  static const Color rowEven = Color(0xFFFFFFFF);
  static const Color rowOdd = Color(0xFFF5F5F5);
  static const Color hover = Color(0x1A1565C0);
  static const Color selectedRow = Color(0xFFE3F2FD);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color errorDark = Color(0xFFB71C1C);
  static const Color successDark = Color(0xFF1B5E20);
  static const Color warningDark = Color(0xFFE65100);
  static const Color neutral = Color(0xFF757575);
  static const Color borderSubtle = Color(0xFFDDDDDD);
  static const Color statusHoliday = Color(0xFF1565C0);
  static const Color statusClosed = Color(0xFF6A1B9A);
  static const Color statusNew = Color(0xFFFF9800);
  // WCAG AA FIX (card P2-502, achado do QA de 11/08/2026, revisado no code
  // review da 4a tentativa - WR-02): 0xFFFFA000 (mesmo tom de `warning`)
  // usado como cor de TEXTO no badge "Desconhecimento da Operação"
  // (manifestacao_destinatario_screen.dart) media ~1.9:1 de contraste --
  // muito abaixo do minimo WCAG AA 4.5:1 para texto pequeno. O fundo real
  // do badge e este mesmo tom com opacidade 10% (`cor.withOpacity(0.1)`)
  // composto sobre o fundo da tela (claro) -- o resultado composto fica
  // proximo do branco, entao a aproximacao contra branco solido (~6.5:1)
  // e valida na pratica, mas nao e exata: se a opacidade do badge ou o
  // fundo da tela mudarem, reconferir contraste contra a cor composta
  // real, nao so contra branco. Usado APENAS pelas telas de Manifestacao
  // (confirmado por grep), escurecido aqui para ~6.5:1 sem trocar a
  // familia de cor (continua ambar/laranja, so mais escuro). Nao afeta
  // nenhuma outra tela. Fix replicado do task_manager_flutter (mesmo
  // valor, independente da paleta de branding deste projeto — não é cor
  // de identidade visual).
  static const Color statusUnknown = Color(0xFF8B5000);
  static const Color pageBackground = Color(0xFFF5F5F5);
  static const Color surfaceMuted = Color(0xFFF3F3F3);
  static const Color disabledBackground = Color(0xFFE0E0E0);
  static const Color suggestionHigh = Color(0xFFE8F5E9);
  static const Color suggestionMedium = Color(0xFFFFF8E1);
  static const Color dialogBackground = Color(0xFFFFFFFF);
  static const Color shadow = Color(0x261565C0);

  /// Texto padrão de campos/valores (cinza-escuro quase preto). Token
  /// adicionado para centralizar um valor (0xFF212121) que antes existia
  /// duplicado como constante local em algumas telas (ex: nfse_detail_screen).
  /// Não altera nenhuma cor renderizada — apenas referencia o mesmo valor
  /// neutro já usado localmente neste projeto.
  static const Color textDefault = Color(0xFF212121);

  /// Fundo alternativo claro (cards/inputs desabilitados). Token adicionado
  /// para centralizar um valor (0xFFF5F5F5) que antes existia duplicado
  /// como constante local em algumas telas.
  static const Color surfaceAlt = Color(0xFFF5F5F5);

  // Cores por tipo de arquivo (GED)
  static const Color fileTypePdf = Colors.red;
  static const Color fileTypeImage = Colors.blue;
  static const Color fileTypeSheet = Colors.green;
  static const Color fileTypeWord = Colors.indigo;
  static const Color fileTypeDefault = Colors.grey;
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
