import 'package:flutter/material.dart';

import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/auth_service.dart';
import 'package:max_reps_frontend/services/exercise_service.dart';
import 'package:max_reps_frontend/services/lift_record_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';

import 'package:max_reps_frontend/pages/login_page.dart';
import 'package:max_reps_frontend/pages/home.dart';
import 'package:max_reps_frontend/pages/admin_page.dart';
import 'package:max_reps_frontend/services/admin_service.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';

// The root widget owns the shared objects used by the application.
class MainApp extends StatefulWidget {
  // Tests can provide an in-memory HTTP client. This root owns its lifetime.
  final ApiClient? apiClient;
  const MainApp({super.key, this.apiClient});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  // Initialized once in initState and retained across widget rebuilds.
  late final ApiClient _apiClient;
  late final AuthState _authState;
  late final ExerciseService _exerciseService;
  late final LiftRecordService _liftRecordService;
  late final AdminService _adminService;

  @override
  void initState() {
    super.initState();

    // Create the dependency chain:
    // ApiClient -> AuthService -> AuthState.
    _apiClient = widget.apiClient ?? ApiClient();
    _exerciseService = ExerciseService(_apiClient);
    _liftRecordService = LiftRecordService(_apiClient);
    _adminService = AdminService(_apiClient);

    final authService = AuthService(_apiClient);
    _authState = AuthState(authService);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MaxReps',
      theme: buildAppTheme(),
      home: ListenableBuilder(
        // Rebuild this section when AuthState calls notifyListeners().
        listenable: _authState,
        builder: (context, child) {
          if (!_authState.isAuthenticated) {
            return LoginPage(authState: _authState);
          }
          if (_authState.user!.isAdmin) {
            return AdminPage(
              authState: _authState,
              adminService: _adminService,
            );
          }
          return HomePage(
            authState: _authState,
            exerciseService: _exerciseService,
            liftRecordService: _liftRecordService,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    // This root created these objects, so it owns their cleanup.
    _authState.dispose();
    _apiClient.close();

    super.dispose();
  }
}
