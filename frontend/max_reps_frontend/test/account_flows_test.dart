import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:max_reps_frontend/app.dart';
import 'package:max_reps_frontend/pages/admin_page.dart';
import 'package:max_reps_frontend/pages/home.dart';
import 'package:max_reps_frontend/pages/login_page.dart';
import 'package:max_reps_frontend/pages/registration_page.dart';
import 'package:max_reps_frontend/services/admin_service.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/auth_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';

// This fake server handles HTTP in memory. The app uses its real API services,
// auth state, dialogs, and navigation; no test can delete a real account.
class TestBackend {
  final bool admin;
  bool inactive = false;
  bool failCleanup = false;
  bool failDashboard = false;
  int eligible = 2;
  int total = 10;
  int inactiveCount = 3;
  final requests = <http.Request>[];

  TestBackend({this.admin = false});

  http.Response json(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/users/token' || path == '/users/reactivate') {
      if (path == '/users/token' && inactive) {
        return json({'detail': 'Inactive user'}, 403);
      }
      inactive = false;
      return json({'access_token': 'test-token', 'token_type': 'bearer'});
    }
    if (path == '/users/me' || path == '/users') {
      return json({
        'id': 'test-user',
        'email': admin ? 'admin@example.com' : 'test@example.com',
        'is_admin': admin,
      }, path == '/users' ? 201 : 200);
    }
    if (path == '/users/me/deactivate') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['current_password'] != 'correct-password') {
        return json({'detail': 'Current password is incorrect'}, 403);
      }
      inactive = true;
      return http.Response('', 204);
    }
    if (path == '/exercises/') {
      return json([
        {'id': 1, 'name': 'Bench press', 'category': 'strength'},
      ]);
    }
    if (path == '/lift_record/') {
      return json([
        {
          'id': 'old-lift',
          'user_id': 'test-user',
          'exercise_id': 1,
          'reps': 5,
          'weight': 135,
          'unit': request.url.queryParameters['unit'] ?? 'lb',
          'one_rep_max_est': 157.5,
          'attempted_at': '2026-10-01T17:30:00Z',
        },
      ]);
    }
    if (path.startsWith('/admin/')) {
      if (!admin) {
        return json({'detail': 'Not authorized for admin routes'}, 403);
      }
      if (failDashboard) return json({'detail': 'Unavailable'}, 503);
      if (path == '/admin/stats') {
        return json({
          'total_users': total,
          'active_users': total - inactiveCount,
          'inactive_users': inactiveCount,
        });
      }
      if (request.method == 'GET') {
        return json({
          'eligible_users': eligible,
          'cutoff_at': '2026-07-17T12:00:00Z',
        });
      }
      if (failCleanup) return json({'detail': 'Unavailable'}, 503);
      final deleted = eligible;
      total -= deleted;
      inactiveCount -= deleted;
      eligible = 0;
      return json({'deleted_users': deleted});
    }
    throw StateError('Unexpected request: ${request.method} $path');
  }

  List<http.Request> get deletes =>
      requests.where((r) => r.method == 'DELETE').toList();
}

final _previewKey = GlobalKey();

Future<void> showApp(
  WidgetTester tester,
  TestBackend backend, {
  double width = 1280,
}) async {
  tester.view.physicalSize = Size(width, width < 600 ? 900 : 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _previewKey,
      child: MainApp(apiClient: ApiClient(client: MockClient(backend.handle))),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'test@example.com');
  await tester.enterText(find.byType(TextFormField).at(1), 'correct-password');
  await tester.ensureVisible(find.text('Sign in'));
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open account menu'));
  await tester.pumpAndSettle();
}

// Optional screenshots live in ignored build data, not source control. Enable
// with --dart-define=CAPTURE_UI=true to review actual Flutter-rendered layouts.
Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  await tester.runAsync(() async {
    final boundary =
        _previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.dart_tool/ui-previews')
      ..createSync(recursive: true);
    File(
      '${directory.path}/$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    // Flutter ships Roboto with its test runner. Loading it avoids Ahem's block
    // glyphs in optional previews and makes layout checks closer to the app.
    final configFile = File('.dart_tool/package_config.json');
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final flutterPackage = (config['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((package) => package['name'] == 'flutter');
    final flutterRoot = Directory.fromUri(
      configFile.absolute.uri.resolve(flutterPackage['rootUri'] as String),
    ).parent.parent;
    final fonts = '${flutterRoot.path}/bin/cache/artifacts/material_fonts';
    final loader = FontLoader('Roboto');
    for (final name in [
      'roboto-regular.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
    ]) {
      final file = File('$fonts/$name');
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('$fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
  });

  testWidgets(
    'regular users get training, email in drawer, and drawer logout',
    (tester) async {
      final backend = TestBackend();
      await showApp(tester, backend);
      await capture(tester, 'login-desktop');
      await signIn(tester);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(AdminPage), findsNothing);
      expect(
        backend.requests.where((r) => r.url.path.startsWith('/admin/')),
        isEmpty,
      );

      await tester.enterText(find.byType(TextFormField).first, 'Bench');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bench press').last);
      await tester.pumpAndSettle();
      await capture(tester, 'training-desktop');
      // Percentage rows are ordered from highest/red to lowest/blue.
      expect(
        tester.getTopLeft(find.text('90%')).dy,
        lessThan(tester.getTopLeft(find.text('50%')).dy),
      );
      await openMenu(tester);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('Deactivate account'), findsOneWidget);
      await capture(tester, 'account-drawer');
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    },
  );

  testWidgets(
    'deactivation validates password, preserves failed sessions, then signs out',
    (tester) async {
      final backend = TestBackend();
      await showApp(tester, backend);
      await signIn(tester);
      await openMenu(tester);
      await tester.tap(find.text('Deactivate account'));
      await tester.pumpAndSettle();
      await capture(tester, 'deactivation-dialog');
      expect(backend.deletes, isEmpty);
      final dialog = find.byType(AlertDialog);
      final confirm = find.descendant(
        of: dialog,
        matching: find.widgetWithText(FilledButton, 'Deactivate account'),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Enter your current password.'), findsOneWidget);
      expect(backend.deletes, isEmpty);
      final password = find.descendant(
        of: dialog,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(password, 'wrong-password');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        find.text('Your password is incorrect. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(HomePage), findsOneWidget);
      expect(backend.inactive, isFalse);

      await tester.enterText(password, 'correct-password');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(backend.inactive, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      final request = backend.deletes.last;
      expect(request.url.path, '/users/me/deactivate');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(jsonDecode(request.body), {
        'current_password': 'correct-password',
      });

      // The existing reactivation flow remains available after deactivation.
      await signIn(tester);
      expect(find.text('Reactivate account?'), findsOneWidget);
      await tester.tap(find.text('Yes, reactivate'));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    },
  );

  testWidgets('canceling deactivation never calls the API', (tester) async {
    final backend = TestBackend();
    await showApp(tester, backend);
    await signIn(tester);
    await openMenu(tester);
    await tester.tap(find.text('Deactivate account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.deletes, isEmpty);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('admin lands on stats and reviews cleanup before deleting', (
    tester,
  ) async {
    final backend = TestBackend(admin: true);
    await showApp(tester, backend);
    await signIn(tester);
    expect(find.byType(AdminPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(backend.requests.where((r) => r.url.path == '/exercises/'), isEmpty);
    for (final label in [
      'Total users',
      'Active users',
      'Inactive users',
      '2 eligible accounts',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await capture(tester, 'admin-desktop');
    await openMenu(tester);
    expect(find.text('admin@example.com'), findsOneWidget);
    expect(find.text('Deactivate account'), findsNothing);
    await tester.tap(find.text('Admin dashboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review inactive accounts'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 inactive accounts?'), findsOneWidget);
    await capture(tester, 'cleanup-confirmation');
    expect(backend.deletes, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.deletes, isEmpty);

    await tester.tap(find.text('Review inactive accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permanently delete'));
    await tester.pumpAndSettle();
    expect(backend.deletes.length, 1);
    expect(backend.deletes.single.url.path, '/admin/inactive-users/cleanup');
    expect(jsonDecode(backend.deletes.single.body), {
      'cutoff_at': '2026-07-17T12:00:00.000Z',
    });
    expect(find.text('0 eligible accounts'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('failed cleanup requires refreshing before another attempt', (
    tester,
  ) async {
    final backend = TestBackend(admin: true)..failCleanup = true;
    await showApp(tester, backend);
    await signIn(tester);
    await tester.tap(find.text('Review inactive accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permanently delete'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not complete cleanup. Refresh the dashboard before trying again.',
      ),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Review inactive accounts'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Refresh dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('2 eligible accounts'), findsOneWidget);
  });

  testWidgets(
    'dashboard load failures offer refresh instead of showing invented counts',
    (tester) async {
      final backend = TestBackend(admin: true)..failDashboard = true;
      await showApp(tester, backend);
      await signIn(tester);
      expect(
        find.text(
          'Could not load the dashboard. Please refresh and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Total users'), findsNothing);
      backend.failDashboard = false;
      await tester.tap(find.text('Refresh dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Total users'), findsOneWidget);
    },
  );

  testWidgets('direct admin page construction rejects an ordinary session', (
    tester,
  ) async {
    final backend = TestBackend();
    final client = ApiClient(client: MockClient(backend.handle));
    final auth = AuthState(AuthService(client));
    addTearDown(client.close);
    addTearDown(auth.dispose);
    await auth.login(email: 'test@example.com', password: 'correct-password');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AdminPage(authState: auth, adminService: AdminService(client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This page is available to administrators only.'),
      findsOneWidget,
    );
    expect(
      backend.requests.where((r) => r.url.path.startsWith('/admin/')),
      isEmpty,
    );
  });

  testWidgets('mobile login and registration fit and complete registration', (
    tester,
  ) async {
    final backend = TestBackend();
    await showApp(tester, backend, width: 360);
    expect(tester.takeException(), isNull);
    await capture(tester, 'login-mobile');
    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegistrationPage), findsOneWidget);
    await capture(tester, 'registration-mobile');
    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.com');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'correct-password',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'correct-password',
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('new@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final admin in [false, true]) {
    testWidgets(
      'mobile ${admin ? 'admin' : 'training'} page fits without overflow',
      (tester) async {
        final backend = TestBackend(admin: admin);
        await showApp(tester, backend, width: 360);
        await signIn(tester);
        if (!admin) {
          await tester.enterText(find.byType(TextFormField).first, 'Bench');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Bench press').last);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Latest saved 1RM'));
          await tester.pumpAndSettle();
        }
        await capture(tester, admin ? 'admin-mobile' : 'training-mobile');
        expect(tester.takeException(), isNull);
        if (admin) {
          await tester.ensureVisible(find.text('Review inactive accounts'));
          await tester.tap(find.text('Review inactive accounts'));
        } else {
          await openMenu(tester);
          await tester.tap(find.text('Deactivate account'));
        }
        await tester.pumpAndSettle();
        await capture(tester, admin ? 'cleanup-mobile' : 'deactivation-mobile');
        expect(tester.takeException(), isNull);
        expect(find.text('Cancel'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(backend.deletes, isEmpty);
      },
    );
  }
}
