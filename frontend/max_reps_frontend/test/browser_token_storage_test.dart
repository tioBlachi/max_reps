@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:max_reps_frontend/services/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Flutter's browser unit-test runner does not register app plugins. A normal
  // `flutter run` or web build generates this registration automatically.
  FlutterSecureStorageWeb.registerWith(webPluginRegistrar);

  test(
    'real browser storage preserves the token across adapter recreation',
    () async {
      // This runs in an isolated Chrome test origin, using the real web plugin
      // and WebCrypto rather than the in-memory platform mock.
      final storage = SecureTokenStorage();
      addTearDown(storage.delete);
      expect(await storage.read(), isNull);
      await storage.write('browser-test-token');
      expect(await SecureTokenStorage().read(), 'browser-test-token');
      await storage.delete();
      expect(await SecureTokenStorage().read(), isNull);
    },
  );
}
