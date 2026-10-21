import 'package:max_reps_frontend/models/lift_record.dart';
import 'package:max_reps_frontend/models/exercise.dart';
import 'package:max_reps_frontend/services/api_client.dart';

class LiftRecordService {
  final ApiClient _apiClient;

  LiftRecordService(this._apiClient);

  Future<List<Exercise>> getLoggedExercises({
    required String accessToken,
  }) async {
    final data =
        await _apiClient.get('/lift_record/exercises', token: accessToken)
            as List<dynamic>;
    return data
        .map((item) => Exercise.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // Save a lift and receive the backend's calculated result.
  Future<LiftRecord> createLiftRecord({
    required String accessToken,
    required int exerciseId,
    required int reps,
    required double weight,
    String unit = 'lb',
    DateTime? attemptedAt,
  }) async {
    final data = await _apiClient.postJson(
      '/lift_record/',

      // ApiClient puts this in the Authorization header.
      token: accessToken,

      body: {
        'exercise_id': exerciseId,
        'reps': reps,
        'weight': weight,
        'unit': unit,

        // Include the timestamp only when one was supplied.
        // Otherwise, the backend uses its current UTC time.
        if (attemptedAt != null)
          'attempted_at': attemptedAt.toUtc().toIso8601String(),
      },
    );

    return LiftRecord.fromJson(data as Map<String, dynamic>);
  }

  // Fetch the authenticated user's saved lifts.
  Future<List<LiftRecord>> getLiftRecords({
    required String accessToken,
    int? exerciseId,
    String unit = 'lb',
    int offset = 0,
    int limit = 20,
  }) async {
    final data = await _apiClient.get(
      '/lift_record/',
      token: accessToken,
      queryParameters: {
        // Query parameter values must be strings.
        'unit': unit,
        'offset': offset.toString(),
        'limit': limit.toString(),

        // Omit this parameter when no exercise filter was supplied.
        if (exerciseId != null) 'exercise_id': exerciseId.toString(),
      },
    );

    final items = data as List<dynamic>;

    return items.map<LiftRecord>((item) {
      return LiftRecord.fromJson(item as Map<String, dynamic>);
    }).toList();
  }
}
