import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../branding/brand_mark.dart';

class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.showHospitalBackground = false,
    this.compactSpacing = false,
    this.footer,
    this.developerTools,
  });

  final String title;
  final String description;
  final Widget child;
  final bool showHospitalBackground;
  final bool compactSpacing;
  final Widget? footer;
  final Widget? developerTools;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cardPadding = width >= 600
        ? const EdgeInsets.symmetric(horizontal: 40, vertical: 36)
        : EdgeInsets.symmetric(
            horizontal: 20,
            vertical: compactSpacing ? 22 : 24,
          );
    final pagePadding = width < 420 ? 16.0 : (width < 600 ? 10.0 : 20.0);
    const borderRadius = BorderRadius.all(Radius.circular(AppRadius.control));

    final authInputTheme = theme.inputDecorationTheme.copyWith(
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: AppColors.focus, width: 2),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: AppColors.destructive),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: AppColors.destructive, width: 2),
      ),
    );

    return Theme(
      data: theme.copyWith(inputDecorationTheme: authInputTheme),
      child: _centeredLayout(context, cardPadding, pagePadding),
    );
  }

  Widget _centeredLayout(
    BuildContext context,
    EdgeInsets cardPadding,
    double pagePadding,
  ) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return ColoredBox(
      color: const Color(0xFFF2F9FB),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showHospitalBackground)
            Positioned.fill(
              child: ClipRect(
                child: Transform.scale(
                  scale: 1.18,
                  alignment: Alignment.bottomCenter,
                  child: Opacity(
                    opacity: .82,
                    child: Image.asset(
                      'assets/images/auth_hospital_background_v2.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: width < 600 && showHospitalBackground
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final topGap = compactSpacing
                          ? 18.0
                          : (constraints.maxHeight * .19)
                                .clamp(140.0, 190.0)
                                .toDouble();
                      return SingleChildScrollView(
                        padding: EdgeInsets.only(top: topGap),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - topGap,
                          ),
                          child: _buildCard(
                            theme,
                            cardPadding,
                            edgeToEdge: true,
                          ),
                        ),
                      );
                    },
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: pagePadding,
                        vertical: compactSpacing ? 18 : 28,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _buildCard(theme, cardPadding),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    ThemeData theme,
    EdgeInsets cardPadding, {
    bool edgeToEdge = false,
  }) => Card(
    margin: EdgeInsets.zero,
    elevation: 2,
    shadowColor: const Color(0x180C2734),
    color: theme.colorScheme.surface.withValues(alpha: 0.94),
    shape: RoundedRectangleBorder(
      borderRadius: edgeToEdge
          ? const BorderRadius.vertical(top: Radius.circular(12))
          : BorderRadius.circular(12),
      side: BorderSide(color: Colors.white.withValues(alpha: .7)),
    ),
    child: Padding(
      padding: cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BrandLockup()),
          SizedBox(height: compactSpacing ? 20 : 26),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          SizedBox(height: compactSpacing ? 24 : 32),
          child,
          if (footer != null) ...[
            SizedBox(height: compactSpacing ? 12 : 20),
            footer!,
          ],
          if (developerTools != null) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 8),
            developerTools!,
          ],
        ],
      ),
    ),
  );
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = onPressed == null
        ? FilledButton.styleFrom(
            disabledBackgroundColor: AppColors.border,
            disabledForegroundColor: AppColors.textSecondary,
          )
        : null;
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: buttonStyle,
        child: child,
      ),
    );
  }
}

class AuthSecondaryButton extends StatelessWidget {
  const AuthSecondaryButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton(onPressed: onPressed, child: child),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text('or', style: Theme.of(context).textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class AuthStatusMessage extends StatelessWidget {
  const AuthStatusMessage({
    super.key,
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.destructive : AppColors.success;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.task_alt_outlined,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
