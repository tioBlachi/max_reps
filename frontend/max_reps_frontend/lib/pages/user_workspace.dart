import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/widgets/app_scaffold.dart';

class UserWorkspace extends StatelessWidget {
  final AuthState authState;
  final StatefulNavigationShell navigationShell;
  final VoidCallback onAddLift;
  const UserWorkspace({
    super.key,
    required this.authState,
    required this.navigationShell,
    required this.onAddLift,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: authState,
    builder: (context, _) => AppScaffold(
      authState: authState,
      section: navigationShell.currentIndex == 0
          ? WorkspaceSection.training
          : WorkspaceSection.profile,
      onNavigate: (section) => navigationShell.goBranch(
        section == WorkspaceSection.training ? 0 : 1,
      ),
      floatingActionButton: navigationShell.currentIndex != 0
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: TextButton(
                    onPressed: onAddLift,
                    child: const Text(
                      'Add New Lift',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  tooltip: 'Add a new lift',
                  onPressed: onAddLift,
                  elevation: 0,
                  shape: const CircleBorder(),
                  backgroundColor: AppColors.orange,
                  foregroundColor: AppColors.ink,
                  child: const Icon(Icons.add_rounded),
                ),
              ],
            ),
      // Each URL has its own navigator. The router keeps both branches mounted
      // after their first visit, preserving exercise selection and training units.
      body: navigationShell,
    ),
  );
}
