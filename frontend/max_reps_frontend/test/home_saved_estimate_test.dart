import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:max_reps_frontend/pages/home.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/auth_service.dart';
import 'package:max_reps_frontend/services/exercise_service.dart';
import 'package:max_reps_frontend/services/lift_record_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';

// Use the real services with an in-memory HTTP client. These tests never access
// the database or a running server, and can inspect the requests the page sends.
http.Response jsonResponse(Object data, [int status = 200]) {
  return http.Response(jsonEncode(data), status);
}

Map<String, Object> savedRecord({
  double estimate = 100,
  String unit = 'lb',
  int exerciseId = 1,
}) {
  return {
    'id': 'saved-lift',
    'user_id': 'test-user',
    'exercise_id': exerciseId,
    'reps': 5,
    'attempted_at': '2026-10-01T12:00:00Z',
    'weight': 80,
    'unit': unit,
    'one_rep_max_est': estimate,
  };
}

Future<AuthState> showHome(
  WidgetTester tester, {
  required FutureOr<http.Response> Function(http.Request) history,
  FutureOr<http.Response> Function(http.Request)? create,
}) async {
  // A tall viewport keeps the form and saved-result cards visible during tests.
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final client = ApiClient(
    client: MockClient((request) async {
      switch (request.url.path) {
        case '/users/token':
          return jsonResponse({
            'access_token': 'test-token',
            'token_type': 'bearer',
          });
        case '/users/me':
          return jsonResponse({'id': 'test-user', 'email': 'test@example.com'});
        case '/exercises/':
          return jsonResponse([
            {'id': 1, 'name': 'Bench press', 'category': 'strength'},
            {'id': 2, 'name': 'Squat', 'category': 'strength'},
          ]);
        case '/lift_record/':
          if (request.method == 'GET') return await history(request);
          if (request.method == 'POST' && create != null) {
            return await create(request);
          }
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    }),
  );
  final auth = AuthState(AuthService(client));
  addTearDown(client.close);
  addTearDown(auth.dispose);
  await auth.login(email: 'test@example.com', password: 'test-password');

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: HomePage(
        authState: auth,
        exerciseService: ExerciseService(client),
        liftRecordService: LiftRecordService(client),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> selectExercise(WidgetTester tester, String name) async {
  final field = find.byType(TextFormField).first;
  await tester.ensureVisible(field);
  await tester.enterText(field, name);
  await tester.pumpAndSettle();
  // Both the text field and its autocomplete suggestion contain this name.
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads the latest saved estimate and its percentages', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await showHome(
      tester,
      history: (request) {
        requests.add(request);
        return jsonResponse([savedRecord()]);
      },
    );

    // Opening the page alone should not fetch unfiltered lift history.
    expect(requests, isEmpty);
    await selectExercise(tester, 'Bench press');

    final request = requests.single;
    expect(request.headers['Authorization'], 'Bearer test-token');
    expect(request.url.queryParameters, {
      'exercise_id': '1',
      'unit': 'lb',
      'offset': '0',
      'limit': '1',
    });
    expect(find.text('Latest saved 1RM'), findsOneWidget);
    expect(find.text('Estimated 1RM: 100.00 lb'), findsOneWidget);
    expect(
      find.text('Attempted at: 10/01/2026 at 12:00 PM UTC'),
      findsOneWidget,
    );
    for (final percentage in [50, 60, 70, 80, 90]) {
      expect(find.text('$percentage%'), findsOneWidget);
      expect(find.text('${percentage.toStringAsFixed(2)} lb'), findsOneWidget);
    }
  });

  testWidgets('explains when the selected exercise has no saved estimate', (
    tester,
  ) async {
    await showHome(tester, history: (_) => jsonResponse([]));
    await selectExercise(tester, 'Bench press');

    expect(find.text('No saved estimate for Bench press yet.'), findsOneWidget);
    expect(find.text('Percentages of estimated 1RM'), findsNothing);
  });

  testWidgets(
    'retries lookup failures without treating them as empty history',
    (tester) async {
      var calls = 0;
      await showHome(
        tester,
        history: (_) {
          calls++;
          return calls == 1
              ? jsonResponse({'detail': 'Unavailable'}, 503)
              : jsonResponse([savedRecord()]);
        },
      );
      await selectExercise(tester, 'Bench press');

      expect(
        find.text('Could not load your saved estimate. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('No saved estimate for Bench press yet.'), findsNothing);
      await tester.tap(find.text('Retry saved estimate'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Estimated 1RM: 100.00 lb'), findsOneWidget);
    },
  );

  testWidgets('ignores a late response for a previously selected exercise', (
    tester,
  ) async {
    // A Completer lets the test finish an older request after a newer request.
    final oldResponse = Completer<http.Response>();
    await showHome(
      tester,
      history: (request) {
        if (request.url.queryParameters['exercise_id'] == '1') {
          return oldResponse.future;
        }
        return jsonResponse([savedRecord(estimate: 160, exerciseId: 2)]);
      },
    );
    await selectExercise(tester, 'Bench press');
    expect(find.text('Loading your saved estimate...'), findsOneWidget);
    await selectExercise(tester, 'Squat');
    oldResponse.complete(jsonResponse([savedRecord()]));
    await tester.pumpAndSettle();

    expect(find.text('Estimated 1RM: 160.00 lb'), findsOneWidget);
    expect(find.text('Estimated 1RM: 100.00 lb'), findsNothing);
  });

  testWidgets('refetches in kilograms and ignores an older pounds response', (
    tester,
  ) async {
    final poundsResponse = Completer<http.Response>();
    await showHome(
      tester,
      history: (request) {
        if (request.url.queryParameters['unit'] == 'lb') {
          return poundsResponse.future;
        }
        return jsonResponse([savedRecord(estimate: 45.36, unit: 'kg')]);
      },
    );
    await selectExercise(tester, 'Bench press');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilograms (kg)').last);
    await tester.pumpAndSettle();
    poundsResponse.complete(jsonResponse([savedRecord()]));
    await tester.pumpAndSettle();

    expect(find.text('Estimated 1RM: 45.36 kg'), findsOneWidget);
    expect(find.text('22.68 kg'), findsOneWidget);
    expect(find.text('Estimated 1RM: 100.00 lb'), findsNothing);
  });

  testWidgets('clears the saved estimate when the exercise text is edited', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    await showHome(tester, history: (_) => response.future);
    await selectExercise(tester, 'Bench press');
    await tester.enterText(find.byType(TextFormField).first, 'Something else');
    response.complete(jsonResponse([savedRecord()]));
    await tester.pumpAndSettle();

    expect(find.text('Latest saved 1RM'), findsNothing);
    expect(find.text('Estimated 1RM: 100.00 lb'), findsNothing);
  });

  testWidgets('refreshes the saved estimate after a new lift is stored', (
    tester,
  ) async {
    var stored = false;
    await showHome(
      tester,
      history: (_) => jsonResponse([savedRecord(estimate: stored ? 120 : 100)]),
      create: (_) {
        stored = true;
        return jsonResponse(savedRecord(estimate: 120), 201);
      },
    );
    await selectExercise(tester, 'Bench press');
    await tester.enterText(find.byType(TextFormField).at(1), '5');
    await tester.enterText(find.byType(TextFormField).at(2), '100');
    await tester.tap(find.text('Calculate 1RM'));
    await tester.pumpAndSettle();

    // Refresh the saved card without duplicating the same record in the session.
    expect(find.text('Estimated 1RM: 120.00 lb'), findsOneWidget);
    expect(find.text('Estimated 1RM: 100.00 lb'), findsNothing);
  });

  testWidgets('expires the session when history returns unauthorized', (
    tester,
  ) async {
    final auth = await showHome(
      tester,
      history: (_) => jsonResponse({'detail': 'Not authenticated'}, 401),
    );
    await selectExercise(tester, 'Bench press');

    expect(auth.isAuthenticated, isFalse);
    expect(
      find.text('Your session expired. Please sign in again.'),
      findsOneWidget,
    );
  });
}
