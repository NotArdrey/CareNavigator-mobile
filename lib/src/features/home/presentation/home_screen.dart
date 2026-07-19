import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/brand_mark.dart';
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
    final horizontal = width < 600 ? 20.0 : 40.0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (width < 920) ...[
                    Row(
                      children: [
                        const BrandMark(),
                        const Spacer(),
                        if (!isSignedIn) ...[
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: const Text('Sign in'),
                          ),
                          IconButton(
                            tooltip: 'Register',
                            onPressed: () => context.go('/register'),
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],
                  _HeroPanel(isCompact: width < 720),
                  const SizedBox(height: 26),
                  const _EmergencyBanner(),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'How can we help?',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      hospitals.when(
                        data: (items) =>
                            Text('${items.length} verified hospitals'),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 40),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: width >= 1180
                  ? 3
                  : width >= 660
                  ? 2
                  : 1,
              mainAxisExtent: 184,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            delegate: SliverChildListDelegate.fixed([
              _ActionCard(
                icon: Icons.local_hospital_rounded,
                color: AppColors.blue,
                title: 'Find the right hospital',
                description:
                    'Compare services, specialists, ER status, beds, and rooms.',
                label: 'Browse hospitals',
                onTap: () => context.go('/hospitals'),
              ),
              _ActionCard(
                icon: Icons.video_call_rounded,
                color: AppColors.teal,
                title: 'Consult a doctor',
                description:
                    'Verify your email and request a first-time online consultation.',
                label: 'Start request',
                onTap: () => context.go('/consult'),
              ),
              _ActionCard(
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF6A4BBC),
                title: 'Check your symptoms',
                description:
                    'Get a preliminary urgency and care-direction assessment—never a diagnosis.',
                label: 'Start assessment',
                onTap: () => context.go('/assessment'),
              ),
              _ActionCard(
                icon: Icons.monitor_heart_rounded,
                color: const Color(0xFFD05A29),
                title: 'Your care in one place',
                description:
                    'Review consultations, records, results, and prescriptions securely.',
                label: 'Open my care',
                onTap: () => context.go('/care'),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'HEALTHCARE NAVIGATION FOR EVERY FILIPINO',
            style: TextStyle(
              color: AppColors.teal,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Know where to go.\nGet care with confidence.',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 14),
        const Text(
          'Find verified hospitals, check live availability, and connect with the right healthcare professional.',
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () => context.go('/hospitals'),
              icon: const Icon(Icons.search),
              label: const Text('Find a hospital'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/consult'),
              icon: const Icon(Icons.video_call_outlined),
              label: const Text('Consult online'),
            ),
          ],
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isCompact ? 24 : 38),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFEAF3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE8F6)),
      ),
      child: isCompact
          ? content
          : Row(
              children: [
                Expanded(flex: 6, child: content),
                const SizedBox(width: 30),
                const Expanded(flex: 4, child: _HeroIllustration()),
              ],
            ),
    );
  }
}

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.15,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -40,
              child: _Orb(
                size: 150,
                color: AppColors.teal.withValues(alpha: 0.35),
              ),
            ),
            Positioned(
              left: -25,
              bottom: -35,
              child: _Orb(
                size: 130,
                color: AppColors.blue.withValues(alpha: 0.45),
              ),
            ),
            const Center(
              child: Icon(
                Icons.health_and_safety_rounded,
                color: Colors.white,
                size: 92,
              ),
            ),
            const Positioned(
              left: 22,
              right: 22,
              bottom: 20,
              child: Text(
                'Hospitals • Doctors • Care',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD0CC)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.emergency_rounded, color: AppColors.danger),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Severe breathing difficulty, chest pain, stroke signs, heavy bleeding, seizures, or loss of consciousness? Call 911 or go to the nearest emergency room now.',
              style: TextStyle(
                color: Color(0xFF7A211B),
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
