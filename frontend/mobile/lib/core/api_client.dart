import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import '../models/models.dart';

/// خطایِ API مطابقِ RFC 7807 (سند ۵ §۲).
class ApiException implements Exception {
  ApiException(this.status, this.detail, this.title);
  final int status;
  final String detail;
  final String title;
  @override
  String toString() => detail.isNotEmpty ? detail : title;
}

/// کلاینتِ HTTP برای سرویسِ Core. توکن در حافظه نگه داشته می‌شود؛
/// برای پایداری می‌توان آن را با secure storage جایگزین کرد.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _base;
  String? _accessToken;

  bool get isAuthenticated => _accessToken != null;
  void setAccessToken(String? token) => _accessToken = token;

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Never _raise(http.Response res) {
    String detail = res.reasonPhrase ?? 'خطا';
    String title = detail;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      detail = (body['detail'] ?? detail) as String;
      title = (body['title'] ?? title) as String;
    } catch (_) {}
    throw ApiException(res.statusCode, detail, title);
  }

  Future<dynamic> _get(String path) async {
    final res = await _client.get(Uri.parse('$_base$path'), headers: _headers());
    if (res.statusCode >= 400) _raise(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<dynamic> _post(String path, Object? body) async {
    final res = await _client.post(
      Uri.parse('$_base$path'),
      headers: _headers(json: true),
      body: jsonEncode(body ?? {}),
    );
    if (res.statusCode >= 400) _raise(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  // ─────────────── Auth ───────────────
  Future<TokenPair> login(String identifier, String password) async {
    final j = await _post('/v1/auth/login', {
      'identifier': identifier,
      'password': password,
    });
    final tokens = TokenPair.fromJson(j as Map<String, dynamic>);
    setAccessToken(tokens.accessToken);
    return tokens;
  }

  /// ورود/ثبت‌نام با Google/Microsoft/Apple/Facebook.
  /// [credential] برای google/microsoft/apple همان id_token و برای facebook
  /// همان access_token است.
  Future<TokenPair> oauthLogin(
    String provider,
    String credential, {
    String homeRegion = 'IR',
  }) async {
    final j = await _post('/v1/auth/oauth/$provider', {
      'credential': credential,
      'home_region': homeRegion,
    });
    final tokens =
        TokenPair.fromJson((j as Map<String, dynamic>)['tokens'] as Map<String, dynamic>);
    setAccessToken(tokens.accessToken);
    return tokens;
  }

  /// ارسالِ کدِ یک‌بارمصرف به موبایل (پیامک) یا Facebook Messenger.
  /// شناسه‌ی چالش برمی‌گرداند که در تأیید استفاده می‌شود.
  Future<String> otpRequest(
    String channel,
    String destination, {
    String purpose = 'login',
  }) async {
    final j = await _post('/v1/auth/otp/request', {
      'channel': channel,
      'destination': destination,
      'purpose': purpose,
    });
    return (j as Map<String, dynamic>)['challenge_id'] as String;
  }

  /// تأییدِ کد و ورود/ثبت‌نامِ خودکار.
  Future<TokenPair> otpVerify(String challengeId, String code) async {
    final j = await _post('/v1/auth/otp/verify', {
      'challenge_id': challengeId,
      'code': code,
    });
    final tokens =
        TokenPair.fromJson((j as Map<String, dynamic>)['tokens'] as Map<String, dynamic>);
    setAccessToken(tokens.accessToken);
    return tokens;
  }

  // ─────────────── Identity ───────────────
  Future<Identity> me() async =>
      Identity.fromJson(await _get('/v1/identity/me') as Map<String, dynamic>);

  Future<void> setVisibility({
    required bool discoverable,
    String audience = 'connections',
    String geoPrecision = 'region',
    List<String> visibleFields = const [],
  }) =>
      _post('/v1/identity/me/visibility', {
        'discoverable': discoverable,
        'audience': audience,
        'geo_precision': geoPrecision,
        'visible_fields': visibleFields,
      });

  // ─────────────── Social ───────────────
  Future<List<Post>> feed({int limit = 30}) async {
    final list = await _get('/v1/social/feed?limit=$limit') as List;
    return list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─────────────── Discovery ───────────────
  Future<List<NearbyPerson>> nearby({
    required String bbox,
    String? entityType,
    String? profession,
    int limit = 50,
  }) async {
    final params = <String, String>{'bbox': bbox, 'limit': '$limit'};
    if (entityType != null && entityType.isNotEmpty) params['entity_type'] = entityType;
    if (profession != null && profession.isNotEmpty) params['profession'] = profession;
    final query = Uri(queryParameters: params).query;
    final list = await _get('/v1/discovery/nearby?$query') as List;
    return list.map((e) => NearbyPerson.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> contactRequest(String earthId, String message) =>
      _post('/v1/discovery/$earthId/contact-request', {'message': message});

  // ─────────────── Freight ───────────────
  Future<List<CargoPost>> listCargo() async {
    final list = await _get('/v1/freight/cargo') as List;
    return list.map((e) => CargoPost.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─────────────── Growth ───────────────
  Future<ReferralLink> referralLink() async =>
      ReferralLink.fromJson(await _get('/v1/growth/referrals/link') as Map<String, dynamic>);

  // ─────────────── AI ───────────────
  Future<String> aiInvoke(String conversationId, String message) async {
    final j = await _post('/v1/ai/conversations/$conversationId/messages', {'message': message});
    return (j as Map<String, dynamic>)['reply'] as String;
  }
}
