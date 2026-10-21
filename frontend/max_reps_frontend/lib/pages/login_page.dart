import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/widgets/auth_layout.dart';

class LoginPage extends StatefulWidget {
  // Receive the shared state created in app.dart.
  final AuthState authState;
  final VoidCallback onRegister;
  final String? registeredEmail;

  const LoginPage({
    super.key,
    required this.authState,
    required this.onRegister,
    this.registeredEmail,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Identifies the form so we can run all its validators.
  final _formKey = GlobalKey<FormState>();

  // Controllers let us read the text entered into the fields.
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;

  // Covers the entire interaction, including the reactivation dialog.
  bool _isSubmitting = false;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    final email = widget.registeredEmail;
    if (email == null) return;
    // Registration passes this in memory, keeping email addresses out of URLs.
    _emailController.text = email;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created. Sign in to continue.'),
          ),
        );
      }
    });
  }

  Future<void> _submit() async {
    // Prevent duplicate submissions.
    if (_isSubmitting || widget.authState.isLoading) return;

    if (_formKey.currentState?.validate() != true) return;

    // Capture the credentials before awaiting anything.
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Dismiss the keyboard. Preserve the password exactly as entered.
    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await _loginOrReactivate(email, password);

      // The router reacts to AuthState and opens the requested destination.
    } catch (error) {
      // The page might have been removed while awaiting a request.
      if (!mounted) return;

      setState(() {
        if (error is ApiException) {
          _errorMessage = error.message;
        } else if (error is TimeoutException) {
          _errorMessage = 'The request timed out. Please try again.';
        } else if (error is http.ClientException) {
          _errorMessage = 'Could not connect to the server.';
        } else {
          _errorMessage = 'Unable to sign in. Please try again.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _openRegistration() {
    if (_isSubmitting || widget.authState.isLoading) return;
    widget.onRegister();
  }

  Future<void> _loginOrReactivate(String email, String password) async {
    try {
      await widget.authState.login(email: email, password: password);
    } on ApiException catch (error) {
      // Other 403 responses must not trigger account reactivation.
      final isInactiveAccount =
          error.statusCode == 403 && error.message == 'Inactive user';

      if (!isInactiveAccount) rethrow;
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Reactivate account?'),
            content: const Text(
              'Your account is inactive. Would you like to reactivate it?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Yes, reactivate'),
              ),
            ],
          );
        },
      );

      // Dismissing the dialog can return null. Only true is approval.
      if (!mounted || confirmed != true) return;

      await widget.authState.reactivate(email: email, password: password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isSubmitting || widget.authState.isLoading;

    return AuthLayout(
      title: 'Welcome back.',
      subtitle: 'Sign in to pick up where you left off.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                enabled: !isBusy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';

                  if (email.isEmpty) {
                    return 'Enter your email address.';
                  }

                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                    return 'Enter a valid email address.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                enabled: !isBusy,
                obscureText: _hidePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _hidePassword ? 'Show password' : 'Hide password',
                    onPressed: isBusy
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
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter your password.';
                  }

                  return null;
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: isBusy ? null : _submit,
                child: Text(isBusy ? 'Signing in...' : 'Sign in'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: isBusy ? null : _openRegistration,
                child: const Text('Create an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
