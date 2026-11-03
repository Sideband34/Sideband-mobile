import 'dart:convert';
import 'dart:io';

import 'secure_store.dart';

/// Durable [KeyValueStore] in one JSON file (receipt history and other
/// non-secret app data). Every write goes to a temp file, is flushed, and is
/// atomically renamed over the previous file, so a crash leaves either the old
/// or the new content, never a torn file. Writes are serialized.
class AtomicFileStore implements KeyValueStore {
  AtomicFileStore(Directory dir, {String name = 'sideband-data.json'})
      : _file = File('${dir.path}/$name');

  final File _file;
  Future<void> _tail = Future.value();
  Map<String, String>? _cache;

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    if (!await _file.exists()) return _cache = {};
    try {
      final j = jsonDecode(await _file.readAsString());
      return _cache = (j as Map).cast<String, String>();
    } on Object {
      // Keep the unreadable file for inspection; start empty rather than crash.
      await _file.rename('${_file.path}.corrupt');
      return _cache = {};
    }
  }

  Future<void> _mutate(void Function(Map<String, String>) f) {
    final run = _tail.then((_) async {
      final m = Map.of(await _load());
      f(m);
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      final raf = await tmp.open(mode: FileMode.write);
      await raf.writeString(jsonEncode(m));
      await raf.flush();
      await raf.close();
      await tmp.rename(_file.path);
      _cache = m;
    });
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<String?> read(String key) async {
    await _tail;
    return (await _load())[key];
  }

  @override
  Future<void> write(String key, String value) =>
      _mutate((m) => m[key] = value);

  @override
  Future<void> delete(String key) => _mutate((m) => m.remove(key));
}
