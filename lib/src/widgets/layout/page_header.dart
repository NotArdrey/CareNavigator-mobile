import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.description,
    this.actions = const [],
    this.descriptionSpacing = AppSpacing.x2,
  });

  final String title;
  final String description;
  final List<Widget> actions;
  final double descriptionSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 680 ||
            (actions.length >= 3 && constraints.maxWidth < 920);
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            SizedBox(height: descriptionSpacing),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
        if (compact || actions.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x4),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.x6),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        );
      },
    );
  }
}

class PageContent extends StatelessWidget {
  const PageContent({
    super.key,
    required this.child,
    this.maxWidth = 1440,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 600
        ? 16.0
        : width < 1000
        ? 24.0
        : 32.0;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding:
              padding ?? EdgeInsets.fromLTRB(horizontal, 24, horizontal, 40),
          child: child,
        ),
      ),
    );
  }
}
