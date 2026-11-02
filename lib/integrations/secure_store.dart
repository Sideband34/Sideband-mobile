/// Key-value persistence boundary for sensitive local state (signed-amount
/// high-water marks, receipts). Production implementations must sit on the
/// platform keychain/keystore (e.g. a flutter_secure_storage adapter), which
/// is NOT included yet. [InMemorySecureStore] is volatile and test-only.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

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
