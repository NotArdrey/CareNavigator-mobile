import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// The single responsive content boundary used by route compositions.
class ResponsivePageContainer extends StatelessWidget {
  const ResponsivePageContainer({
    required this.child,
    this.maxWidth = 1320,
    this.padding,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  static double horizontalPadding(double width) => switch (width) {
    < AppBreakpoints.compact => AppSpacing.lg,
    < AppBreakpoints.expanded => AppSpacing.xxl,
    _ => AppSpacing.xxxl,
  };

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : width;
        final containerWidth = availableWidth > maxWidth
            ? maxWidth
            : availableWidth;
        return Align(
          alignment: alignment,
          child: SizedBox(
            width: containerWidth,
            child: Padding(
              padding:
                  padding ??
                  EdgeInsets.symmetric(
                    horizontal: horizontalPadding(width),
                    vertical: width < AppBreakpoints.compact
                        ? AppSpacing.xl
                        : AppSpacing.xxxl,
                  ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Backward-compatible name while routes migrate to
/// [ResponsivePageContainer] individually.
class AppPageBody extends StatelessWidget {
  const AppPageBody({
    required this.child,
    this.maxWidth = 1320,
    this.padding,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  static double horizontalPadding(double width) =>
      ResponsivePageContainer.horizontalPadding(width);

  @override
  Widget build(BuildContext context) => ResponsivePageContainer(
    maxWidth: maxWidth,
    padding: padding,
    alignment: alignment,
    child: child,
  );
}

enum AppCardTone { paper, soft, mint, coral, blue, dark }

/// Intentional surface primitive. Unlike Material [Card], tone and elevation
/// communicate hierarchy instead of every item receiving the same treatment.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.tone = AppCardTone.paper,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.borderRadius = AppRadius.extraLarge,
    super.key,
  });

  final Widget child;
  final AppCardTone tone;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border, elevation) = switch (tone) {
      AppCardTone.paper => (
        AppColors.paper,
        AppColors.ink,
        AppColors.outline,
        0.0,
      ),
      AppCardTone.soft => (
        AppColors.fog,
        AppColors.ink,
        Colors.transparent,
        0.0,
      ),
      AppCardTone.mint => (
        AppColors.seaGlass,
        AppColors.evergreenDark,
        Colors.transparent,
        0.0,
      ),
      AppCardTone.coral => (
        const Color(0xFFFFF4EE),
        AppColors.ink,
        AppColors.outline,
        0.0,
      ),
      AppCardTone.blue => (
        AppColors.forest,
        Colors.white,
        Colors.transparent,
        0.0,
      ),
      AppCardTone.dark => (
        AppColors.evergreenDark,
        Colors.white,
        Colors.transparent,
        0.0,
      ),
    };
    final radius = BorderRadius.circular(borderRadius);
    return Material(
      color: background,
      textStyle: DefaultTextStyle.of(context).style.copyWith(color: foreground),
      elevation: elevation,
      shadowColor: AppColors.evergreenDark.withValues(alpha: .12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

enum AppButtonStyle { primary, secondary, quiet, danger }

/// Standard action primitive with shared size, icon placement, and loading
/// behavior.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = AppButtonStyle.primary,
    this.loading = false,
    this.expand = false,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonStyle style;
  final bool loading;
  final bool expand;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final callback = loading ? null : onPressed;
    final content = loading
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
    final button = switch (style) {
      AppButtonStyle.primary => FilledButton(
        onPressed: callback,
        style: backgroundColor == null && foregroundColor == null
            ? null
            : FilledButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
              ),
        child: content,
      ),
      AppButtonStyle.secondary => OutlinedButton(
        onPressed: callback,
        style: foregroundColor == null
            ? null
            : OutlinedButton.styleFrom(foregroundColor: foregroundColor),
        child: content,
      ),
      AppButtonStyle.quiet => TextButton(
        onPressed: callback,
        style: foregroundColor == null
            ? null
            : TextButton.styleFrom(foregroundColor: foregroundColor),
        child: content,
      ),
      AppButtonStyle.danger => FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.danger,
          foregroundColor: foregroundColor,
        ),
        child: content,
      ),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Labeled, filled form control. Labels live outside the field so they remain
/// visible after entry and validation.
class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.prefixIcon,
    this.suffix,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.onSubmitted,
    this.onChanged,
    this.labelColor,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final IconData? prefixIcon;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool enabled;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: labelColor ?? AppColors.evergreenDark,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        autofillHints: autofillHints,
        obscureText: obscureText,
        enabled: enabled,
        maxLines: maxLines,
        validator: validator,
        onFieldSubmitted: onSubmitted,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
          suffixIcon: suffix,
        ),
      ),
      if (helper != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(helper!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ],
  );
}

/// Consistent section identity with optional eyebrow and trailing action.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(
                eyebrow!.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.forest,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle!),
            ],
          ],
        ),
      ),
      if (action != null) ...[const SizedBox(width: AppSpacing.md), action!],
    ],
  );
}

class AppIconTile extends StatelessWidget {
  const AppIconTile({
    required this.icon,
    this.color,
    this.size = 44,
    this.circular = false,
    super.key,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .11),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular
            ? null
            : BorderRadius.circular(AppRadius.extraLarge),
      ),
      child: Icon(icon, color: accent, size: size * .48),
    );
  }
}

class AppNotice extends StatelessWidget {
  const AppNotice({
    required this.message,
    required this.icon,
    this.color,
    this.title,
    super.key,
  });

  final String message;
  final String? title;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    final surface = switch (accent) {
      AppColors.danger || AppColors.coral => const Color(0xFFFFF4EE),
      AppColors.warning => const Color(0xFFFFF8E8),
      _ => accent.withValues(alpha: .06),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    required this.label,
    required this.color,
    this.icon,
    this.inverse = false,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool inverse;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: inverse
          ? Colors.white.withValues(alpha: .12)
          : color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: inverse ? Colors.white : color),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Text(
          label,
          style: TextStyle(
            color: inverse ? Colors.white : color,
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// Shared grouped-list row used instead of one card per item.
class AppListRow extends StatelessWidget {
  const AppListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: leading,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: trailing,
  );
}

/// Shared modal composition used for confirmation, safety, and edit flows.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.content,
    this.eyebrow,
    this.icon,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? eyebrow;
  final IconData? icon;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
    titlePadding: EdgeInsets.zero,
    contentPadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
    actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    title: Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.evergreenDark,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.extraLarge),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.forest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.mint,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .9,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    content: content,
    actions: actions,
  );
}

/// Shared responsive bottom-sheet surface for compact-screen task flows.
class AppModalSheet extends StatelessWidget {
  const AppModalSheet({
    required this.title,
    required this.child,
    this.eyebrow,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        AppPageBody.horizontalPadding(MediaQuery.sizeOf(context).width),
        AppSpacing.sm,
        AppPageBody.horizontalPadding(MediaQuery.sizeOf(context).width),
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: title, eyebrow: eyebrow),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    ),
  );
}

class AppModuleDestination {
  const AppModuleDestination({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Desktop operations composition with a persistent module rail and one
/// focused canvas. Used by dense administration workspaces.
class AppModuleLayout extends StatelessWidget {
  const AppModuleLayout({
    required this.eyebrow,
    required this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
    this.summary,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String? summary;
  final List<AppModuleDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = AppPageBody.horizontalPadding(width);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding,
        AppSpacing.lg,
        padding,
        AppSpacing.xl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 278,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.evergreenDark,
              borderRadius: BorderRadius.circular(AppRadius.extraLarge),
              boxShadow: AppShadows.medium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppStatusBadge(
                  label: eyebrow,
                  color: AppColors.mint,
                  icon: AppIcons.lockRounded,
                  inverse: true,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                if (summary != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    summary!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.mist),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'MODULES',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.mist,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: destinations.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xxs),
                    itemBuilder: (context, index) {
                      final destination = destinations[index];
                      final active = index == selectedIndex;
                      return Material(
                        color: active ? AppColors.forest : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        child: InkWell(
                          onTap: () => onSelected(index),
                          borderRadius: BorderRadius.circular(AppRadius.medium),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  destination.icon,
                                  color: active ? Colors.white : AppColors.mint,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    destination.label,
                                    style: TextStyle(
                                      color: active
                                          ? Colors.white
                                          : AppColors.mist,
                                      fontWeight: active
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(AppRadius.extraLarge),
                border: Border.all(color: AppColors.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
