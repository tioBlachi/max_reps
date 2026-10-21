import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:max_reps_frontend/models/lift_record.dart';
import 'package:max_reps_frontend/pages/add_lift_page.dart';
import 'package:max_reps_frontend/pages/admin_page.dart';
import 'package:max_reps_frontend/pages/login_page.dart';
import 'package:max_reps_frontend/pages/profile_page.dart';
import 'package:max_reps_frontend/pages/registration_page.dart';
import 'package:max_reps_frontend/pages/training_zone_page.dart';
import 'package:max_reps_frontend/pages/user_workspace.dart';
import 'package:max_reps_frontend/services/admin_service.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/auth_service.dart';
import 'package:max_reps_frontend/services/exercise_service.dart';
import 'package:max_reps_frontend/services/lift_record_service.dart';
import 'package:max_reps_frontend/services/token_storage.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';

class MainApp extends StatefulWidget {
  // Tests can replace network and storage without changing application behavior.
  // This root owns the API client's lifetime.
  final ApiClient? apiClient;
  final TokenStorage? tokenStorage;
  const MainApp({super.key, this.apiClient, this.tokenStorage});
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _rootNavigator = GlobalKey<NavigatorState>();
  final _training = GlobalKey<TrainingZonePageState>();
  late final ApiClient _apiClient;
  late final AuthState _authState;
  late final ExerciseService _exercises;
  late final LiftRecordService _lifts;
  late final AdminService _admin;
  late final GoRouter _router;
  bool _wasAuthenticated = false;
  String? _lastStorageMessage;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient();
    _authState = AuthState(
      AuthService(_apiClient),
      storage: widget.tokenStorage,
    );
    _exercises = ExerciseService(_apiClient);
    _lifts = LiftRecordService(_apiClient);
    _admin = AdminService(_apiClient);
    _router = GoRouter(
      navigatorKey: _rootNavigator,
      refreshListenable: _authState,
      redirect: _redirect,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(
          path: '/login',
          builder: (_, state) => LoginPage(
            authState: _authState,
            registeredEmail: state.extra is String
                ? state.extra as String
                : null,
            onRegister: () => _router.go(_authLocation('/register', state.uri)),
          ),
        ),
        GoRoute(
          path: '/register',
          builder: (_, state) => RegistrationPage(
            authState: _authState,
            onBack: () => _router.go(_authLocation('/login', state.uri)),
            onRegistered: (email) =>
                _router.go(_authLocation('/login', state.uri), extra: email),
          ),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => UserWorkspace(
            authState: _authState,
            navigationShell: navigationShell,
            onAddLift: _openAddLift,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/training',
                  builder: (_, _) => TrainingZonePage(
                    key: _training,
                    authState: _authState,
                    liftRecordService: _lifts,
                    onAddLift: _openAddLift,
                  ),
                  routes: [
                    GoRoute(
                      path: 'add-lift',
                      // Cover the workspace, including its app bar and drawer.
                      parentNavigatorKey: _rootNavigator,
                      builder: (_, state) => AddLiftPage(
                        authState: _authState,
                        exerciseService: _exercises,
                        liftRecordService: _lifts,
                        initialUnit: state.uri.queryParameters['unit'] == 'kg'
                            ? 'kg'
                            : 'lb',
                        onSaved: _liftSaved,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (_, _) => ListenableBuilder(
                    listenable: _authState,
                    builder: (_, _) => ProfilePage(authState: _authState),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/admin',
          builder: (_, _) => ListenableBuilder(
            listenable: _authState,
            builder: (_, _) =>
                AdminPage(authState: _authState, adminService: _admin),
          ),
        ),
      ],
    );
    _authState.addListener(_storageNotice);
    unawaited(_authState.restoreSession());
  }

  // Only return to known in-app destinations. An external URL supplied in a
  // query parameter must never become the post-login destination.
  String? _destination(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    if (!const {
      '/training',
      '/training/add-lift',
      '/profile',
      '/admin',
    }.contains(uri.path)) {
      return null;
    }
    return Uri(
      path: uri.path,
      queryParameters:
          uri.path == '/training/add-lift' &&
              uri.queryParameters['unit'] == 'kg'
          ? {'unit': 'kg'}
          : null,
    ).toString();
  }

  String _authLocation(String path, Uri current) => Uri(
    path: path,
    queryParameters: _destination(current.queryParameters['from']) == null
        ? null
        : {'from': _destination(current.queryParameters['from'])!},
  ).toString();

  String? _redirect(BuildContext context, GoRouterState state) {
    final path = state.uri.path;
    final publicPage = path == '/login' || path == '/register';
    if (!_authState.isAuthenticated) {
      if (_wasAuthenticated) {
        // Logging out drops every private route, including open dialogs. A
        // deliberate new sign-in starts at the appropriate role's home page.
        _wasAuthenticated = false;
        return '/login';
      }
      if (publicPage) return null;
      // Browser route-information events can contain an absolute URL. Keep
      // only its local path and query when remembering the requested page.
      final destination = _destination(
        Uri(path: path, query: state.uri.query).toString(),
      );
      return Uri(
        path: '/login',
        queryParameters: destination == null ? null : {'from': destination},
      ).toString();
    }
    _wasAuthenticated = true;
    final home = _authState.user!.isAdmin ? '/admin' : '/training';
    if (publicPage || path == '/') {
      return _destination(state.uri.queryParameters['from']) ?? home;
    }
    // Client-side guards keep the UI appropriate to the signed-in role.
    // The backend continues to enforce permissions on every API request.
    if (_authState.user!.isAdmin) return path == '/admin' ? null : home;
    if (path == '/admin' || _destination(path) == null) {
      return home;
    }
    return null;
  }

  void _openAddLift() {
    if (_authState.isLoading) return;
    _router.go(
      Uri(
        path: '/training/add-lift',
        queryParameters: _training.currentState?.unit == 'kg'
            ? {'unit': 'kg'}
            : null,
      ).toString(),
    );
  }

  Future<void> _liftSaved(LiftRecord record) async {
    _router.go('/training');
    await _training.currentState?.reload(
      selectExerciseId: record.exerciseId,
      unit: record.unit,
    );
    if (mounted && _authState.isAuthenticated) {
      _messenger.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Lift saved. Your history is up to date.'),
        ),
      );
    }
  }

  void _storageNotice() {
    final message = _authState.storageMessage;
    if (message == null) {
      _lastStorageMessage = null;
      return;
    }
    if (message == _lastStorageMessage) return;
    _lastStorageMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _messenger.currentState?.showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    debugShowCheckedModeBanner: false,
    title: 'MaxReps',
    theme: buildAppTheme(),
    scaffoldMessengerKey: _messenger,
    routerConfig: _router,
    builder: (context, child) => ListenableBuilder(
      listenable: _authState,
      builder: (context, _) {
        if (_authState.isRestoring) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Do not mount private pages before JWT validation finishes. Keeping
        // the initial URL intact lets refresh restore Profile or Add Lift.
        return child!;
      },
    ),
  );

  @override
  void dispose() {
    _authState.removeListener(_storageNotice);
    _router.dispose();
    _authState.dispose();
    _apiClient.close();
    super.dispose();
  }
}
