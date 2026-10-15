import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/widgets/auth_layout.dart';

class RegistrationPage extends StatefulWidget {
  final AuthState authState;

  const RegistrationPage({super.key, required this.authState});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _errorMessage;
  bool _isSubmitting = false;
  bool _hidePassword = true;

  Future<void> _submit() async {
    if (_isSubmitting || widget.authState.isLoading) return;
    if (_formKey.currentState?.validate() != true) return;

    final email = _emailController.text.trim();

    // Preserve the password exactly as entered.
    final password = _passwordController.text;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.authState.register(email: email, password: password);

      if (!mounted) return;

      // If the user already went back, don't pop another page.
      if (ModalRoute.of(context)?.isCurrent != true) return;

      // Close registration and return the email to the login page.
      Navigator.of(context).pop(email);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        if (error is ApiException) {
          _errorMessage = error.statusCode == 422
              ? 'Check your email address and password.'
              : error.message;
        } else if (error is TimeoutException) {
          _errorMessage =
              'The request timed out. Your account may have been created; '
              'try signing in.';
        } else if (error is http.ClientException) {
          _errorMessage = 'Could not connect to the server.';
        } else {
          _errorMessage = 'Unable to create your account. Please try again.';
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

  @override
  Widget build(BuildContext context) {
    final isBusy = _isSubmitting || widget.authState.isLoading;

    return AuthLayout(
      title: 'Start your next chapter.',
      subtitle: 'Create an account. Find your numbers. Keep building.',
      canGoBack: !isBusy,
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
                autofillHints: const [AutofillHints.email],
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
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'Use 8–128 characters.',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _hidePassword
                        ? 'Show passwords'
                        : 'Hide passwords',
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
                    return 'Enter a password.';
                  }

                  // Count Unicode code points, matching the
                  // backend's password-length convention.
                  final length = value.runes.length;

                  if (length < 8 || length > 128) {
                    return 'Use 8–128 characters.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                enabled: !isBusy,
                obscureText: _hidePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Confirm your password.';
                  }

                  if (value != _passwordController.text) {
                    return 'Passwords do not match.';
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
                child: Text(isBusy ? 'Creating account...' : 'Create account'),
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
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
