import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:max_reps_frontend/app.dart';
import 'package:max_reps_frontend/pages/add_lift_page.dart';
import 'package:max_reps_frontend/pages/admin_page.dart';
import 'package:max_reps_frontend/pages/login_page.dart';
import 'package:max_reps_frontend/pages/profile_page.dart';
import 'package:max_reps_frontend/pages/registration_page.dart';
import 'package:max_reps_frontend/pages/training_zone_page.dart';
import 'support/app_test_support.dart';

GoRouter router(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
        as GoRouter;

Uri location(WidgetTester tester) =>
    router(tester).routeInformationProvider.value.uri;

// Send the route-information event Flutter receives from browser Back/Forward.
Future<void> browserVisit(WidgetTester tester, String path) async {
  await router(tester).routeInformationProvider.didPushRouteInformation(
    RouteInformation(uri: Uri.parse(path)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPreviewFonts);

  testWidgets(
    'deep links wait for server validation before displaying private pages',
    (tester) async {
      final validation = Completer<http.Response>();
      final backend = TestBackend();
      backend.override = (request) =>
          request.url.path == '/users/me' ? validation.future : null;
      tester.platformDispatcher.defaultRouteNameTestValue = '/profile';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(
        MainApp(
          apiClient: backend.client(),
          tokenStorage: MemoryTokenStorage(backend.token),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ProfilePage), findsNothing);
      expect(backend.calls('/lift_record/exercises'), isEmpty);
      expect(location(tester).path, '/profile');
      validation.complete(
        backend.json({
          'id': 'test-user',
          'email': backend.email,
          'is_admin': false,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(location(tester).path, '/profile');
    },
  );

  testWidgets(
    'refreshing Profile restores that URL rather than Training Zone',
    (tester) async {
      final backend = TestBackend();
      final storage = MemoryTokenStorage(backend.token);
      await showApp(tester, backend, storage);
      await openProfile(tester);
      expect(location(tester).path, '/profile');

      // Recreate the whole app with only the token and current URL preserved.
      // This loses all widget state, as a real browser refresh would.
      await showApp(tester, backend, storage, location: '/profile');
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.byType(TrainingZonePage), findsNothing);
      expect(location(tester).path, '/profile');
      expect(backend.calls('/users/token'), isEmpty);
      expect(backend.calls('/users/me').length, 2);
    },
  );

  testWidgets('drawer and browser navigation preserve the selected exercise', (
    tester,
  ) async {
    final backend = TestBackend();
    await showApp(tester, backend, MemoryTokenStorage(backend.token));
    await selectExercise(tester, 'Squat');
    final historyRequests = backend.calls('/lift_record/').length;
    await openProfile(tester);
    expect(location(tester).path, '/profile');
    await browserVisit(tester, '/training');
    expect(find.byType(TrainingZonePage), findsOneWidget);
    expect(find.text('210.00 lb'), findsOneWidget);
    expect(backend.calls('/lift_record/').length, historyRequests);
    await browserVisit(tester, '/profile');
    expect(find.byType(ProfilePage), findsOneWidget);
    await openMenu(tester);
    await tester.tap(find.text('Training Zone').last);
    await tester.pumpAndSettle();
    expect(location(tester).path, '/training');
    expect(find.text('210.00 lb'), findsOneWidget);
  });

  for (final signedIn in [false, true]) {
    testWidgets(
      'absolute browser URL preserves Profile when signed in: $signedIn',
      (tester) async {
        final backend = TestBackend();
        await showApp(
          tester,
          backend,
          MemoryTokenStorage(signedIn ? backend.token : null),
        );
        await browserVisit(tester, 'http://localhost:3000/profile');
        if (!signedIn) {
          expect(location(tester).queryParameters['from'], '/profile');
          await signIn(tester);
        }
        expect(find.byType(ProfilePage), findsOneWidget);
        expect(location(tester).path, '/profile');
      },
    );
  }

  for (final expired in [false, true]) {
    testWidgets(
      '${expired ? 'expired token' : 'signed-out visit'} returns to Profile after login',
      (tester) async {
        final backend = TestBackend()..rejectToken = expired;
        final storage = MemoryTokenStorage(expired ? 'expired-token' : null);
        await showApp(tester, backend, storage, location: '/profile');
        expect(find.byType(LoginPage), findsOneWidget);
        expect(location(tester).path, '/login');
        expect(location(tester).queryParameters['from'], '/profile');
        expect(storage.value, isNull);
        expect(backend.calls('/lift_record/exercises'), isEmpty);
        backend.rejectToken = false;
        await signIn(tester);
        expect(location(tester).path, '/profile');
        expect(find.byType(ProfilePage), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Add Lift URL survives refresh, retains units, and returns after saving',
    (tester) async {
      final backend = TestBackend();
      final storage = MemoryTokenStorage(backend.token);
      await showApp(tester, backend, storage);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilograms (kg)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add a new lift'));
      await tester.pumpAndSettle();
      expect(location(tester).path, '/training/add-lift');
      expect(location(tester).queryParameters['unit'], 'kg');
      final savedUrl = location(tester).toString();
      await showApp(tester, backend, storage, location: savedUrl);
      expect(find.byType(AddLiftPage), findsOneWidget);
      expect(find.text('Kilograms (kg)').hitTestable(), findsOneWidget);
      await selectExercise(tester, 'Deadlift');
      await tester.enterText(field('Repetitions'), '5');
      await tester.enterText(field('Weight'), '100');
      await tester.ensureVisible(find.text('Save lift'));
      await tester.tap(find.text('Save lift'));
      await tester.pumpAndSettle();
      expect(location(tester).path, '/training');
      expect(find.byType(AddLiftPage), findsNothing);
      expect(find.text('116.67 kg'), findsOneWidget);
      expect(
        backend.calls('/lift_record/').last.url.queryParameters['exercise_id'],
        '3',
      );
    },
  );

  testWidgets('Add Lift opened directly can cancel back to Training Zone', (
    tester,
  ) async {
    final backend = TestBackend();
    await showApp(
      tester,
      backend,
      MemoryTokenStorage(backend.token),
      location: '/training/add-lift',
    );
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(location(tester).path, '/training');
    expect(find.byType(TrainingZonePage), findsOneWidget);
    expect(backend.calls('/lift_record/', 'POST'), isEmpty);
  });

  for (final admin in [false, true]) {
    testWidgets(
      '${admin ? 'admin' : 'regular user'} receives only authorized workspace URLs',
      (tester) async {
        final backend = TestBackend(admin: admin);
        final storage = MemoryTokenStorage(backend.token);
        await showApp(
          tester,
          backend,
          storage,
          location: admin ? '/profile' : '/admin',
        );
        expect(location(tester).path, admin ? '/admin' : '/training');
        expect(find.byType(AdminPage), admin ? findsOneWidget : findsNothing);
        expect(
          find.byType(TrainingZonePage),
          admin ? findsNothing : findsOneWidget,
        );
        if (admin) {
          expect(backend.calls('/lift_record/exercises'), isEmpty);
          await showApp(tester, backend, storage, location: '/admin');
          expect(location(tester).path, '/admin');
          expect(find.byType(AdminPage), findsOneWidget);
        } else {
          expect(backend.calls('/admin/stats'), isEmpty);
        }
      },
    );
  }

  testWidgets('logout removes Profile and Back cannot reopen private pages', (
    tester,
  ) async {
    final backend = TestBackend();
    final storage = MemoryTokenStorage(backend.token);
    await showApp(tester, backend, storage, location: '/profile');
    await tester.tap(find.text('Update email'));
    await tester.pumpAndSettle();
    // A route event to a public page while authenticated stays in the workspace.
    router(tester).go('/login');
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await openMenu(tester);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(location(tester).path, '/login');
    expect(storage.value, isNull);
    await browserVisit(tester, '/profile');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(ProfilePage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'registration has its own URL and keeps the requested destination',
    (tester) async {
      final backend = TestBackend();
      await showApp(
        tester,
        backend,
        MemoryTokenStorage(),
        location: '/profile',
      );
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      expect(location(tester).path, '/register');
      expect(location(tester).queryParameters['from'], '/profile');
      expect(find.byType(RegistrationPage), findsOneWidget);
      await tester.enterText(field('Email'), 'test@example.com');
      await tester.enterText(field('Password'), 'correct-password');
      await tester.enterText(field('Confirm password'), 'correct-password');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(location(tester).path, '/login');
      expect(location(tester).queryParameters['from'], '/profile');
      expect(
        tester.widget<TextField>(field('Email')).controller!.text,
        'test@example.com',
      );
      expect(
        find.text('Account created. Sign in to continue.'),
        findsOneWidget,
      );
      await signIn(tester);
      expect(location(tester).path, '/profile');
    },
  );

  for (final destination in [
    'https://example.com/profile',
    '//example.com/profile',
    '/missing',
  ]) {
    testWidgets(
      'unrecognized return destination $destination falls back to home',
      (tester) async {
        final backend = TestBackend();
        await showApp(
          tester,
          backend,
          MemoryTokenStorage(backend.token),
          location: Uri(
            path: '/login',
            queryParameters: {'from': destination},
          ).toString(),
        );
        expect(location(tester).path, '/training');
        expect(find.byType(TrainingZonePage), findsOneWidget);
      },
    );
  }
}
