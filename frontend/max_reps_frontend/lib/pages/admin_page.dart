import 'dart:async';

import 'package:flutter/material.dart';
import 'package:max_reps_frontend/models/admin.dart';
import 'package:max_reps_frontend/services/admin_service.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/utils/date_format.dart';
import 'package:max_reps_frontend/widgets/app_scaffold.dart';

class AdminPage extends StatefulWidget {
  final AuthState authState;
  final AdminService adminService;
  const AdminPage({
    super.key,
    required this.authState,
    required this.adminService,
  });

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  AdminStats? _stats;
  CleanupPreview? _preview;
  bool _loading = true;
  bool _cleaning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The server enforces the role too; this guard prevents fetching admin data
    // if the page is ever constructed directly for an ordinary user.
    if (widget.authState.user?.isAdmin == true) unawaited(_load());
  }

  bool _handleSessionError(Object error) {
    if (error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in again to access the admin workspace.'),
        ),
      );
      widget.authState.logout();
      return true;
    }
    return false;
  }

  Future<void> _load() async {
    final token = widget.authState.accessToken;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });
    try {
      final data = await Future.wait<Object>([
        widget.adminService.getStats(token),
        widget.adminService.previewCleanup(token),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = data[0] as AdminStats;
        _preview = data[1] as CleanupPreview;
      });
    } catch (error) {
      if (!mounted || _handleSessionError(error)) return;
      setState(() {
        _error = 'Could not load the dashboard. Please refresh and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmCleanup() async {
    if (_cleaning || _loading) return;
    final token = widget.authState.accessToken;
    if (token == null) return;
    setState(() {
      _cleaning = true;
      _error = null;
    });
    try {
      // Refresh eligibility just before asking for confirmation. The DELETE
      // then uses this exact cutoff, and independently rechecks current status.
      final preview = await widget.adminService.previewCleanup(token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
      });
      if (preview.eligibleUsers == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('There are no eligible inactive accounts to delete.'),
          ),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          icon: Icon(
            Icons.delete_forever_outlined,
            color: Theme.of(context).colorScheme.error,
            size: 32,
          ),
          title: Text('Delete ${preview.eligibleUsers} inactive accounts?'),
          content: SizedBox(
            width: 420,
            child: Text(
              'This permanently deletes eligible accounts and all of their lift records. '
              'This cannot be undone.\n\n'
              'Only regular accounts still inactive and last deactivated on or before '
              '${formatUsUtc(preview.cutoffAt)} qualify. Admins and accounts without a deactivation date are excluded.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Permanently delete'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final deleted = await widget.adminService.cleanup(token, preview);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted $deleted inactive ${deleted == 1 ? 'account' : 'accounts'} and their lift records.',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted || _handleSessionError(error)) return;
      setState(() {
        _preview = null;
        _error = error is TimeoutException
            ? 'The cleanup request timed out and may have completed. Refresh the dashboard to check before retrying.'
            : error is ApiException && error.statusCode == 429
            ? 'Too many cleanup attempts. Please wait before trying again.'
            : 'Could not complete cleanup. Refresh the dashboard before trying again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cleaning = false;
        });
      }
    }
  }

  Widget _stat(String label, int value, IconData icon, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 20),
          Text('$value', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.authState.user?.isAdmin != true) {
      return const Scaffold(
        body: Center(
          child: Text('This page is available to administrators only.'),
        ),
      );
    }
    final stats = _stats;
    return AppScaffold(
      authState: widget.authState,
      busy: _cleaning,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'ADMIN WORKSPACE',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.7,
                    color: AppColors.deepAqua,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your community, at a glance.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Keep an eye on account activity and keep your community up to date.',
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _loading || _cleaning ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      _loading ? 'Refreshing...' : 'Refresh dashboard',
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: LinearProgressIndicator(),
                  ),
                if (stats != null) ...[
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 700 ? 3 : 1;
                      final width =
                          (constraints.maxWidth - (columns - 1) * 16) / columns;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: width,
                            child: _stat(
                              'Total users',
                              stats.totalUsers,
                              Icons.people_outline_rounded,
                              AppColors.deepAqua,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _stat(
                              'Active users',
                              stats.activeUsers,
                              Icons.check_circle_outline_rounded,
                              AppColors.aqua,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _stat(
                              'Inactive users',
                              stats.inactiveUsers,
                              Icons.pause_circle_outline_rounded,
                              const Color(0xFFB45A0D),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Counts include your admin account and exclude permanently deleted accounts.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.orange.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.auto_delete_outlined,
                                  color: Color(0xFFB45A0D),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Inactive account cleanup',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _preview == null
                                ? 'Eligibility unavailable'
                                : '${_preview!.eligibleUsers} eligible accounts',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Remove regular accounts that have been inactive for at least 90 days. Their lift records are permanently deleted too. Accounts without a deactivation date are kept.',
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed:
                                  _loading ||
                                      _cleaning ||
                                      _preview == null ||
                                      _preview!.eligibleUsers == 0
                                  ? null
                                  : _confirmCleanup,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: Text(
                                _cleaning
                                    ? 'Working...'
                                    : 'Review inactive accounts',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'You will review the eligible count and confirm before anything is deleted.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
