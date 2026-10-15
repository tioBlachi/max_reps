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
  Future<User> getCurrentUser({
    required String accessToken,
  }) async {
    final data = await _apiClient.get(
      '/users/me',
      token: accessToken,
    );

    return User.fromJson(data as Map<String, dynamic>);
  }

  // Call after user confirms they want to reactivate
  Future<AuthToken> reactivate({
    required String email,
    required String password,
  }) async {
    final data = await _apiClient.postForm('/users/reactivate', body: {'username': email, 'password': password});

    return AuthToken.fromJson(data as Map<String, dynamic>);
  }
}
