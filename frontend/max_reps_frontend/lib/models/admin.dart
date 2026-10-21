class AdminStats {
  final int totalUsers;
  final int activeUsers;
  final int inactiveUsers;

  const AdminStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.inactiveUsers,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
    totalUsers: json['total_users'] as int,
    activeUsers: json['active_users'] as int,
    inactiveUsers: json['inactive_users'] as int,
  );
}

class CleanupPreview {
  final int eligibleUsers;
  final DateTime cutoffAt;

  const CleanupPreview({required this.eligibleUsers, required this.cutoffAt});

  factory CleanupPreview.fromJson(Map<String, dynamic> json) => CleanupPreview(
    eligibleUsers: json['eligible_users'] as int,
    cutoffAt: DateTime.parse(json['cutoff_at'] as String).toUtc(),
  );
}
