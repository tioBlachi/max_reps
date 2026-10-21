import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:max_reps_frontend/pages/add_lift_page.dart';
import 'package:max_reps_frontend/pages/admin_page.dart';
import 'package:max_reps_frontend/pages/login_page.dart';
import 'package:max_reps_frontend/pages/profile_page.dart';
import 'package:max_reps_frontend/pages/training_zone_page.dart';
import 'support/app_test_support.dart';

void main() {
  setUpAll(loadPreviewFonts);

  for (final email in [
    'test@example.com',
    'TEST@EXAMPLE.COM',
    '  test@example.com  ',
  ]) {
    testWidgets(
      'unchanged email $email shows validation without sending a request',
      (tester) async {
        final backend = TestBackend();
        final storage = MemoryTokenStorage(backend.token);
        await showApp(tester, backend, storage);
        await openProfile(tester);
        await tester.tap(find.text('Update email'));
        await tester.pumpAndSettle();
        await tester.enterText(field('New email'), email);
        await tester.enterText(field('Current password'), 'correct-password');
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();

        expect(
          find.text('New email must be different from your current email.'),
          findsOneWidget,
        );
        expect(backend.calls('/users/me/email'), isEmpty);
        expect(backend.email, 'test@example.com');
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(storage.value, backend.token);
      },
    );
  }

  testWidgets(
    'unchanged password shows validation and keeps the user signed in',
    (tester) async {
      final backend = TestBackend();
      final storage = MemoryTokenStorage(backend.token);
      await showApp(tester, backend, storage);
      await openProfile(tester);
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'correct-password');
      await tester.enterText(field('New password'), 'correct-password');
      await tester.enterText(field('Confirm new password'), 'correct-password');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(
        find.text('New password must be different from your current password.'),
        findsOneWidget,
      );
      expect(backend.calls('/users/me/password'), isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(storage.value, backend.token);

      // Password comparison is exact: changing letter case is a real change.
      await tester.enterText(field('New password'), 'Correct-password');
      await tester.enterText(field('Confirm new password'), 'Correct-password');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(backend.calls('/users/me/password').length, 1);
      expect(backend.password, 'Correct-password');
      expect(find.byType(LoginPage), findsOneWidget);
    },
  );

  testWidgets(
    'valid stored token survives an app restart without logging in again',
    (tester) async {
      final backend = TestBackend();
      final storage = MemoryTokenStorage();
      await showApp(tester, backend, storage);
      expect(find.byType(LoginPage), findsOneWidget);
      await capture(tester, 'login-desktop');
      await signIn(tester);
      expect(storage.value, backend.token);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(
        storage.value,
        backend.token,
      ); // disposing widgets must not log out
      await showApp(tester, backend, storage);
      expect(find.byType(TrainingZonePage), findsOneWidget);
      expect(backend.calls('/users/token').length, 1);
      expect(backend.calls('/users/me').length, 2);
      await openMenu(tester);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('Training Zone'), findsWidgets);
      expect(find.text('Profile'), findsOneWidget);
      await capture(tester, 'drawer');
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(storage.value, isNull);
      expect(find.byType(LoginPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TrainingZonePage), findsNothing);
    },
  );

  testWidgets('expired or revoked saved tokens are removed and show login', (
    tester,
  ) async {
    final backend = TestBackend()..rejectToken = true;
    final storage = MemoryTokenStorage('expired-token');
    await showApp(tester, backend, storage);
    expect(storage.value, isNull);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(backend.calls('/lift_record/exercises'), isEmpty);
  });

  testWidgets(
    'temporary restoration failures show login and preserve the token',
    (tester) async {
      final backend = TestBackend()..profileUnavailable = true;
      final storage = MemoryTokenStorage(backend.token);
      await showApp(tester, backend, storage);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Retry sign-in restoration'), findsNothing);
      expect(storage.value, backend.token);
      backend.profileUnavailable = false;
      await showApp(tester, backend, storage);
      expect(find.byType(TrainingZonePage), findsOneWidget);
    },
  );

  testWidgets('storage failure still permits sign-in for the current visit', (
    tester,
  ) async {
    final backend = TestBackend();
    final storage = MemoryTokenStorage()..failRead = true;
    await showApp(tester, backend, storage);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Sign in instead'), findsNothing);
    storage.failWrite = true;
    await signIn(tester);
    expect(find.byType(TrainingZonePage), findsOneWidget);
    expect(
      find.text('Signed in, but this browser could not remember your session.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'email validation and server errors preserve state; successful update refreshes drawer',
    (tester) async {
      final backend = TestBackend();
      final storage = MemoryTokenStorage(backend.token);
      await showApp(tester, backend, storage);
      await openProfile(tester);
      await capture(tester, 'profile-desktop');
      await tester.tap(find.text('Update email'));
      await tester.pumpAndSettle();
      await capture(tester, 'email-dialog');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(backend.calls('/users/me/email'), isEmpty);

      await tester.enterText(field('New email'), 'new@example.com');
      await tester.enterText(field('Current password'), 'wrong');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Your current password is incorrect.'), findsOneWidget);
      expect(backend.email, 'test@example.com');

      await tester.enterText(field('Current password'), 'correct-password');
      await tester.enterText(field('New email'), 'taken@example.com');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        find.text('That email address is already registered.'),
        findsOneWidget,
      );
      await tester.enterText(field('New email'), 'new@example.com');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(backend.email, 'new@example.com');
      expect(storage.value, backend.token);
      await openMenu(tester);
      expect(find.text('new@example.com'), findsWidgets);
      expect(find.text('test@example.com'), findsNothing);
      await tester.tap(find.text('Training Zone').last);
      await tester.pumpAndSettle();
      expect(find.text('157.50 lb'), findsOneWidget);
    },
  );

  testWidgets(
    'password confirmation prevents mistakes and a successful change clears session',
    (tester) async {
      final backend = TestBackend();
      final storage = MemoryTokenStorage(backend.token);
      await showApp(tester, backend, storage);
      await openProfile(tester);
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      await capture(tester, 'password-dialog');
      await tester.enterText(field('Current password'), 'correct-password');
      await tester.enterText(field('New password'), 'new-password-123');
      await tester.enterText(field('Confirm new password'), 'does-not-match');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(backend.calls('/users/me/password'), isEmpty);
      await tester.enterText(field('Confirm new password'), 'new-password-123');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(storage.value, isNull);
      expect(backend.password, 'new-password-123');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsNothing);
    },
  );

  testWidgets(
    'deactivation cancellation is harmless, confirmation signs out and permits reactivation',
    (tester) async {
      final backend = TestBackend();
      final storage = MemoryTokenStorage(backend.token);
      await showApp(tester, backend, storage);
      await openProfile(tester);
      final deactivate = find.widgetWithText(
        OutlinedButton,
        'Deactivate account',
      );
      await tester.tap(deactivate);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.calls('/users/me/deactivate'), isEmpty);
      await tester.tap(deactivate);
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'wrong');
      await tester.tap(find.text('Confirm deactivation'));
      await tester.pumpAndSettle();
      expect(find.text('Your current password is incorrect.'), findsOneWidget);
      expect(storage.value, backend.token);
      await tester.enterText(field('Current password'), 'correct-password');
      await tester.tap(find.text('Confirm deactivation'));
      await tester.pumpAndSettle();
      expect(backend.inactive, isTrue);
      expect(storage.value, isNull);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await signIn(tester);
      await tester.tap(find.text('Yes, reactivate'));
      await tester.pumpAndSettle();
      expect(find.byType(TrainingZonePage), findsOneWidget);
      expect(storage.value, backend.token);
    },
  );

  testWidgets(
    'restored admin dashboard keeps stats and confirmed 90-day cleanup',
    (tester) async {
      final backend = TestBackend(admin: true);
      await showApp(tester, backend, MemoryTokenStorage(backend.token));
      expect(find.byType(AdminPage), findsOneWidget);
      expect(find.byType(TrainingZonePage), findsNothing);
      expect(backend.calls('/lift_record/exercises'), isEmpty);
      expect(find.text('Total users'), findsOneWidget);
      expect(find.text('Active users'), findsOneWidget);
      expect(find.text('Inactive users'), findsOneWidget);
      await capture(tester, 'admin-unchanged');
      await tester.tap(find.text('Review inactive accounts'));
      await tester.pumpAndSettle();
      expect(backend.calls('/admin/inactive-users/cleanup', 'DELETE'), isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review inactive accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Permanently delete'));
      await tester.pumpAndSettle();
      expect(
        backend.calls('/admin/inactive-users/cleanup', 'DELETE').length,
        1,
      );
      expect(find.text('0 eligible accounts'), findsOneWidget);
    },
  );

  testWidgets(
    'private add-lift route disappears if the server rejects the session',
    (tester) async {
      final backend = TestBackend();
      final storage = MemoryTokenStorage(backend.token);
      await showApp(tester, backend, storage);
      await tester.tap(find.byTooltip('Add a new lift'));
      await tester.pumpAndSettle();
      expect(find.byType(AddLiftPage), findsOneWidget);
      await selectExercise(tester, 'Deadlift');
      await tester.enterText(field('Repetitions'), '5');
      await tester.enterText(field('Weight'), '180');
      backend.rejectToken = true;
      await tester.ensureVisible(find.text('Save lift'));
      await tester.tap(find.text('Save lift'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AddLiftPage), findsNothing);
      expect(storage.value, isNull);
    },
  );

  for (final width in [360.0, 768.0]) {
    testWidgets('user screens and dialogs fit a ${width.toInt()}px viewport', (
      tester,
    ) async {
      final backend = TestBackend();
      await showApp(tester, backend, MemoryTokenStorage(), width: width);
      await capture(tester, 'login-${width.toInt()}');
      await signIn(tester);
      await capture(tester, 'training-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Add a new lift'));
      await tester.pumpAndSettle();
      await capture(tester, 'add-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await openProfile(tester);
      await capture(tester, 'profile-${width.toInt()}');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      await capture(tester, 'password-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Deactivate account'),
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Deactivate account'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  }
}
