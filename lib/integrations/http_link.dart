import 'dart:convert';
import 'dart:io';

import 'package:sideband_protocol/sideband_protocol.dart';

import 'provider_link.dart';

/// [ProviderLink] over the sideband-gateway HTTP API v1 (local network). The
/// gateway issues a per-session bearer token with the offer; plain HTTP is for
/// local demos only (TLS is not set up).
class HttpProviderLink implements ResumableLink {
  HttpProviderLink(this.baseUri, {HttpClient? client})
      : _http = client ?? HttpClient();

  final Uri baseUri;
  final HttpClient _http;
  String? _session;
  String? _token;

  Future<(int, Map<String, dynamic>, HttpHeaders)> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final req = await _http.openUrl(method, baseUri.resolve(path));
    req.headers.contentType = ContentType.json;
    if (_token != null) req.headers.set('authorization', 'Bearer $_token');
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    final json = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    return (res.statusCode, json, res.headers);
  }

  Never _fail(int status, Map<String, dynamic> j) {
    final e = (j['error'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (status == 402 && e['code'] == 'payment_required') {
      throw PaymentRequired(
        required: Amount.parse(e['requiredCumulative'] as String),
        current: Amount.parse(e['currentCumulative'] as String),
      );
    }
    throw ProviderRejected(
      (e['code'] as String?) ?? 'http_$status',
      (e['message'] as String?) ?? 'HTTP $status',
      details: Map.of(e)..removeWhere((k, _) => k == 'code' || k == 'message'),
    );
  }

  @override
  Map<String, String> get resumeState => {
        if (_session != null) 'session': _session!,
        if (_token != null) 'token': _token!,
      };

  /// Re-binds to a journaled session and checks it is still active.
  @override
  Future<void> reattach(Map<String, String> state) async {
    final session = state['session'];
    if (session == null) {
      throw ProviderRejected('not_resumable', 'No journaled session');
    }
    _session = session;
    _token = state['token'];
    final (status, json, _) = await _send('GET', '/v1/sessions/$session/usage');
    if (status != 200) _fail(status, json);
    if (json['phase'] != 'active') {
      throw ProviderRejected('session_closed', 'Session is ${json['phase']}');
    }
  }

  @override
  Future<ServiceOffer> requestOffer() async {
    final (status, json, headers) = await _send(
      'POST',
      '/v1/sessions/offer',
      body: {'schemaVersion': 1},
    );
    if (status != 201) {
      _fail(status, json);
    }
    _token = headers.value('x-sideband-session-token');
    final offer = Frame.decode(jsonEncode(json));
    if (offer is! ServiceOffer) {
      throw ProviderRejected('bad_frame', 'Expected service_offer');
    }
    _session = offer.session;
    return offer;
  }

  @override
  Future<void> accept(SessionAccept a) async {
    final (status, json, _) =
        await _send('POST', '/v1/sessions/accept', body: a.toJson());
    if (status != 200) {
      _fail(status, json);
    }
  }

  @override
  Future<void> sendVoucher(VoucherFrame v) async {
    final (status, json, _) = await _send(
        'POST', '/v1/sessions/$_session/vouchers',
        body: v.toJson());
    if (status != 200) {
      _fail(status, json);
    }
  }

  @override
  Future<ServeResult> serve(String text) async {
    final (status, json, _) = await _send(
        'POST', '/v1/sessions/$_session/serve',
        body: {'text': text});
    if (status != 200) {
      _fail(status, json);
    }
    return ServeResult(
      output: json['output'] as String,
      units: json['units'] as int,
      cumulativeUnits: json['cumulativeUnits'] as int,
    );
  }

  @override
  Future<void> close() async {
    if (_session == null) return;
    await _send('POST', '/v1/sessions/$_session/close');
  }

  /// Raw call for tests/admin tooling.
  Future<(int, Map<String, dynamic>)> raw(String method, String path,
      {Object? body, Map<String, String> headers = const {}}) async {
    final req = await _http.openUrl(method, baseUri.resolve(path));
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }
}
