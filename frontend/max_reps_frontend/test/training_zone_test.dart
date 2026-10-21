import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:max_reps_frontend/app.dart';
import 'package:max_reps_frontend/pages/add_lift_page.dart';
import 'package:max_reps_frontend/pages/training_zone_page.dart';
import 'package:max_reps_frontend/utils/date_format.dart';
import 'package:max_reps_frontend/widgets/lift_history_card.dart';
import 'support/app_test_support.dart';

void main() {
  setUpAll(loadPreviewFonts);

  testWidgets(
    'restores sign-in, shows five records, and expands only the latest splits',
    (tester) async {
      final backend = TestBackend();
      await showApp(tester, backend, MemoryTokenStorage(backend.token));
      expect(find.byType(TrainingZonePage), findsOneWidget);
      expect(backend.calls('/exercises/'), isEmpty);
      final request = backend.calls('/lift_record/').single;
      expect(request.url.queryParameters, {
        'unit': 'lb',
        'exercise_id': '1',
        'offset': '0',
        'limit': '5',
      });
      expect(find.byType(LiftHistoryCard), findsNWidgets(5));
      expect(find.text('157.50 lb'), findsOneWidget);
      expect(find.text('152.50 lb'), findsNothing);
      // The expected label follows the machine's timezone, just like the UI.
      expect(
        find.text(formatUsLocal(DateTime.parse('2026-10-21T17:30:00Z'))),
        findsOneWidget,
      );
      expect(find.text('90%'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('90%')).dy,
        lessThan(tester.getTopLeft(find.text('50%')).dy),
      );
      expect(find.text('141.75 lb'), findsOneWidget);
      expect(find.text('Add New Lift'), findsOneWidget);
      await capture(tester, 'training-desktop');

      // Only exercises present in this user's history can be selected here.
      await tester.enterText(field('Search your logged exercises'), 'Deadlift');
      await tester.pumpAndSettle();
      expect(
        find.text('Deadlift'),
        findsOneWidget,
      ); // typed text, no suggestion
      expect(find.byType(LiftHistoryCard), findsNothing);
      await selectExercise(tester, 'Squat');
      expect(find.byType(LiftHistoryCard), findsOneWidget);
      expect(find.text('210.00 lb'), findsOneWidget);
    },
  );

  testWidgets(
    'empty history offers add action and cancel leaves history unchanged',
    (tester) async {
      final backend = TestBackend(empty: true);
      await showApp(tester, backend, MemoryTokenStorage(backend.token));
      expect(find.text('Nothing Logged.'), findsOneWidget);
      expect(find.text('To Add A Lift'), findsOneWidget);
      await capture(tester, 'empty-desktop');
      await tester.tap(find.text('To Add A Lift'));
      await tester.pumpAndSettle();
      expect(find.byType(AddLiftPage), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.calls('/lift_record/', 'POST'), isEmpty);
      expect(find.text('Nothing Logged.'), findsOneWidget);
    },
  );

  testWidgets('adding a new exercise returns to its refreshed history', (
    tester,
  ) async {
    final backend = TestBackend();
    await showApp(tester, backend, MemoryTokenStorage(backend.token));
    await tester.tap(find.byTooltip('Add a new lift'));
    await tester.pumpAndSettle();
    await capture(tester, 'add-lift-desktop');
    await selectExercise(tester, 'Deadlift');
    await tester.enterText(field('Repetitions'), '5');
    await tester.enterText(field('Weight'), '180');
    await tester.ensureVisible(find.text('Save lift'));
    await tester.tap(find.text('Save lift'));
    await tester.pumpAndSettle();
    expect(find.byType(AddLiftPage), findsNothing);
    expect(find.byType(LiftHistoryCard), findsOneWidget);
    expect(find.text('210.00 lb'), findsOneWidget);
    expect(backend.calls('/lift_record/', 'POST').length, 1);
    expect(
      backend.calls('/lift_record/').last.url.queryParameters['exercise_id'],
      '3',
    );
    expect(
      find.text('Lift saved. Your history is up to date.'),
      findsOneWidget,
    );
  });

  testWidgets('failed lookups show retry and never claim empty history', (
    tester,
  ) async {
    final backend = TestBackend();
    backend.override = (request) => request.url.path == '/lift_record/'
        ? backend.json({'detail': 'Unavailable'}, 503)
        : null;
    await showApp(tester, backend, MemoryTokenStorage(backend.token));
    expect(
      find.text('Could not load your lift records. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Nothing Logged.'), findsNothing);
    backend.override = null;
    await tester.tap(find.text('Retry records'));
    await tester.pumpAndSettle();
    expect(find.byType(LiftHistoryCard), findsNWidgets(5));
  });

  testWidgets('late exercise responses cannot overwrite the current selection', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    final backend = TestBackend();
    backend.override = (request) =>
        request.url.path == '/lift_record/' &&
            request.url.queryParameters['exercise_id'] == '1'
        ? old.future
        : null;
    // A pending request intentionally keeps a spinner running; do not settle it.
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = backend.client();
    await tester.pumpWidget(
      MainApp(
        apiClient: client,
        tokenStorage: MemoryTokenStorage(backend.token),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(field('Search your logged exercises'), 'Squat');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Squat').last);
    await tester.pumpAndSettle();
    old.complete(backend.json([backend.records.first]));
    await tester.pumpAndSettle();
    expect(find.text('210.00 lb'), findsOneWidget);
    expect(find.text('157.50 lb'), findsNothing);
  });

  testWidgets('unit changes refetch all five records and percentage weights', (
    tester,
  ) async {
    final backend = TestBackend();
    await showApp(tester, backend, MemoryTokenStorage(backend.token));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilograms (kg)').last);
    await tester.pumpAndSettle();
    expect(
      backend.calls('/lift_record/').last.url.queryParameters['unit'],
      'kg',
    );
    expect(find.text('71.44 kg'), findsOneWidget);
    expect(find.text('64.30 kg'), findsOneWidget);
    expect(find.text('157.50 lb'), findsNothing);
  });
}
