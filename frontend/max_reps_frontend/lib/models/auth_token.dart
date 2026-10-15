// Represents the auth response returned by the API

class AuthToken {
  // The JWT sent with requests that require authentication
  final String accessToken;
  // The authentication scheme. Backend return 'bearer'
  final String tokenType;

  // Constructor
  const AuthToken({required this.accessToken, required this.tokenType});

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    return AuthToken(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
    );
  }
}
