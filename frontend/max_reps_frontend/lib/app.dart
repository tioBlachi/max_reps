import 'package:flutter/material.dart';

import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/auth_service.dart';
import 'package:max_reps_frontend/services/exercise_service.dart';
import 'package:max_reps_frontend/services/lift_record_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';

import 'package:max_reps_frontend/pages/login_page.dart';
import 'package:max_reps_frontend/pages/home.dart';

// The root widget owns the shared objects used by the application.
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  // Initialized once in initState and retained across widget rebuilds.
  late final ApiClient _apiClient;
  late final AuthState _authState;
  late final ExerciseService _exerciseService;
  late final LiftRecordService _liftRecordService;

  @override
  void initState() {
    super.initState();

    // Create the dependency chain:
    // ApiClient -> AuthService -> AuthState.
    _apiClient = ApiClient();
    _exerciseService = ExerciseService(_apiClient);
    _liftRecordService = LiftRecordService(_apiClient);

    final authService = AuthService(_apiClient);
    _authState = AuthState(authService);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MaxReps',
      home: ListenableBuilder(
        // Rebuild this section when AuthState calls notifyListeners().
        listenable: _authState,
        builder: (context, child) {
          // These temporary contents keep the app runnable while
          // we build the login and home pages.
          if (!_authState.isAuthenticated) {
            return LoginPage(authState: _authState);
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
