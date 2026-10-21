import 'package:max_reps_frontend/models/auth_token.dart';
import 'package:max_reps_frontend/models/user.dart';
import 'package:max_reps_frontend/services/api_client.dart';

// Provides the application's account and authentication requests
class AuthService {
  // Receive a shared API client
  final ApiClient _apiClient;

  AuthService(this._apiClient);

  // Registration
  Future<User> register({
    required String email,
    required String password,
  }) async {
    final data = await _apiClient.postJson(
      '/users',
      body: {'email': email, 'password': password},
    );

    // The registration endpoint returns one JSON object.
    return User.fromJson(data as Map<String, dynamic>);
  }

  // Login - Returns a Token
  Future<AuthToken> login({
    required String email,
    required String password,
  }) async {
    final data = await _apiClient.postForm(
      '/users/token',
      body: {'username': email, 'password': password},
    );

    return AuthToken.fromJson(data as Map<String, dynamic>);
  }

  // Fetching the current user
  Future<User> getCurrentUser({required String accessToken}) async {
    final data = await _apiClient.get('/users/me', token: accessToken);

    return User.fromJson(data as Map<String, dynamic>);
  }

  // Account changes require the user's current password.
  Future<User> updateEmail({
    required String accessToken,
    required String email,
    required String currentPassword,
  }) async {
    final data = await _apiClient.patchJson(
      '/users/me/email',
      token: accessToken,
      body: {'email': email, 'current_password': currentPassword},
    );
    return User.fromJson(data as Map<String, dynamic>);
  }

  Future<void> updatePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _apiClient.patchJson(
      '/users/me/password',
      token: accessToken,
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  Future<void> deactivate({
    required String accessToken,
    required String currentPassword,
  }) async {
    await _apiClient.delete(
      '/users/me/deactivate',
      token: accessToken,
      body: {'current_password': currentPassword},
    );
  }

  // Call after user confirms they want to reactivate.
  Future<AuthToken> reactivate({
    required String email,
    required String password,
  }) async {
    final data = await _apiClient.postForm(
      '/users/reactivate',
      body: {'username': email, 'password': password},
    );

    return AuthToken.fromJson(data as Map<String, dynamic>);
  }
}
