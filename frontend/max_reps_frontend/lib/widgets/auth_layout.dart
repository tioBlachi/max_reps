import 'package:flutter/material.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/widgets/brand_mark.dart';

// Both authentication pages share the same responsive frame and visual rhythm.
class AuthLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool canGoBack;
  final VoidCallback? onBack;

  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.canGoBack = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE6F5F4), AppColors.background, Color(0xFFFFF7EF)],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            return SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 40 : 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (canGoBack) ...[
                            IconButton(
                              tooltip: 'Back to sign in',
                              onPressed:
                                  onBack ??
                                  () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const BrandMark(),
                          const Spacer(),
                          if (wide)
                            const Text(
                              'MAKE EVERY REP COUNT',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                                color: AppColors.deepAqua,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: wide ? 80 : 36),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (wide) ...[
                            const Expanded(child: _Welcome()),
                            const SizedBox(width: 72),
                          ],
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 460,
                                ),
                                child: Card(
                                  child: Padding(
                                    padding: EdgeInsets.all(wide ? 36 : 24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          title,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.headlineMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(subtitle),
                                        const SizedBox(height: 28),
                                        child,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      const Text(
                        'A little data. A stronger direction.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Text(
          'YOUR STRENGTH, IN FOCUS',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Find your strength.\nBuild your next best.',
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w900,
          height: 1.12,
          letterSpacing: -1.5,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Turn the reps you lift into a clearer plan for what comes next.',
        style: TextStyle(fontSize: 18, height: 1.6, color: AppColors.muted),
      ),
      const SizedBox(height: 32),
      for (final feature in [
        (
          Icons.fitness_center_rounded,
          'Log your lift',
          'Choose an exercise, weight, and reps.',
        ),
        (
          Icons.insights_rounded,
          'Know your numbers',
          'Get your estimated max and training percentages.',
        ),
        (
          Icons.history_rounded,
          'Pick up where you left off',
          'Recall your latest saved estimate.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(feature.$1, color: AppColors.deepAqua),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.$2,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(feature.$3),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
