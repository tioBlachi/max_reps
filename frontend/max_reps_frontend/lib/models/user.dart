// Represents the public User unformation returned by the API

class User {
  // The backend UUID serialized as a JSON string
  final String id;
  // The backend returns the user's normalized email address
  final String email;

  // Constructor
  // Both named arguments MUST be supplied when creating a User
  const User({
    required this.id,
    required this.email,
  });

  // Converts one decoded JSON object into a User
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
    );
  }
}