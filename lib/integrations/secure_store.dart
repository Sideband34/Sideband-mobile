/// Durable key-value persistence (string values).
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// A [KeyValueStore] whose values are protected by the platform
/// keychain/keystore: signed-amount high-water marks, the signer seed, the
/// session journal (it holds bearer tokens). [FlutterSecureStore] is the
/// production implementation; [InMemorySecureStore] is volatile and test-only.
abstract interface class SecureStore implements KeyValueStore {}

class InMemorySecureStore implements SecureStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);

  /// Test hook: copy of the raw stored values (simulates "disk" for restarts).
  Map<String, String> snapshot() => Map.of(_m);
  void load(Map<String, String> data) => _m
    ..clear()
    ..addAll(data);
}
