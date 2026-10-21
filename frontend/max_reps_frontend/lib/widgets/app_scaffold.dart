import 'package:flutter/material.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/widgets/brand_mark.dart';

enum WorkspaceSection { training, profile }

class AppScaffold extends StatelessWidget {
  final AuthState authState;
  final Widget body;
  final bool busy;
  final WorkspaceSection section;
  final ValueChanged<WorkspaceSection>? onNavigate;
  final Widget? floatingActionButton;

  const AppScaffold({
    super.key,
    required this.authState,
    required this.body,
    this.busy = false,
    this.section = WorkspaceSection.training,
    this.onNavigate,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final admin = authState.user?.isAdmin == true;
    final disabled = busy || authState.isLoading;
    void navigate(WorkspaceSection destination) {
      Navigator.of(context).pop();
      onNavigate?.call(destination);
    }

    return Scaffold(
      appBar: AppBar(
        title: const BrandMark(),
        leading: Builder(
          builder: (scaffoldContext) => IconButton(
            tooltip: 'Open account menu',
            onPressed: disabled
                ? null
                : () => Scaffold.of(scaffoldContext).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 480)
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Chip(
                avatar: Icon(
                  admin
                      ? Icons.admin_panel_settings_outlined
                      : Icons.bolt_rounded,
                  size: 18,
                  color: AppColors.deepAqua,
                ),
                label: Text(admin ? 'Admin workspace' : 'Training Zone'),
                backgroundColor: AppColors.aqua.withValues(alpha: 0.07),
                side: BorderSide.none,
              ),
            ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BrandMark(),
                          const SizedBox(height: 32),
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: AppColors.aqua.withValues(
                              alpha: 0.12,
                            ),
                            child: Icon(
                              admin
                                  ? Icons.shield_outlined
                                  : Icons.person_outline_rounded,
                              color: AppColors.deepAqua,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            admin ? 'Administrator' : 'Your account',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            authState.user?.email ?? '',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        admin
                            ? Icons.dashboard_outlined
                            : Icons.fitness_center_rounded,
                      ),
                      title: Text(admin ? 'Admin dashboard' : 'Training Zone'),
                      selected: admin || section == WorkspaceSection.training,
                      selectedColor: AppColors.deepAqua,
                      onTap: disabled
                          ? null
                          : () => navigate(WorkspaceSection.training),
                    ),
                    if (!admin)
                      ListTile(
                        leading: const Icon(Icons.person_outline_rounded),
                        title: const Text('Profile'),
                        selected: section == WorkspaceSection.profile,
                        selectedColor: AppColors.deepAqua,
                        onTap: disabled
                            ? null
                            : () => navigate(WorkspaceSection.profile),
                      ),
                    const Spacer(),
                    ListTile(
                      enabled: !disabled,
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text('Log out'),
                      onTap: () {
                        Navigator.of(context).pop();
                        authState.logout();
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'MAXREPS · MAKE EVERY REP COUNT',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(child: body),
      floatingActionButton: floatingActionButton,
    );
  }
}
