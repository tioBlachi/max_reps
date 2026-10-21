import 'dart:async';
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
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/token_storage.dart';

class MemoryTokenStorage implements TokenStorage {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  MemoryTokenStorage([this.value]);
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Storage unavailable');
    return value;
  }

  @override
  Future<void> write(String token) async {
    if (failWrite) throw StateError('Storage unavailable');
    value = token;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

// In-memory HTTP server: real application services and auth/navigation run,
// but no test touches live users, credentials, or a production database.
class TestBackend {
  final bool admin;
  String email = 'test@example.com';
  String password = 'correct-password';
  bool inactive = false;
  bool profileUnavailable = false;
  bool rejectToken = false;
  int authVersion = 1;
  int eligible = 2;
  int totalUsers = 10;
  int inactiveUsers = 3;
  final requests = <http.Request>[];
  final List<Map<String, Object>> records;
  FutureOr<http.Response>? Function(http.Request)? override;
  TestBackend({this.admin = false, bool empty = false})
    : records = empty
          ? []
          : [
              for (var i = 0; i < 6; i++)
                {
                  'id': 'bench-$i',
                  'user_id': 'test-user',
                  'exercise_id': 1,
                  'reps': 5,
                  'weight': 135.0,
                  'unit': 'lb',
                  'one_rep_max_est': 157.5 - i,
                  'attempted_at':
                      '2026-10-${(21 - i).toString().padLeft(2, '0')}T17:30:00Z',
                },
              {
                'id': 'squat-1',
                'user_id': 'test-user',
                'exercise_id': 2,
                'reps': 5,
                'weight': 180.0,
                'unit': 'lb',
                'one_rep_max_est': 210.0,
                'attempted_at': '2026-10-20T12:00:00Z',
              },
            ];

  String get token => 'token-$authVersion';
  static const catalog = [
    {'id': 1, 'name': 'Bench press', 'category': 'strength'},
    {'id': 2, 'name': 'Squat', 'category': 'strength'},
    {'id': 3, 'name': 'Deadlift', 'category': 'strength'},
  ];
  http.Response json(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status);
  ApiClient client() => ApiClient(client: MockClient(handle));
  List<http.Request> calls(String path, [String? method]) => requests
      .where(
        (request) =>
            request.url.path == path &&
            (method == null || request.method == method),
      )
      .toList();

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final intercepted = override?.call(request);
    if (intercepted != null) return await intercepted;
    final path = request.url.path;
    if (path == '/users/token' || path == '/users/reactivate') {
      final form = Uri.splitQueryString(request.body);
      if (form['username'] != email || form['password'] != password) {
        return json({'detail': 'Could not validate credentials'}, 401);
      }
      if (path == '/users/token' && inactive) {
        return json({'detail': 'Inactive user'}, 403);
      }
      inactive = false;
      return json({'access_token': token, 'token_type': 'bearer'});
    }
    if (path == '/users' && request.method == 'POST') {
      return json({
        'id': 'new-user',
        'email': 'new@example.com',
        'is_admin': false,
      }, 201);
    }
    if (path == '/exercises/') return json(catalog);
    if (request.headers['Authorization'] != 'Bearer $token' || rejectToken) {
      return json({'detail': 'Could not validate credentials'}, 401);
    }
    if (path == '/users/me') {
      if (profileUnavailable) return json({'detail': 'Unavailable'}, 503);
      return json({'id': 'test-user', 'email': email, 'is_admin': admin});
    }
    if (path.startsWith('/users/me/')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['current_password'] != password) {
        return json({'detail': 'Current password is incorrect'}, 403);
      }
      if (path.endsWith('/email')) {
        if (body['email'] == 'taken@example.com') {
          return json({
            'detail': 'Another user is already registered with this email',
          }, 409);
        }
        email = body['email'] as String;
        return json({'id': 'test-user', 'email': email, 'is_admin': admin});
      }
      if (path.endsWith('/password')) password = body['new_password'] as String;
      if (path.endsWith('/deactivate')) inactive = true;
      authVersion++;
      return http.Response('', 204);
    }
    if (path == '/lift_record/exercises') {
      final sorted = [...records]
        ..sort(
          (a, b) => (b['attempted_at'] as String).compareTo(
            a['attempted_at'] as String,
          ),
        );
      final ids = sorted.map((record) => record['exercise_id']).toSet();
      return json([
        for (final id in ids)
          catalog.firstWhere((exercise) => exercise['id'] == id),
      ]);
    }
    if (path == '/lift_record/' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final weight = (body['weight'] as num).toDouble();
      final record = <String, Object>{
        'id': 'new-${records.length}',
        'user_id': 'test-user',
        'exercise_id': body['exercise_id'] as int,
        'reps': body['reps'] as int,
        'weight': weight,
        'unit': body['unit'] as String,
        'one_rep_max_est': weight * (1 + (body['reps'] as int) / 30),
        'attempted_at': '2026-10-22T12:00:00Z',
      };
      records.insert(0, record);
      return json(record, 201);
    }
    if (path == '/lift_record/') {
      final id = int.parse(request.url.queryParameters['exercise_id']!);
      final limit = int.parse(request.url.queryParameters['limit']!);
      final unit = request.url.queryParameters['unit'] ?? 'lb';
      final matches =
          records.where((record) => record['exercise_id'] == id).toList()..sort(
            (a, b) => (b['attempted_at'] as String).compareTo(
              a['attempted_at'] as String,
            ),
          );
      return json(
        matches.take(limit).map((record) {
          final factor = record['unit'] == unit
              ? 1.0
              : unit == 'kg'
              ? 1 / 2.2046226218
              : 2.2046226218;
          return {
            ...record,
            'unit': unit,
            'weight': (record['weight'] as num) * factor,
            'one_rep_max_est': (record['one_rep_max_est'] as num) * factor,
          };
        }).toList(),
      );
    }
    if (path.startsWith('/admin/')) {
      if (!admin) {
        return json({'detail': 'Not authorized for admin routes'}, 403);
      }
      if (path == '/admin/stats') {
        return json({
          'total_users': totalUsers,
          'active_users': totalUsers - inactiveUsers,
          'inactive_users': inactiveUsers,
        });
      }
      if (request.method == 'GET') {
        return json({
          'eligible_users': eligible,
          'cutoff_at': '2026-07-17T12:00:00Z',
        });
      }
      final deleted = eligible;
      totalUsers -= deleted;
      inactiveUsers -= deleted;
      eligible = 0;
      return json({'deleted_users': deleted});
    }
    throw StateError('Unexpected request: ${request.method} $path');
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
final previewKey = GlobalKey();

Future<void> showApp(
  WidgetTester tester,
  TestBackend backend,
  MemoryTokenStorage storage, {
  double width = 1280,
  String location = '/',
}) async {
  // Match the URL that the browser supplies on a direct visit or refresh.
  tester.platformDispatcher.defaultRouteNameTestValue = location;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  tester.view.physicalSize = Size(width, width < 600 ? 1000 : 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: previewKey,
      child: MainApp(
        key: UniqueKey(),
        apiClient: backend.client(),
        tokenStorage: storage,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(field('Email'), 'test@example.com');
  await tester.enterText(field('Password'), 'correct-password');
  await tester.ensureVisible(find.text('Sign in'));
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open account menu'));
  await tester.pumpAndSettle();
}

Future<void> openProfile(WidgetTester tester) async {
  await openMenu(tester);
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
}

Future<void> selectExercise(WidgetTester tester, String name) async {
  final search = find.byType(TextFormField).first;
  await tester.ensureVisible(search);
  await tester.enterText(search, name);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> loadPreviewFonts() async {
  final configFile = File('.dart_tool/package_config.json');
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final package = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .firstWhere((package) => package['name'] == 'flutter');
  final sdk = Directory.fromUri(
    configFile.absolute.uri.resolve(package['rootUri'] as String),
  ).parent.parent;
  final fonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final name in [
    'roboto-regular.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    roboto.addFont(
      Future.value(
        ByteData.sublistView(File('$fonts/$name').readAsBytesSync()),
      ),
    );
  }
  await roboto.load();
  final iconFile = [
    File('$fonts/MaterialIcons-Regular.otf'),
    File('$fonts/materialicons-regular.otf'),
  ].firstWhere((file) => file.existsSync());
  await (FontLoader('MaterialIcons')..addFont(
        Future.value(ByteData.sublistView(iconFile.readAsBytesSync())),
      ))
      .load();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  await tester.runAsync(() async {
    final boundary =
        previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('.dart_tool/ui-previews').createSync(recursive: true);
    File(
      '.dart_tool/ui-previews/redesign-$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
