import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:max_reps_frontend/services/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'token survives storage-wrapper recreation and logout deletes only its own key',
    () async {
      // Exercise the actual storage adapter against the plugin's in-memory
      // platform implementation, without writing to this computer's real store.
      FlutterSecureStorage.setMockInitialValues({'unrelated_setting': 'keep'});
      final first = SecureTokenStorage();
      await first.write('test-access-token');
      final afterRestart = SecureTokenStorage();
      expect(await afterRestart.read(), 'test-access-token');
      await afterRestart.delete();
      expect(await first.read(), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'unrelated_setting'),
        'keep',
      );
    },
  );
}
