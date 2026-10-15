import 'package:flutter/material.dart';

import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/auth_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';

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

  @override
  void initState() {
    super.initState();

    // Create the dependency chain:
    // ApiClient -> AuthService -> AuthState.
    _apiClient = ApiClient();

    final authService = AuthService(_apiClient);
    _authState = AuthState(authService);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MaxReps',
      home: ListenableBuilder(
        // Rebuild this section when AuthState calls notifyListeners().
        listenable: _authState,
        builder: (context, child) {
          // These temporary contents keep the app runnable while
          // we build the login and home pages.
          return Scaffold(
            appBar: AppBar(
              title: const Text('MaxReps'),
              actions: [
                if (_authState.isAuthenticated)
                  TextButton(
                    // Disable logout during an authentication operation.
                    onPressed:
                        _authState.isLoading ? null : _authState.logout,
                    child: const Text('Log out'),
                  ),
              ],
            ),
            body: Center(
              child: Text(
                _authState.isAuthenticated
                    ? 'Signed in as ${_authState.user?.email}'
                    : 'Login page goes here.',
              ),
            ),
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