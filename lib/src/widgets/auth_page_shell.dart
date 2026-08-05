import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/brand_mark.dart';
import 'package:flutter/material.dart';

/// Full-viewport account-entry composition without a branded page header.
class AuthPageShell extends StatelessWidget {
  const AuthPageShell({required this.child, this.maxWidth = 480, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ColoredBox(
      color: AppColors.alabaster,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppBreakpoints.medium;
          final form = SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              wide ? AppSpacing.xxxl : AppSpacing.lg,
              AppSpacing.xxl,
              wide ? AppSpacing.xxxl : AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: AppCard(
                  padding: EdgeInsets.all(
                    wide ? AppSpacing.xxxl : AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: AppSpacing.xxl),
                      child,
                      const SizedBox(height: AppSpacing.xxl),
                      const _AuthFootnote(),
                    ],
                  ),
                ),
              ),
            ),
          );
          if (!wide) return form;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxxl,
                    AppSpacing.xxl,
                    0,
                    AppSpacing.xxxl,
                  ),
                  child: const _AuthIntroPanel(),
                ),
              ),
              Expanded(flex: 6, child: form),
            ],
          );
        },
      ),
    ),
  );
}

class _AuthIntroPanel extends StatelessWidget {
  const _AuthIntroPanel();

  @override
  Widget build(BuildContext context) => AppCard(
    tone: AppCardTone.blue,
    borderRadius: AppRadius.feature,
    padding: const EdgeInsets.all(AppSpacing.xxxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppStatusBadge(
          label: 'PRIVATE CARE ACCESS',
          color: AppColors.sunflower,
          icon: AppIcons.lockOutlineRounded,
          inverse: true,
        ),
        const SizedBox(height: 64),
        Text(
          'A clearer way\nthrough the care system.',
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Keep verified hospitals, consultations, records, and next steps connected to one secure workspace.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.mist),
        ),
        const SizedBox(height: 64),
        Row(
          children: [
            const AppIconTile(
              icon: AppIcons.routeRounded,
              color: Colors.white,
              size: 54,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Navigate with confidence',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AuthFootnote extends StatelessWidget {
  const _AuthFootnote();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(AppIcons.lockOutlineRounded, size: 15),
      const SizedBox(width: AppSpacing.xs),
      Flexible(
        child: Text(
          'Encrypted access - scoped by role - session protected',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
