import 'package:flutter/foundation.dart';

import 'package:max_reps_frontend/models/auth_token.dart';
import 'package:max_reps_frontend/models/user.dart';
import 'package:max_reps_frontend/services/auth_service.dart';

class AuthState extends ChangeNotifier {
  // Pretty much used as an Event updater and broadcaster
  final AuthService _authService;

  AuthState(this._authService);

  // No account is logged in when the app first starts.
  User? _user;
  AuthToken? _token;
  bool _isLoading = false;

  // Getters let widgets read state without assigning these fields.
  User? get user => _user;
  String? get accessToken => _token?.accessToken;
  bool get isLoading => _isLoading;

  // A completed login requires both a token and a fetched profile.
  bool get isAuthenticated => _token != null && _user != null;

  // Register an account. Registration does not log the user in.
  Future<void> register({required String email, required String password}) {
    return _run(() async {
      await _authService.register(email: email, password: password);
    });
  }

  Future<void> login({required String email, required String password}) {
    return _run(() async {
      final token = await _authService.login(email: email, password: password);

      await _setSession(token);
    });
  }

  // The page calls this after the user confirms reactivation.
  Future<void> reactivate({required String email, required String password}) {
    return _run(() async {
      final token = await _authService.reactivate(
        email: email,
        password: password,
      );

      await _setSession(token);
    });
  }

  Future<void> deactivate({required String currentPassword}) {
    final token = accessToken;
    if (token == null || _user?.isAdmin == true) {
      throw StateError('This account cannot be deactivated.');
    }
    return _run(() async {
      await _authService.deactivate(
        accessToken: token,
        currentPassword: currentPassword,
      );
      // Clear the session only after the server confirms deactivation.
      _user = null;
      _token = null;
    });
  }

  // Login and reactivation both finish by fetching the user's profile.
  Future<void> _setSession(AuthToken token) async {
    final user = await _authService.getCurrentUser(
      accessToken: token.accessToken,
    );

    // Publish the session only after both requests have succeeded.
    _token = token;
    _user = user;
  }

  // Share loading behavior across authentication operations.
  Future<void> _run(Future<void> Function() action) async {
    if (_isLoading) {
      throw StateError('An authentication request is already in progress.');
    }

    _isLoading = true;
    notifyListeners();

    try {
      await action();
    } finally {
      // Runs whether the action succeeds or throws an exception.
      _isLoading = false;
      notifyListeners();
    }
  }

  void logout() {
    if (_isLoading) {
      throw StateError('Wait for the authentication request to finish.');
    }

    // Clear the session held by this running app.
    _user = null;
    _token = null;
    notifyListeners();
  }
}
