// Represents a saved lift returned by the API.
class LiftRecord {
  // Lift records and users have UUIDs represented as strings.
  final String id;
  final String userId;

  // Exercises have integer IDs.
  final int exerciseId;
  final int reps;

  // Store the timestamp as a DateTime, normalized to UTC.
  final DateTime attemptedAt;

  // These values use the unit returned with this record.
  final double weight;
  final String unit;
  final double oneRepMaxEst;

  const LiftRecord({
    required this.id,
    required this.userId,
    required this.exerciseId,
    required this.reps,
    required this.attemptedAt,
    required this.weight,
    required this.unit,
    required this.oneRepMaxEst,
  });

  factory LiftRecord.fromJson(Map<String, dynamic> json) {
    final timestamp = json['attempted_at'] as String;

    // Recognize a timezone suffix such as Z, +00:00, or -04:00.
    final hasTimezone = RegExp(
      r'(Z|[+-]\d{2}:\d{2})$',
      caseSensitive: false,
    ).hasMatch(timestamp);

    // The app interprets timestamps without a timezone as UTC.
    // Appending Z makes that explicit before Dart parses the value.
    final normalizedTimestamp =
        hasTimezone ? timestamp : '${timestamp}Z';

    return LiftRecord(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      exerciseId: json['exercise_id'] as int,
      reps: json['reps'] as int,
      attemptedAt: DateTime.parse(normalizedTimestamp).toUtc(),

      // JSON numbers can decode as int or double.
      // Accept either numeric type, then convert to double.
      weight: (json['weight'] as num).toDouble(),
      unit: json['unit'] as String,
      oneRepMaxEst: (json['one_rep_max_est'] as num).toDouble(),
    );
  }
}