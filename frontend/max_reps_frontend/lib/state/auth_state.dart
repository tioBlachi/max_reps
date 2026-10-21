import 'package:flutter/foundation.dart';
import 'package:max_reps_frontend/models/auth_token.dart';
import 'package:max_reps_frontend/models/user.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/auth_service.dart';
import 'package:max_reps_frontend/services/token_storage.dart';

class AuthState extends ChangeNotifier {
  final AuthService _authService;
  final TokenStorage _storage;

  AuthState(this._authService, {TokenStorage? storage})
    : _storage = storage ?? SecureTokenStorage();

  User? _user;
  AuthToken? _token;
  bool _isLoading = false;
  bool _isRestoring = true;
  bool _disposed = false;
  String? _storageMessage;

  User? get user => _user;
  String? get accessToken => _token?.accessToken;
  bool get isLoading => _isLoading;
  bool get isRestoring => _isRestoring;
  bool get isAuthenticated => _token != null && _user != null;
  String? get storageMessage => _storageMessage;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restoreSession() async {
    if (_isLoading) return;
    _isRestoring = true;
    _notify();
    try {
      final token = await _storage.read();
      if (_disposed || token == null) return;
      // The backend checks expiration, account activity, and auth_version.
      // A decoded JWT alone cannot establish that this session is still valid.
      final user = await _authService.getCurrentUser(accessToken: token);
      if (_disposed) return;
      _user = user;
      _token = AuthToken(accessToken: token, tokenType: 'bearer');
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _clearSession();
      }
    } catch (_) {
      // A network/storage outage is not proof that a saved token is invalid.
      // Keep it for the next visit and show the normal login page this time.
    } finally {
      _isRestoring = false;
      _notify();
    }
  }

  Future<void> register({required String email, required String password}) =>
      _run(() async {
        await _authService.register(email: email, password: password);
      });

  Future<void> login({required String email, required String password}) => _run(
    () async {
      final token = await _authService.login(email: email, password: password);
      await _setSession(token);
    },
  );

  Future<void> reactivate({required String email, required String password}) =>
      _run(() async {
        final token = await _authService.reactivate(
          email: email,
          password: password,
        );
        await _setSession(token);
      });

  Future<void> updateEmail({
    required String email,
    required String currentPassword,
  }) => _run(() async {
    final user = await _authService.updateEmail(
      accessToken: _requireToken(),
      email: email,
      currentPassword: currentPassword,
    );
    if (!_disposed) _user = user;
  });

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) => _run(() async {
    await _authService.updatePassword(
      accessToken: _requireToken(),
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    // Password changes increment auth_version, revoking every old token.
    await _clearSession();
  });

  Future<void> deactivate({required String currentPassword}) => _run(() async {
    if (_user?.isAdmin == true) {
      throw StateError('Admin accounts cannot be deactivated.');
    }
    await _authService.deactivate(
      accessToken: _requireToken(),
      currentPassword: currentPassword,
    );
    await _clearSession();
  });

  String _requireToken() {
    final token = accessToken;
    if (token == null) throw StateError('Please sign in again.');
    return token;
  }

  Future<void> _setSession(AuthToken token) async {
    final user = await _authService.getCurrentUser(
      accessToken: token.accessToken,
    );
    if (_disposed) return;
    _storageMessage = null;
    try {
      await _storage.write(token.accessToken);
    } catch (_) {
      _storageMessage =
          'Signed in, but this browser could not remember your session.';
    }
    if (_disposed) return;
    _user = user;
    _token = token;
  }

  Future<void> _clearSession() async {
    _user = null;
    _token = null;
    _storageMessage = null;
    try {
      await _storage.delete();
    } catch (_) {
      _storageMessage =
          'Your saved sign-in could not be removed. Clear this site\'s browser data if needed.';
    }
  }

  Future<void> logout() async {
    if (_isLoading || _isRestoring) return;
    _isLoading = true;
    // Notify immediately after clearing the user so authenticated pages close
    // even if browser storage is slow. No password is ever persisted.
    final clearing = _clearSession();
    _notify();
    await clearing;
    _isLoading = false;
    _notify();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_isLoading || _isRestoring) {
      throw StateError('An authentication request is already in progress.');
    }
    _isLoading = true;
    _notify();
    try {
      await action();
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  @override
  void dispose() {
    // Disposing a widget/app is not logout. Preserve the saved valid token.
    _disposed = true;
    super.dispose();
  }
}
