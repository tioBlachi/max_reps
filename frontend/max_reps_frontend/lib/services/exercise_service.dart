import 'package:max_reps_frontend/models/exercise.dart';
import 'package:max_reps_frontend/services/api_client.dart';

// Fetches exercise catalog data from the backend.
class ExerciseService {
  final ApiClient _apiClient;

  // Receive the same shared client used by the other services.
  ExerciseService(this._apiClient);

  // Return a list of Exercise objects once the request completes.
  Future<List<Exercise>> getExercises() async {
    // This endpoint is public, so no access token is required.
    final data = await _apiClient.get('/exercises/');

    // The response contains a JSON array, decoded as a Dart List.
    final items = data as List<dynamic>;

    // Convert each decoded JSON object into an Exercise.
    return items.map<Exercise>((item) {
      return Exercise.fromJson(item as Map<String, dynamic>);
    }).toList();
  }
}

