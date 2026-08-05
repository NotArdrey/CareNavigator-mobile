import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:flutter/material.dart';

enum AppStateKind { empty, error, restricted }

/// Full-region empty state with visual mass appropriate to the page it
/// replaces. It intentionally does not look like another small content card.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    required this.message,
    this.icon = AppIcons.inboxOutlined,
    this.kind = AppStateKind.empty,
    this.accentColor,
    this.action,
    this.compact = false,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final AppStateKind kind;
  final Color? accentColor;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent =
        accentColor ??
        switch (kind) {
          AppStateKind.error => AppColors.danger,
          AppStateKind.restricted => AppColors.warning,
          AppStateKind.empty => AppColors.forest,
        };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: compact ? 82 : 112,
                    height: compact ? 82 : 112,
                    decoration: BoxDecoration(
                      color: AppColors.fog,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Transform.rotate(
                    angle: -.12,
                    child: Container(
                      width: compact ? 52 : 68,
                      height: compact ? 52 : 68,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: compact ? 26 : 34,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.inkMuted),
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compatibility surface while routes migrate from AppStatePanel naming.
class AppStatePanel extends StatelessWidget {
  const AppStatePanel({
    required this.title,
    required this.message,
    this.icon = AppIcons.inboxOutlined,
    this.kind = AppStateKind.empty,
    this.accentColor,
    this.action,
    this.compact = false,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final AppStateKind kind;
  final Color? accentColor;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) => AppEmptyState(
    title: title,
    message: message,
    icon: icon,
    kind: kind,
    accentColor: accentColor,
    action: action,
    compact: compact,
  );
}

/// Shared loading composition: progress, label, and softly pulsing skeleton
/// rows communicate what region is loading instead of a lone spinner.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({this.label = 'Preparing your workspace…', super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: label,
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: AppCard(
          tone: AppCardTone.soft,
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const _Skeleton(widthFactor: .82),
              const SizedBox(height: AppSpacing.sm),
              const _Skeleton(widthFactor: 1),
              const SizedBox(height: AppSpacing.sm),
              const _Skeleton(widthFactor: .58),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: widthFactor,
    child: Container(
      height: 12,
      decoration: BoxDecoration(
        color: AppColors.outline.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}
