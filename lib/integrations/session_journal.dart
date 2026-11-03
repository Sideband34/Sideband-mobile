import 'dart:convert';

import 'package:sideband_protocol/sideband_protocol.dart';

import 'secure_store.dart';

/// What the payer must remember about an in-flight session to resume it after
/// the app is killed: the agreed offer/accept, units seen, the link state and
/// any voucher that was signed (ledger already advanced) but not yet
/// acknowledged by the provider.
class JournalEntry {
  const JournalEntry({
    required this.offer,
    required this.accept,
    required this.acceptedAt,
    required this.units,
    this.linkState = const {},
    this.pendingVoucher,
  });

  final ServiceOffer offer;
  final SessionAccept accept;
  final int acceptedAt;
  final int units;
  final Map<String, String> linkState;
  final VoucherFrame? pendingVoucher;

  String get sessionId => offer.session;

  JournalEntry copyWith({
    int? units,
    VoucherFrame? pendingVoucher,
    bool clearPending = false,
  }) =>
      JournalEntry(
        offer: offer,
        accept: accept,
        acceptedAt: acceptedAt,
        units: units ?? this.units,
        linkState: linkState,
        pendingVoucher:
            clearPending ? null : (pendingVoucher ?? this.pendingVoucher),
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'offer': offer.encode(),
        'accept': accept.encode(),
        'acceptedAt': acceptedAt,
        'units': units,
        'link': linkState,
        if (pendingVoucher != null) 'pending': pendingVoucher!.encode(),
      };

  static JournalEntry fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1) throw const FormatException('Unknown journal version');
    final offer = Frame.decode(j['offer'] as String);
    final accept = Frame.decode(j['accept'] as String);
    final pending = j['pending'] == null
        ? null
        : Frame.decode(j['pending'] as String) as VoucherFrame;
    if (offer is! ServiceOffer || accept is! SessionAccept) {
      throw const FormatException('Corrupt session journal');
    }
    return JournalEntry(
      offer: offer,
      accept: accept,
      acceptedAt: j['acceptedAt'] as int,
      units: j['units'] as int,
      linkState: (j['link'] as Map).cast<String, String>(),
      pendingVoucher: pending,
    );
  }
}

/// Single-slot journal (one active session at a time, like the provider's
/// one-session-per-channel rule) persisted through a [SecureStore]: the link
/// state can contain a bearer token.
class SessionJournal {
  SessionJournal(this._store, {this.key = 'sideband.session_journal.v1'});

  final SecureStore _store;
  final String key;

  Future<JournalEntry?> load() async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      return JournalEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Unreadable journal: drop it rather than resume on guesswork. The
      // signed ledger (separate key) still prevents re-signing lower amounts.
      await clear();
      return null;
    }
  }

  Future<void> save(JournalEntry e) =>
      _store.write(key, jsonEncode(e.toJson()));

  Future<void> clear() => _store.delete(key);
}
