import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

class ContentPanel extends StatelessWidget {
  const ContentPanel({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.all(AppSpacing.x5),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || action != null) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = action != null && constraints.maxWidth < 620;
                  final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Semantics(
                          header: true,
                          child: Text(
                            title!,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heading,
                        const SizedBox(height: AppSpacing.x3),
                        action!,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: heading),
                      ?action,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.x4),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class StatusTag extends StatelessWidget {
  const StatusTag({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DataState extends StatelessWidget {
  const DataState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.liveRegion = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: AppColors.selected,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(height: 14),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (action != null) ...[const SizedBox(height: 18), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
