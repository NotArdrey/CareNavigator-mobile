import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider);
    final isSignedIn =
        ref.read(supabaseClientProvider).auth.currentSession != null;
    final hospitals = ref.watch(hospitalsProvider(''));
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;
    final hospitalCount = hospitals.maybeWhen(
      data: (items) => items.length,
      orElse: () => null,
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: _PublicTopBar(isSignedIn: isSignedIn),
          ),
        ),
        SliverToBoxAdapter(
          child: ResponsivePageContainer(
            padding: EdgeInsets.fromLTRB(
              ResponsivePageContainer.horizontalPadding(width),
              compact ? AppSpacing.sm : AppSpacing.lg,
              ResponsivePageContainer.horizontalPadding(width),
              AppSpacing.massive,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LandingHero(compact: compact, hospitalCount: hospitalCount),
                const SizedBox(height: AppSpacing.lg),
                const _EmergencyStrip(),
                SizedBox(
                  height: compact ? AppSpacing.xxxl : AppSpacing.massive,
                ),
                AppSectionHeader(
                  eyebrow: 'Choose your next step',
                  title: 'Care starts with the right direction.',
                  subtitle:
                      'Each path is designed around a specific healthcare task—not a generic dashboard.',
                  action: compact
                      ? null
                      : hospitals.when(
                          data: (items) => AppStatusBadge(
                            label: '${items.length} VERIFIED FACILITIES',
                            color: AppColors.forest,
                            icon: AppIcons.verifiedRounded,
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _CarePathGrid(compact: compact),
                SizedBox(
                  height: compact ? AppSpacing.xxxl : AppSpacing.massive,
                ),
                const _CareContinuityBand(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PublicTopBar extends StatelessWidget {
  const _PublicTopBar({required this.isSignedIn});

  final bool isSignedIn;

  @override
  Widget build(BuildContext context) => AppPageHeader(
    eyebrow: isSignedIn ? 'YOUR CARE NAVIGATOR' : 'PUBLIC CARE NAVIGATOR',
    title: 'Healthcare choices, made clearer.',
    subtitle:
        'Verified hospitals, consultations, and care guidance in one place.',
    icon: AppIcons.publicRounded,
  );
}

class _LandingHero extends StatelessWidget {
  const _LandingHero({required this.compact, required this.hospitalCount});

  final bool compact;
  final int? hospitalCount;

  @override
  Widget build(BuildContext context) {
    final introduction = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const AppStatusBadge(
          label: 'CARE ATLAS · CENTRAL LUZON',
          color: AppColors.forest,
          icon: AppIcons.nearMeOutlined,
        ),
        SizedBox(height: compact ? AppSpacing.xl : AppSpacing.xxl),
        Text(
          'Know what care you need.\nKnow where to find it.',
          style:
              (compact
                      ? Theme.of(context).textTheme.displaySmall
                      : Theme.of(context).textTheme.displayLarge)
                  ?.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 630),
          child: Text(
            'Compare verified hospitals, understand the right level of care, and connect with a clinician from one trusted guide.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.inkMuted,
              fontSize: compact ? 15 : 18,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppButton(
              label: 'Find a hospital',
              icon: AppIcons.searchRounded,
              onPressed: () => context.go('/hospitals'),
            ),
            AppButton(
              label: 'Check symptoms',
              icon: AppIcons.symptomCheck,
              style: AppButtonStyle.secondary,
              onPressed: () => context.go('/assessment'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.xxl,
          runSpacing: AppSpacing.md,
          children: [
            _HeroMetric(
              value: hospitalCount?.toString() ?? '—',
              label: 'verified facilities',
            ),
            const _HeroMetric(value: '3', label: 'levels of care'),
            const _HeroMetric(value: '24/7', label: 'navigation access'),
          ],
        ),
      ],
    );

    return AppCard(
      tone: AppCardTone.paper,
      borderRadius: AppRadius.feature,
      padding: EdgeInsets.all(compact ? AppSpacing.xl : AppSpacing.xxxl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (compact || constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                introduction,
                const SizedBox(height: AppSpacing.xl),
                const _HeroNavigator(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 13, child: introduction),
              const SizedBox(width: AppSpacing.xxxl),
              const Expanded(flex: 8, child: _HeroNavigator()),
            ],
          );
        },
      ),
    );
  }
}

class _HeroNavigator extends StatelessWidget {
  const _HeroNavigator();

  @override
  Widget build(BuildContext context) => AppCard(
    tone: AppCardTone.blue,
    padding: const EdgeInsets.all(AppSpacing.xl),
    borderRadius: AppRadius.extraLarge,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppIconTile(icon: AppIcons.routeRounded, color: Colors.white),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'What do you need today?',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _NavigatorRow(
          icon: AppIcons.localHospitalOutlined,
          label: 'Compare facilities',
          inverse: true,
          detail: 'Services · ER · capacity',
          onTap: () => context.go('/hospitals'),
        ),
        const Divider(color: Color(0x38FFFFFF)),
        _NavigatorRow(
          icon: AppIcons.videoCallOutlined,
          label: 'Request a consultation',
          inverse: true,
          detail: 'First-time online care',
          onTap: () => context.go('/consult'),
        ),
        const Divider(color: Color(0x38FFFFFF)),
        _NavigatorRow(
          icon: AppIcons.healthAndSafetyOutlined,
          label: 'Understand urgency',
          inverse: true,
          detail: 'Guidance, never diagnosis',
          onTap: () => context.go('/assessment'),
        ),
      ],
    ),
  );
}

class _NavigatorRow extends StatelessWidget {
  const _NavigatorRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.inverse = false,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final bool inverse;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.extraLarge),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: inverse ? Colors.white : AppColors.forest),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: inverse ? Colors.white : null,
                  ),
                ),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: inverse ? AppColors.mist : null,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            AppIcons.arrowOutwardRounded,
            size: 19,
            color: inverse ? Colors.white : AppColors.ink,
          ),
        ],
      ),
    ),
  );
}

class _EmergencyStrip extends StatelessWidget {
  const _EmergencyStrip();

  @override
  Widget build(BuildContext context) => const AppNotice(
    title: 'Emergency symptoms',
    icon: AppIcons.emergencyRounded,
    color: AppColors.danger,
    message:
        'For chest pain, stroke signs, severe breathing difficulty, heavy bleeding, or loss of consciousness, call 911 now.',
  );
}

class _CarePathGrid extends StatelessWidget {
  const _CarePathGrid({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hospital = _PathFeature(
      eyebrow: 'FACILITY FINDER',
      title: 'Compare capability, not just distance.',
      description:
          'See verified service levels, emergency status, room capacity, and directions before you travel.',
      icon: AppIcons.localHospitalRounded,
      tone: AppCardTone.mint,
      action: 'Explore hospitals',
      onTap: () => context.go('/hospitals'),
    );
    final consult = _PathFeature(
      eyebrow: 'ONLINE CONSULTATION',
      title: 'Meet the right clinician.',
      description:
          'Submit a guided first-time request and continue care securely.',
      icon: AppIcons.videoCallRounded,
      tone: AppCardTone.mint,
      action: 'Start a request',
      onTap: () => context.go('/consult'),
      compact: true,
    );
    final assessment = _PathFeature(
      eyebrow: 'CARE DIRECTION',
      title: 'Understand how urgent it may be.',
      description: 'Use a preliminary navigation assessment—never a diagnosis.',
      icon: AppIcons.symptomCheck,
      tone: AppCardTone.mint,
      action: 'Check symptoms',
      onTap: () => context.go('/assessment'),
      compact: true,
    );
    if (compact) {
      return Column(
        children: [
          hospital,
          const SizedBox(height: AppSpacing.md),
          consult,
          const SizedBox(height: AppSpacing.md),
          assessment,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 7, child: hospital),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Expanded(child: consult),
                const SizedBox(height: AppSpacing.lg),
                Expanded(child: assessment),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PathFeature extends StatelessWidget {
  const _PathFeature({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.tone,
    required this.action,
    required this.onTap,
    this.compact = false,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final AppCardTone tone;
  final String action;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => AppCard(
    tone: tone,
    onTap: onTap,
    padding: EdgeInsets.all(compact ? AppSpacing.xl : AppSpacing.xxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconTile(
              icon: icon,
              color: AppColors.forest,
              size: compact ? 44 : 56,
            ),
            const Spacer(),
            const Icon(AppIcons.arrowOutwardRounded),
          ],
        ),
        SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xxxl),
        Text(
          eyebrow,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.forest,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          title,
          style: compact
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(description),
        const SizedBox(height: AppSpacing.lg),
        Text(
          action,
          style: const TextStyle(
            color: AppColors.forest,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _CareContinuityBand extends StatelessWidget {
  const _CareContinuityBand();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 700;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Already receiving care?',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Appointments, records, laboratory results, prescriptions, and messages stay together in your private workspace.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xFFD2E0DB)),
          ),
        ],
      );
      return AppCard(
        tone: AppCardTone.blue,
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Open my care',
                    icon: AppIcons.arrowForwardRounded,
                    backgroundColor: AppColors.ink,
                    foregroundColor: Colors.white,
                    onPressed: () => context.go('/care'),
                  ),
                ],
              )
            : Row(
                children: [
                  const AppIconTile(
                    icon: AppIcons.monitorHeartRounded,
                    color: Colors.white,
                    size: 58,
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(child: content),
                  const SizedBox(width: AppSpacing.xl),
                  AppButton(
                    label: 'Open my care workspace',
                    icon: AppIcons.arrowForwardRounded,
                    backgroundColor: AppColors.ink,
                    foregroundColor: Colors.white,
                    onPressed: () => context.go('/care'),
                  ),
                ],
              ),
      );
    },
  );
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: AppColors.ink),
      ),
      Text(label, style: const TextStyle(color: AppColors.inkMuted)),
    ],
  );
}
