import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

/// کلاینتِ HTTP برای سرویسِ Core. توکن‌ها بین اجراها با `shared_preferences`
/// پایدار می‌مانند تا کاربر با هر بار بازکردنِ اپ مجبور به ورودِ دوباره نباشد.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = baseUrl ?? AppConfig.apiBaseUrl;

  static const _kAccessTokenKey = 'dilix.access_token';
  static const _kRefreshTokenKey = 'dilix.refresh_token';

  final http.Client _client;
  final String _base;
  String? _accessToken;
  String? _refreshToken;

  bool get isAuthenticated => _accessToken != null;
  void setAccessToken(String? token) => _accessToken = token;

  /// خواندنِ نشستِ پایدارشده هنگامِ راه‌اندازیِ اپ (قبل از تصمیمِ ورود/خانه).
  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_kAccessTokenKey);
    _refreshToken = prefs.getString(_kRefreshTokenKey);
  }

  /// ذخیره‌ی توکن‌ها در حافظه + storage. با ورودِ موفق صدا زده می‌شود.
  Future<void> _persistTokens(TokenPair tokens) async {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken.isEmpty ? null : tokens.refreshToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessTokenKey, tokens.accessToken);
    if (_refreshToken != null) {
      await prefs.setString(_kRefreshTokenKey, _refreshToken!);
    } else {
      await prefs.remove(_kRefreshTokenKey);
    }
  }

  /// پاک‌سازیِ نشست (خروج). هم حافظه و هم storage را خالی می‌کند.
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessTokenKey);
    await prefs.remove(_kRefreshTokenKey);
  }

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
    await _persistTokens(tokens);
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
    await _persistTokens(tokens);
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
    await _persistTokens(tokens);
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
  Future<List<Post>> feed({int limit = 30, String? postType}) async {
    final q = postType == null ? '' : '&post_type=$postType';
    final list = await _get('/v1/social/feed?limit=$limit$q') as List;
    return list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// فیدِ ریلز: فقط پست‌های `post_type=reel` از همان endpoint فید.
  Future<List<Post>> reelsFeed({int limit = 30}) =>
      feed(limit: limit, postType: 'reel');

  /// ثبتِ واکنش روی یک پست؛ پستِ به‌روزشده را برمی‌گرداند.
  Future<Post> reactToPost(String postId, {String reaction = 'like'}) async {
    final j = await _post('/v1/social/posts/$postId/reactions', {'reaction': reaction});
    return Post.fromJson(j as Map<String, dynamic>);
  }

  /// ثبتِ نظر روی یک پست.
  Future<void> commentOnPost(String postId, String content) =>
      _post('/v1/social/posts/$postId/comments', {'content': content});

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

  // ─────────────── Marketplace ───────────────
  /// فهرست/جستجویِ آگهی‌های خدمت.
  Future<List<Listing>> marketplaceListings({String? keyword}) async {
    final q = (keyword == null || keyword.isEmpty)
        ? ''
        : '?keyword=${Uri.encodeQueryComponent(keyword)}';
    final list = await _get('/v1/marketplace/listings$q') as List;
    return list.map((e) => Listing.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ثبتِ آگهیِ خدمتِ جدید.
  Future<Listing> createListing({
    required String title,
    required String description,
    required String category,
    required int basePriceMinor,
    String currency = 'IRR',
    int deliveryDays = 7,
  }) async {
    final j = await _post('/v1/marketplace/listings', {
      'title': title,
      'description': description,
      'category': category,
      'base_price_minor': basePriceMinor,
      'currency': currency,
      'delivery_days': deliveryDays,
    });
    return Listing.fromJson(j as Map<String, dynamic>);
  }

  /// ثبتِ سفارش روی یک آگهی (escrow سمتِ سرور ساخته می‌شود).
  Future<MarketOrder> placeOrder(
    String listingId, {
    required int agreedPriceMinor,
    required String currency,
    String? requirements,
  }) async {
    final j = await _post('/v1/marketplace/orders', {
      'listing_id': listingId,
      'agreed_price_minor': agreedPriceMinor,
      'currency': currency,
      if (requirements != null) 'requirements': requirements,
    });
    return MarketOrder.fromJson(j as Map<String, dynamic>);
  }

  /// سفارش‌هایی که کاربر خریدار یا فروشندهٔ آن‌هاست.
  Future<List<MarketOrder>> marketplaceOrders() async {
    final list = await _get('/v1/marketplace/orders') as List;
    return list.map((e) => MarketOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// اکشن‌های چرخهٔ سفارش: accept/deliver/complete.
  Future<MarketOrder> orderAction(String orderId, String action) async {
    final j = await _post('/v1/marketplace/orders/$orderId/$action', null);
    return MarketOrder.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── Growth ───────────────
  Future<ReferralLink> referralLink() async =>
      ReferralLink.fromJson(await _get('/v1/growth/referrals/link') as Map<String, dynamic>);

  // ─────────────── Notifications ───────────────
  Future<List<NotificationItem>> notifications({
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    final list = await _get('/v1/notifications?unread_only=$unreadOnly&limit=$limit') as List;
    return list.map((e) => NotificationItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> markNotificationRead(String id) =>
      _post('/v1/notifications/$id/read', null);

  // ─────────────── Gamification (کیفِ پاداش) ───────────────
  /// موجودیِ امتیازِ پاداش (سکه‌ی دیلیکس).
  Future<int> rewardPoints() async {
    final j = await _get('/v1/gamification/points') as Map<String, dynamic>;
    return (j['balance'] as num).toInt();
  }

  // ─────────────── Messaging ───────────────
  /// فهرستِ گفتگوهایِ کاربرِ فعلی (مرتب بر اساسِ جدیدترین فعالیت).
  Future<List<ChatRoom>> listRooms({int limit = 100}) async {
    final list = await _get('/v1/messaging/rooms?limit=$limit') as List;
    return list.map((e) => ChatRoom.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ساختِ (یا بازکردنِ) گفتگویِ مستقیم با یک کاربر به کمکِ Earth ID او.
  Future<ChatRoom> createDirectRoom(String peerEarthId, {String? title}) async {
    final j = await _post('/v1/messaging/rooms', {
      'room_type': 'direct',
      if (title != null) 'title': title,
      'member_ids': [peerEarthId],
    });
    return ChatRoom.fromJson(j as Map<String, dynamic>);
  }

  /// پیام‌هایِ یک اتاق (جدیدترین در انتها؛ مرتب‌سازی در UI انجام می‌شود).
  Future<List<ChatMessage>> roomMessages(String roomId, {int limit = 50}) async {
    final list = await _get('/v1/messaging/rooms/$roomId/messages?limit=$limit') as List;
    return list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ارسالِ پیامِ متنی به یک اتاق.
  Future<ChatMessage> sendMessage(String roomId, String content) async {
    final j = await _post('/v1/messaging/rooms/$roomId/messages', {
      'content': content,
      'msg_type': 'text',
    });
    return ChatMessage.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── AI ───────────────
  /// ساختِ مکالمهٔ جدید با agent (پیش‌فرض personal) و دریافتِ شناسهٔ واقعی.
  Future<AiConversation> createAiConversation({
    String agentType = 'personal',
    String? title,
  }) async {
    final j = await _post('/v1/ai/conversations', {
      'agent_type': agentType,
      if (title != null) 'title': title,
    });
    return AiConversation.fromJson(j as Map<String, dynamic>);
  }

  /// مکالمه‌های کاربرِ فعلی، جدیدترین اول.
  Future<List<AiConversation>> aiConversations() async {
    final list = await _get('/v1/ai/conversations') as List;
    return list
        .map((e) => AiConversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// تاریخچهٔ پیام‌های یک مکالمه (قدیمی → جدید).
  Future<List<AiMessage>> aiHistory(String conversationId, {int limit = 50}) async {
    final list =
        await _get('/v1/ai/conversations/$conversationId/history?limit=$limit') as List;
    return list.map((e) => AiMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ارسالِ پیام؛ پاسخِ assistant را برمی‌گرداند.
  Future<AiMessage> aiChat(String conversationId, String message) async {
    final j = await _post(
      '/v1/ai/conversations/$conversationId/chat',
      {'message': message},
    );
    return AiMessage.fromJson(j as Map<String, dynamic>);
  }
}
