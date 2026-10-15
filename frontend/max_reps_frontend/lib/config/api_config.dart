// Shared configuration for communication with the backend

class ApiConfig {
  // Settings accessed through ApiConfig, not by creating ApiConfig objects
  ApiConfig._(); // Private named constructor

  // Set the backend address to the default of localhost on port 8000
  // Can be filled in from environment when in production
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // Set a limit for how long these requests should take
  static const Duration requestTimeout = Duration(seconds: 15);
}


// flutter run --dart-define=API_BASE_URL=http://localhost:8000
// In terminal to define the baseURL as something else