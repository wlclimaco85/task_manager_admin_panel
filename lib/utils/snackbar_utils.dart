import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import 'grid_colors.dart';

class SnackbarUtils {
  SnackbarUtils._();

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, GridColors.success, Icons.check_circle_outline);
  }

  static void showError(BuildContext context, String message) {
    _show(context, message, GridColors.error, Icons.error_outline);
  }

  static void showWarning(BuildContext context, String message) {
    _show(context, message, GridColors.warning, Icons.warning_amber_outlined);
  }

  static void showInfo(BuildContext context, String message) {
    _show(context, message, GridColors.info, Icons.info_outline);
  }

  static void _show(
    BuildContext context,
    String message,
    Color backgroundColor,
    IconData icon,
  ) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
