import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_store.dart';

/// [SecureStore] on the platform keychain (iOS) / Keystore-backed encrypted
/// storage (Android) via `flutter_secure_storage`. Unit-tested against a
/// mocked platform channel; not yet verified on a physical device.
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                  accessibility:
                      KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}
