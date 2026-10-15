import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/widgets/brand_mark.dart';

class AppScaffold extends StatelessWidget {
  final AuthState authState;
  final Widget body;
  final bool busy;

  const AppScaffold({
    super.key,
    required this.authState,
    required this.body,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final admin = authState.user?.isAdmin == true;
    final disabled = busy || authState.isLoading;
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
          if (MediaQuery.sizeOf(context).width >= 420)
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
                label: Text(admin ? 'Admin workspace' : 'Training studio'),
                backgroundColor: AppColors.aqua.withValues(alpha: 0.07),
                side: BorderSide.none,
              ),
            ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
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
                      backgroundColor: AppColors.aqua.withValues(alpha: 0.12),
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
                title: Text(admin ? 'Admin dashboard' : 'Training studio'),
                selected: true,
                selectedColor: AppColors.deepAqua,
                onTap: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              if (!admin)
                ListTile(
                  enabled: !disabled,
                  leading: Icon(
                    Icons.person_off_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Deactivate account',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(context).pop();
                    showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _DeactivateDialog(authState: authState),
                    ).then((deactivated) {
                      if (deactivated == true && messenger.mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Your account has been deactivated.'),
                          ),
                        );
                      }
                    });
                  },
                ),
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
      ),
      body: SafeArea(child: body),
    );
  }
}

class _DeactivateDialog extends StatefulWidget {
  final AuthState authState;
  const _DeactivateDialog({required this.authState});

  @override
  State<_DeactivateDialog> createState() => _DeactivateDialogState();
}

class _DeactivateDialogState extends State<_DeactivateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _hidePassword = true;
  String? _error;

  Future<void> _submit() async {
    if (_submitting || _formKey.currentState?.validate() != true) return;
    final password =
        _password.text; // Never trim a password or store it in app state.
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authState.deactivate(currentPassword: password);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        Navigator.of(context).pop();
        widget.authState.logout();
        return;
      }
      setState(() {
        _error = switch (error) {
          ApiException(statusCode: 403) =>
            'Your password is incorrect. Please try again.',
          ApiException(statusCode: 429) =>
            'Too many attempts. Please wait before trying again.',
          ApiException() => error.message,
          TimeoutException() =>
            'The request timed out. Try signing in to check your account status.',
          http.ClientException() =>
            'Could not connect to the server. Please try again.',
          _ => 'Could not deactivate your account. Please try again.',
        };
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: AlertDialog(
      icon: Icon(
        Icons.person_off_outlined,
        color: Theme.of(context).colorScheme.error,
        size: 32,
      ),
      title: const Text('Deactivate your account?'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'You will be signed out. You can reactivate by signing in again. Accounts inactive for 90 days or more may be permanently deleted along with their lift records.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _password,
                  enabled: !_submitting,
                  autofocus: true,
                  obscureText: _hidePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    suffixIcon: IconButton(
                      tooltip: _hidePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: _submitting
                          ? null
                          : () => setState(() {
                              _hidePassword = !_hidePassword;
                            }),
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your current password.'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
          ),
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Deactivating...' : 'Deactivate account'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }
}
