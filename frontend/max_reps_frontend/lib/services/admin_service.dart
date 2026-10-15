import 'package:max_reps_frontend/models/admin.dart';
import 'package:max_reps_frontend/services/api_client.dart';

class AdminService {
  final ApiClient _client;
  AdminService(this._client);

  Future<AdminStats> getStats(String token) async => AdminStats.fromJson(
    await _client.get('/admin/stats', token: token) as Map<String, dynamic>,
  );

  Future<CleanupPreview> previewCleanup(String token) async =>
      CleanupPreview.fromJson(
        await _client.get('/admin/inactive-users/cleanup', token: token)
            as Map<String, dynamic>,
      );

  Future<int> cleanup(String token, CleanupPreview preview) async {
    // Reuse the preview's cutoff so time passing during confirmation cannot
    // enlarge the date range the administrator agreed to clean up.
    final data =
        await _client.delete(
              '/admin/inactive-users/cleanup',
              token: token,
              body: {'cutoff_at': preview.cutoffAt.toUtc().toIso8601String()},
            )
            as Map<String, dynamic>;
    return data['deleted_users'] as int;
  }
}
