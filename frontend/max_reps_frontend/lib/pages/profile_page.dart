import 'dart:async';

import 'package:flutter/material.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';

enum _AccountAction { email, password, deactivate }

class ProfilePage extends StatelessWidget {
  final AuthState authState;
  const ProfilePage({super.key, required this.authState});

  Future<void> _open(BuildContext context, _AccountAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => _AccountDialog(authState: authState, action: action),
    );
    if (result == true && messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            _AccountAction.email => 'Your email address has been updated.',
            _AccountAction.password =>
              'Password updated. Sign in with your new password.',
            _AccountAction.deactivate => 'Your account has been deactivated.',
          }),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              'YOUR ACCOUNT',
              style: TextStyle(
                color: AppColors.deepAqua,
                letterSpacing: 1.6,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text('Profile', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 10),
            const Text('Manage your sign-in details and account.'),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.aqua,
                      size: 40,
                    ),
                    const SizedBox(height: 18),
                    SelectableText(
                      authState.user?.email ?? '',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    _option(
                      context,
                      Icons.mail_outline_rounded,
                      'Update email',
                      'Confirm your current password to change your email.',
                      _AccountAction.email,
                    ),
                    const Divider(),
                    _option(
                      context,
                      Icons.lock_outline_rounded,
                      'Update password',
                      'Choose a new password. You’ll sign in again afterward.',
                      _AccountAction.password,
                    ),
                  ],
                ),
              ),
            ),
            if (authState.user?.isAdmin != true) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deactivate account',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'You can reactivate by signing in again. Accounts inactive for 90 days or more may be permanently deleted along with their lift records.',
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: authState.isLoading
                            ? null
                            : () => _open(context, _AccountAction.deactivate),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        icon: const Icon(Icons.person_off_outlined),
                        label: const Text('Deactivate account'),
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
  );

  Widget _option(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    _AccountAction action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    leading: Icon(icon, color: AppColors.deepAqua),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: authState.isLoading ? null : () => _open(context, action),
  );
}

class _AccountDialog extends StatefulWidget {
  final AuthState authState;
  final _AccountAction action;
  const _AccountDialog({required this.authState, required this.action});
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newValue = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  String get _title => switch (widget.action) {
    _AccountAction.email => 'Update email',
    _AccountAction.password => 'Update password',
    _AccountAction.deactivate => 'Deactivate your account?',
  };

  Future<void> _submit() async {
    if (_busy || _form.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (widget.action) {
        case _AccountAction.email:
          await widget.authState.updateEmail(
            email: _newValue.text.trim(),
            currentPassword: _current.text,
          );
        case _AccountAction.password:
          await widget.authState.updatePassword(
            currentPassword: _current.text,
            newPassword: _newValue.text,
          );
        case _AccountAction.deactivate:
          await widget.authState.deactivate(currentPassword: _current.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        await widget.authState.logout();
        return;
      }
      setState(() {
        _error = switch (error) {
          ApiException(statusCode: 403) =>
            'Your current password is incorrect.',
          ApiException(statusCode: 409) =>
            'That email address is already registered.',
          ApiException(statusCode: 429) =>
            'Too many attempts. Please wait before trying again.',
          ApiException(statusCode: 422) => 'Check the details you entered.',
          ApiException() => error.message,
          TimeoutException() =>
            'The request timed out and may have completed. Check your account before retrying.',
          _ => 'Could not update your account. Please try again.',
        };
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _password(
    TextEditingController controller,
    String label, {
    bool newPassword = false,
    bool confirmation = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    obscureText: _obscure,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
        onPressed: _busy
            ? null
            : () => setState(() {
                _obscure = !_obscure;
              }),
        icon: Icon(
          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    onFieldSubmitted: (_) => _submit(),
    validator: (value) {
      if (value == null || value.isEmpty) {
        return 'Enter ${label.toLowerCase()}.';
      }
      if (newPassword && (value.runes.length < 8 || value.runes.length > 128)) {
        return 'Use 8–128 characters.';
      }
      if (newPassword && value == _current.text) {
        return 'New password must be different from your current password.';
      }
      if (confirmation && value != _newValue.text) {
        return 'Passwords do not match.';
      }
      return null;
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(_title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.action == _AccountAction.deactivate) ...[
                const Text(
                  'Confirm your password to deactivate your account and sign out. You can reactivate by signing in again.',
                ),
                const SizedBox(height: 20),
              ],
              if (widget.action == _AccountAction.email) ...[
                TextFormField(
                  controller: _newValue,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'New email'),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (!RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(email)) {
                      return 'Enter a valid email address.';
                    }
                    if (email.toLowerCase() ==
                        widget.authState.user?.email.trim().toLowerCase()) {
                      return 'New email must be different from your current email.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
              ],
              _password(_current, 'Current password'),
              if (widget.action == _AccountAction.password) ...[
                const SizedBox(height: 20),
                _password(_newValue, 'New password', newPassword: true),
                const SizedBox(height: 20),
                _password(_confirm, 'Confirm new password', confirmation: true),
                const SizedBox(height: 16),
                const Text(
                  'Updating your password signs you out on all devices.',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: widget.action == _AccountAction.deactivate
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(
            _busy
                ? 'Saving...'
                : widget.action == _AccountAction.deactivate
                ? 'Confirm deactivation'
                : 'Save changes',
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _current.dispose();
    _newValue.dispose();
    _confirm.dispose();
    super.dispose();
  }
}
