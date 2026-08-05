import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared route header with one stable identity row and an optional action row.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.icon,
    this.leading,
    this.onBack,
    this.backTooltip,
    this.actions = const [],
    this.secondaryActions = const [],
    this.showProfileAction = true,
    this.backgroundColor,
    super.key,
  });

  static const height = 92.0;
  static const mobileHeight = 64.0;
  static const _headerPadding = EdgeInsets.fromLTRB(20, 14, 20, 16);
  static const _leadingSize = 44.0;
  static const _iconGraphicSize = 22.0;
  static const _actionSize = 40.0;
  static const _titleSize = 20.0;
  static const _titleLineHeight = 24.0 / _titleSize;
  static const _subtitleSize = 13.0;
  static const _subtitleLineHeight = 18.0 / _subtitleSize;
  static const _eyebrowLineHeight = 16.0 / 12.0;

  final String title;
  final String subtitle;
  final String? eyebrow;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onBack;
  final String? backTooltip;
  final List<Widget> actions;
  final List<Widget> secondaryActions;
  final bool showProfileAction;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppBreakpoints.compact;
    if (compact) return _mobileHeader(context);

    final topActions = _headerActions(context);
    final bottomActions = secondaryActions;
    return Material(
      color: backgroundColor ?? AppColors.alabaster,
      surfaceTintColor: Colors.transparent,
      child: ResponsivePageContainer(
        padding: _headerPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _identity(context)),
                if (topActions.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.md),
                  _actionRow(topActions),
                ],
              ],
            ),
            if (bottomActions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: _actionRow(bottomActions),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mobileHeader(BuildContext context) => Material(
    color: backgroundColor ?? AppColors.paper,
    surfaceTintColor: Colors.transparent,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Builder(
          builder: (context) {
            final headerActions = _headerActions(context);
            final topActions = headerActions
                .where(_isMobilePrimaryAction)
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (onBack != null) ...[
                      _mobileLeading(),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    const _MobileBrand(),
                    const Spacer(),
                    if (topActions.isNotEmpty)
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _actionRow(
                            topActions
                                .map(_mobileAction)
                                .toList(growable: false),
                            spacing: 0,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _mobileLeading() => SizedBox.square(
    dimension: _actionSize,
    child: IconButton(
      tooltip: backTooltip ?? 'Back',
      onPressed: onBack,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(_actionSize),
        maximumSize: const Size.square(_actionSize),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.fog,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      icon: const Icon(AppIcons.arrowBackRounded),
    ),
  );

  bool _isMobilePrimaryAction(Widget action) => action is IconButton;

  Widget _mobileAction(Widget action) => SizedBox.square(
    dimension: _actionSize,
    child: IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(_actionSize),
          maximumSize: const Size.square(_actionSize),
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.ink,
          iconSize: 22,
        ),
      ),
      child: action,
    ),
  );

  List<Widget> _headerActions(BuildContext context) => [
    ...actions,
    if (showProfileAction)
      IconButton(
        tooltip: 'Profile',
        onPressed: () => context.go('/profile'),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(_actionSize),
          maximumSize: const Size.square(_actionSize),
          padding: EdgeInsets.zero,
          foregroundColor: AppColors.ink,
          iconSize: 22,
        ),
        icon: const Icon(AppIcons.profile),
      ),
  ];

  Widget _identity(BuildContext context) => Row(
    children: [
      if (onBack != null) ...[
        SizedBox.square(
          dimension: _actionSize,
          child: IconButton.filledTonal(
            tooltip: backTooltip ?? 'Back',
            onPressed: onBack,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(_actionSize),
              maximumSize: const Size.square(_actionSize),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            icon: const Icon(AppIcons.arrowBackRounded),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      leading ??
          SizedBox.square(
            dimension: _leadingSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.seaGlass,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Icon(
                icon ?? AppIcons.healthAndSafetyRounded,
                size: _iconGraphicSize,
                color: AppColors.forest,
              ),
            ),
          ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Semantics(
          header: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null)
                Text(
                  eyebrow!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.forest,
                    fontSize: 12,
                    height: _eyebrowLineHeight,
                    letterSpacing: 1.1,
                  ),
                )
              else
                const SizedBox(height: 16),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: _titleSize,
                  height: _titleLineHeight,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: _subtitleSize,
                  height: _subtitleLineHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _actionRow(List<Widget> items, {double spacing = AppSpacing.xs}) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: spacing,
      runSpacing: spacing,
      children: items,
    );
  }
}

class _MobileBrand extends StatelessWidget {
  const _MobileBrand();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.forest,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: const Icon(AppIcons.navigation, color: Colors.white, size: 19),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        'CareNavigator',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: -.3,
        ),
      ),
    ],
  );
}
