import 'dart:convert';

import 'package:sideband_protocol/sideband_protocol.dart';

import '../domain/receipt.dart';
import 'secure_store.dart';

/// Persists session receipts. Newest first.
class HistoryRepository {
  HistoryRepository(this._store, {this.key = 'sideband.history.v1'});

  final KeyValueStore _store;
  final String key;

  Future<List<Receipt>> all() async {
    final raw = await _store.read(key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => _from(e as Map<String, dynamic>)).toList();
  }

  Future<void> upsert(Receipt r) async {
    final cur = await all();
    final i = cur.indexWhere((x) => x.sessionId == r.sessionId);
    if (i >= 0) {
      // A confirmed receipt is never downgraded by a later stale write.
      if (cur[i].status == SettlementStatus.confirmed &&
          r.status != SettlementStatus.confirmed) {
        return;
      }
      cur[i] = r;
    } else {
      cur.insert(0, r);
    }
    await _store.write(key, jsonEncode(cur.map(_to).toList()));
  }

  Future<Receipt?> byId(String sessionId) async {
    for (final r in await all()) {
      if (r.sessionId == sessionId) return r;
    }
    return null;
  }

  Map<String, Object?> _to(Receipt r) => {
        'sessionId': r.sessionId,
        'channelId': r.channelId,
        'provider': r.providerPublicKey,
        'units': r.units,
        'committed': r.committed.toString(),
        'baseline': r.baseline.toString(),
        'status': r.status.name,
        'closeReason': r.closeReason,
        'channelExpiresAt': r.channelExpiresAt,
      };

  Receipt _from(Map<String, dynamic> j) => Receipt(
        sessionId: j['sessionId'] as String,
        channelId: j['channelId'] as String,
        providerPublicKey: j['provider'] as String,
        units: j['units'] as int,
        committed: Amount.parse(j['committed'] as String),
        // Absent in records written before protocol v2: fresh channel.
        baseline: Amount.parse((j['baseline'] as String?) ?? '0'),
        status: SettlementStatus.values.byName(j['status'] as String),
        closeReason: j['closeReason'] as String,
        channelExpiresAt: j['channelExpiresAt'] as int,
      );
}
