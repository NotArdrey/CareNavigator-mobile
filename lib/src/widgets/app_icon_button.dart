import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Accessible square icon-only action with consistent interaction states.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.loading = false,
    this.size = 20,
    this.foregroundColor,
    this.backgroundColor,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool loading;
  final double size;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveBackground = selected
        ? colors.primaryContainer
        : backgroundColor;
    final effectiveForeground = selected
        ? colors.primary
        : foregroundColor ?? colors.onSurfaceVariant;
    return Semantics(
      button: true,
      enabled: onPressed != null && !loading,
      selected: selected,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: loading ? null : onPressed,
        isSelected: selected,
        iconSize: size,
        style: IconButton.styleFrom(
          foregroundColor: effectiveForeground,
          backgroundColor: effectiveBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
        icon: loading
            ? SizedBox.square(
                dimension: size,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
      ),
    );
  }
}
