import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/pages/registration_page.dart';

class LoginPage extends StatefulWidget {
  // Receive the shared state created in app.dart.
  final AuthState authState;

  const LoginPage({super.key, required this.authState});

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

      // No navigation here: app.dart listens to AuthState and
      // replaces this page after authentication succeeds.
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

  Future<void> _openRegistration() async {
    if (_isSubmitting || widget.authState.isLoading) return;

    // Push registration onto the navigation stack and wait for its result.
    final registeredEmail = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) {
          return RegistrationPage(authState: widget.authState);
        },
      ),
    );

    // Going back without registering returns null.
    if (!mounted || registeredEmail == null) return;

    // Prefill the newly registered email and clear the old password.
    _emailController.text = registeredEmail;
    _passwordController.clear();

    setState(() {
      _errorMessage = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account created. Sign in to continue.')),
    );
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

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
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
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final email = value?.trim() ?? '';

                        if (email.isEmpty) {
                          return 'Enter your email address.';
                        }

                        if (!RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(email)) {
                          return 'Enter a valid email address.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !isBusy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Password'),
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
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
