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

/// کلاینتِ HTTP برای سرویسِ dilix-api (همان backendِ وب؛ مسیرها با `/api/v1`).
/// توکن‌ها بین اجراها با `shared_preferences` پایدار می‌مانند تا کاربر با هر بار
/// بازکردنِ اپ مجبور به ورودِ دوباره نباشد.
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

  /// توکنِ دسترسیِ جاری (برای اتصالِ WebSocket تماس).
  String? get accessToken => _accessToken;

  /// آدرسِ پایهٔ سرویسِ Core (برای ساختِ URLِ WebSocket).
  String get baseUrl => _base;

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

  /// POST با بدنهٔ `application/x-www-form-urlencoded` (کتابخانهٔ http وقتی
  /// body یک `Map<String,String>` باشد خودکار این نوع را تنظیم می‌کند).
  Future<dynamic> _postForm(String path, Map<String, String> fields) async {
    final res = await _client.post(
      Uri.parse('$_base$path'),
      headers: _headers(),
      body: fields,
    );
    if (res.statusCode >= 400) _raise(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  // ─────────────── Auth ───────────────
  Future<TokenPair> login(String identifier, String password) async {
    final j = await _post('/api/v1/auth/login', {
      'identifier': identifier,
      'password': password,
    });
    final tokens = TokenPair.fromJson(j as Map<String, dynamic>);
    await _persistTokens(tokens);
    return tokens;
  }

  /// ثبت‌نامِ کاربرِ جدید. [identifier] همان ایمیل یا شمارهٔ موبایل است و
  /// در موفقیت توکن‌ها ذخیره شده و کاربر واردِ حساب می‌شود.
  Future<TokenPair> register({
    required String identifier,
    required String fullName,
    required String password,
  }) async {
    final j = await _post('/api/v1/auth/register', {
      'identifier': identifier,
      'full_name': fullName,
      'password': password,
    });
    final tokens = TokenPair.fromJson(j as Map<String, dynamic>);
    await _persistTokens(tokens);
    return tokens;
  }

  /// ورود/ثبت‌نام با Google/Microsoft/Apple/Facebook.
  /// [credential] برای google/microsoft/apple همان id_token و برای facebook
  /// همان access_token است.
  Future<TokenPair> oauthLogin(String provider, String credential) async {
    final j = await _post('/api/v1/auth/oauth/$provider', {
      'credential': credential,
    });
    final tokens = TokenPair.fromJson(j as Map<String, dynamic>);
    await _persistTokens(tokens);
    return tokens;
  }

  /// ارسالِ کدِ یک‌بارمصرف به موبایل (پیامک). [destination] شمارهٔ موبایل است؛
  /// همان شماره برای مرحلهٔ تأیید برگردانده می‌شود.
  Future<String> otpRequest(
    String channel,
    String destination, {
    String purpose = 'login',
  }) async {
    await _post('/api/v1/auth/otp/send', {
      'phone': destination,
      'purpose': purpose,
    });
    return destination;
  }

  /// تأییدِ کد و ورود/ثبت‌نامِ خودکار. [phone] همان مقصدِ ارسالِ کد است.
  Future<TokenPair> otpVerify(String phone, String code) async {
    final j = await _post('/api/v1/auth/otp/verify', {
      'phone': phone,
      'otp': code,
    });
    final tokens = TokenPair.fromJson(j as Map<String, dynamic>);
    await _persistTokens(tokens);
    return tokens;
  }

  // ─────────────── Identity ───────────────
  Future<Identity> me() async =>
      Identity.fromJson(await _get('/api/v1/auth/me') as Map<String, dynamic>);

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

  // ─────────────── Social (پست‌ها) ───────────────
  /// فیدِ پست‌ها. dilix-api پاسخِ `{items:[PostOut], next_cursor}` می‌دهد.
  Future<List<Post>> feed({int limit = 30, String? postType}) async {
    final j = await _get('/api/v1/posts/feed') as Map<String, dynamic>;
    final list = (j['items'] ?? const []) as List;
    return list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// فیدِ ریلز؛ dilix-api endpointِ جدا دارد (`ReelOut` هم‌شکلِ PostOut است).
  Future<List<Post>> reelsFeed({int limit = 30}) async {
    final j = await _get('/api/v1/reels/feed') as Map<String, dynamic>;
    final list = (j['items'] ?? const []) as List;
    return list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// toggleِ لایکِ یک پست؛ شمارِ جدیدِ لایک را برمی‌گرداند.
  Future<int> likePost(String postId) async {
    final j = await _post('/api/v1/posts/$postId/like', null);
    return ((j as Map)['like_count'] as num?)?.toInt() ?? 0;
  }

  /// ثبتِ نظر روی یک پست (بدنه به‌صورتِ form با کلیدِ `body`).
  Future<void> commentOnPost(String postId, String content) =>
      _postForm('/api/v1/posts/$postId/comments', {'body': content});

  /// ساختِ پستِ جدید با آپلودِ فایلِ رسانه از گوشی (multipart).
  Future<Post> createPost({
    required String filePath,
    String? caption,
    double? lat,
    double? lng,
    String? placeName,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/api/v1/posts'));
    req.headers.addAll(_headers());
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    if (caption != null && caption.isNotEmpty) req.fields['caption'] = caption;
    if (lat != null) req.fields['lat'] = '$lat';
    if (lng != null) req.fields['lng'] = '$lng';
    if (placeName != null && placeName.isNotEmpty) req.fields['place_name'] = placeName;
    final res = await http.Response.fromStream(await _client.send(req));
    if (res.statusCode >= 400) _raise(res);
    return Post.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ─────────────── Discovery (کره) ───────────────
  /// کاربرانِ روی کره؛ dilix-api پاسخِ `{count, users:[...]}` می‌دهد.
  /// [type] یکی از `driver|person|business`، [country] کدِ ISO-3.
  Future<List<NearbyPerson>> earthUsers({
    String? type,
    String? country,
    int limit = 200,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (country != null && country.isNotEmpty) params['country'] = country;
    final query = Uri(queryParameters: params).query;
    final j = await _get('/api/v1/earth/users?$query') as Map<String, dynamic>;
    final list = (j['users'] ?? const []) as List;
    return list.map((e) => NearbyPerson.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─────────────── Freight ───────────────
  Future<List<CargoPost>> listCargo() async {
    final list = await _get('/v1/freight/cargo') as List;
    return list.map((e) => CargoPost.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ثبتِ آگهیِ بارِ جدید (اسنپِ بار). وزن به گرم و بودجهٔ اختیاری به amount_minor.
  Future<CargoPost> createCargo({
    required String title,
    required String origin,
    required String destination,
    required int weightGrams,
    int? budgetMinor,
    String currency = 'IRR',
  }) async {
    final j = await _post('/v1/freight/cargo', {
      'title': title,
      'origin': origin,
      'destination': destination,
      'weight_grams': weightGrams,
      if (budgetMinor != null) 'budget_minor': budgetMinor,
      'currency': currency,
    });
    return CargoPost.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── Provider (پورتالِ خودسرویس) ───────────────
  /// ثبت‌نامِ ارائه‌دهنده (KYB). `providerType`: insurer/carrier/psp/telecom/third_party.
  Future<Provider> registerProvider({
    required String legalName,
    required String providerType,
    String country = 'IR',
  }) async {
    final j = await _post('/v1/providers/register', {
      'legal_name': legalName,
      'provider_type': providerType,
      'country': country,
    });
    return Provider.fromJson(j as Map<String, dynamic>);
  }

  /// فهرستِ APIهای ثبت‌شدهٔ ارائه‌دهنده.
  Future<List<ProviderApi>> providerApis(String providerId) async {
    final list = await _get('/v1/providers/$providerId/apis') as List;
    return list.map((e) => ProviderApi.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ثبتِ یک API/سرویسِ جدید برای ارائه‌دهنده.
  Future<ProviderApi> registerProviderApi(
    String providerId, {
    required String name,
    String? specUrl,
  }) async {
    final j = await _post('/v1/providers/$providerId/apis', {
      'name': name,
      if (specUrl != null && specUrl.isNotEmpty) 'spec_url': specUrl,
    });
    return ProviderApi.fromJson(j as Map<String, dynamic>);
  }

  /// تستِ دسترس‌پذیریِ sandbox روی یک API.
  Future<SandboxResult> providerSandboxTest(String providerId, String apiId) async {
    final j = await _post('/v1/providers/$providerId/apis/$apiId/sandbox-test', null);
    return SandboxResult.fromJson(j as Map<String, dynamic>);
  }

  /// ثبتِ webhook؛ `secret` فقط در همین پاسخ برمی‌گردد.
  Future<Webhook> registerProviderWebhook(
    String providerId, {
    required String url,
    List<String> eventTypes = const ['*'],
  }) async {
    final j = await _post('/v1/providers/$providerId/webhooks', {
      'url': url,
      'event_types': eventTypes,
    });
    return Webhook.fromJson(j as Map<String, dynamic>);
  }

  /// صدورِ کلیدِ sandbox/production؛ کلیدِ خام فقط در همین پاسخ برمی‌گردد.
  Future<Credential> issueProviderCredential(String providerId, String env) async {
    final j = await _post('/v1/providers/$providerId/credentials', {'env': env});
    return Credential.fromJson(j as Map<String, dynamic>);
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

  // ─────────────── Stories ───────────────
  /// فیدِ حلقه‌های داستان (هر نویسنده یک حلقه، مرتب: خودم/دیده‌نشده/جدیدتر).
  Future<List<StoryRing>> storiesFeed() async {
    final list = await _get('/v1/stories/feed') as List;
    return list.map((e) => StoryRing.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// داستان‌های فعالِ یک نویسنده (به‌ترتیبِ زمانی).
  Future<List<Story>> userStories(String earthId) async {
    final list = await _get('/v1/stories/user/$earthId') as List;
    return list.map((e) => Story.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ثبتِ بازدیدِ یک داستان (idempotent؛ بازدیدِ خودِ نویسنده شمرده نمی‌شود).
  Future<void> viewStory(String storyId) =>
      _post('/v1/stories/$storyId/view', null);

  /// ثبتِ داستانِ جدید با آدرسِ رسانه.
  Future<Story> createStory({
    required String mediaUrl,
    String mediaType = 'image',
    String? caption,
    String audience = 'public',
  }) async {
    final j = await _post('/v1/stories', {
      'media_url': mediaUrl,
      'media_type': mediaType,
      'audience': audience,
      if (caption != null) 'caption': caption,
    });
    return Story.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── Growth ───────────────
  Future<ReferralLink> referralLink() async =>
      ReferralLink.fromJson(await _get('/v1/growth/referrals/link') as Map<String, dynamic>);

  /// کیفِ پاداش: موجودی‌ها به‌تفکیکِ ارز + شمارِ پاداش‌های در انتظار.
  Future<RewardWallet> rewardWallet() async =>
      RewardWallet.fromJson(await _get('/v1/growth/rewards') as Map<String, dynamic>);

  /// وضعیتِ سهم از درآمد (پلن، سهمِ bps، واحدهای سرمایه‌گذاری).
  Future<RevenueShare> revenueShare() async =>
      RevenueShare.fromJson(await _get('/v1/growth/revenue-share') as Map<String, dynamic>);

  // ─────────────── Payments (escrow) ───────────────
  /// ساختِ سفارشِ پرداختِ امانی (Dilix فقط ارکستریت می‌کند؛ مدلِ escrow).
  Future<PaymentOrder> createEscrow({
    required String payeeEarthId,
    required int amountMinor,
    required String currency,
    String providerCode = 'sandbox',
  }) async {
    final j = await _post('/v1/payments/escrow', {
      'payee_earth_id': payeeEarthId,
      'amount_minor': amountMinor,
      'currency': currency,
      'provider_code': providerCode,
    });
    return PaymentOrder.fromJson(j as Map<String, dynamic>);
  }

  /// تسویهٔ سفارشِ امانی (held → captured).
  Future<PaymentOrder> capturePayment(String orderId) async {
    final j = await _post('/v1/payments/$orderId/capture', null);
    return PaymentOrder.fromJson(j as Map<String, dynamic>);
  }

  /// برگشتِ سفارشِ امانی (held → refunded).
  Future<PaymentOrder> refundPayment(String orderId) async {
    final j = await _post('/v1/payments/$orderId/refund', null);
    return PaymentOrder.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── Notifications ───────────────
  /// dilix-api پاسخِ `{unread, items:[...]}` می‌دهد؛ فقط آرایهٔ `items` استخراج می‌شود.
  Future<List<NotificationItem>> notifications({
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    final j = await _get('/api/v1/notifications') as Map<String, dynamic>;
    final list = (j['items'] ?? const []) as List;
    return list.map((e) => NotificationItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> markNotificationRead(String id) =>
      _post('/api/v1/notifications/$id/read', null);

  // ─────────────── Gamification (کیفِ پاداش) ───────────────
  /// موجودیِ امتیازِ پاداش (سکه‌ی دیلیکس).
  Future<int> rewardPoints() async {
    final j = await _get('/v1/gamification/points') as Map<String, dynamic>;
    return (j['balance'] as num).toInt();
  }

  /// نشان‌هایِ کسب‌شدهٔ کاربر.
  Future<List<Badge>> gamificationBadges() async {
    final list = await _get('/v1/gamification/badges') as List;
    return list.map((e) => Badge.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─────────────── Investment ───────────────
  /// آخرین NAVِ یک صندوق (به کوچک‌ترین واحدِ پول).
  Future<NavQuote> investmentNav(String fundCode) async {
    final j = await _get('/v1/investment/nav?fund_code=${Uri.encodeQueryComponent(fundCode)}');
    return NavQuote.fromJson(j as Map<String, dynamic>);
  }

  /// موقعیت‌های سرمایه‌گذاریِ کاربر.
  Future<List<InvestmentPosition>> investmentPositions() async {
    final list = await _get('/v1/investment/positions') as List;
    return list.map((e) => InvestmentPosition.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// خریدِ واحدِ صندوق؛ موقعیتِ به‌روزشده را برمی‌گرداند.
  Future<InvestmentPosition> buyFund({
    required String fundCode,
    required int amountMinor,
    String currency = 'IRR',
    String providerCode = 'sandbox_fund',
  }) async {
    final j = await _post('/v1/investment/buy', {
      'fund_code': fundCode,
      'amount_minor': amountMinor,
      'currency': currency,
      'provider_code': providerCode,
    });
    return InvestmentPosition.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── Membership ───────────────
  /// عضویتِ جاریِ کاربر.
  Future<Membership> membership() async =>
      Membership.fromJson(await _get('/v1/membership') as Map<String, dynamic>);

  /// ارتقا/تمدیدِ پلنِ عضویت.
  Future<Membership> upgradeMembership(String plan, {int months = 1}) async {
    final j = await _post('/v1/membership/upgrade', {'plan': plan, 'months': months});
    return Membership.fromJson(j as Map<String, dynamic>);
  }

  /// لغوِ عضویت (بازگشت به پلنِ رایگان).
  Future<Membership> cancelMembership() async {
    final j = await _post('/v1/membership/cancel', null);
    return Membership.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── Reputation ───────────────
  /// امتیازهایِ اعتبارِ یک کاربر به‌تفکیکِ حوزه.
  Future<List<ReputationScore>> reputationScores(String earthId) async {
    final list = await _get('/v1/reputation/scores/$earthId') as List;
    return list.map((e) => ReputationScore.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// نظرهایِ دریافتیِ یک کاربر.
  Future<List<Review>> reputationReviews(String earthId) async {
    final list = await _get('/v1/reputation/reviews/$earthId') as List;
    return list.map((e) => Review.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─────────────── Insurance ───────────────
  /// استعلامِ بیمه (ساختِ بیمه‌نامهٔ در وضعیتِ استعلام).
  Future<InsurancePolicy> createInsuranceQuote({
    required String productCode,
    required int coverageMinor,
    String currency = 'IRR',
    String providerCode = 'sandbox',
    Map<String, dynamic> attributes = const {},
  }) async {
    final j = await _post('/v1/insurance/quotes', {
      'product_code': productCode,
      'coverage_minor': coverageMinor,
      'currency': currency,
      'provider_code': providerCode,
      'attributes': attributes,
    });
    return InsurancePolicy.fromJson(j as Map<String, dynamic>);
  }

  /// صدورِ نهاییِ بیمه‌نامه.
  Future<InsurancePolicy> issuePolicy(String policyId) async {
    final j = await _post('/v1/insurance/$policyId/issue', null);
    return InsurancePolicy.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── Telecom ───────────────
  /// شارژِ خطِ موبایل / بستهٔ اینترنت.
  Future<TopUp> telecomTopUp({
    required String msisdn,
    required String productCode,
    required int amountMinor,
    String currency = 'IRR',
    String providerCode = 'sandbox',
  }) async {
    final j = await _post('/v1/telecom/top-up', {
      'msisdn': msisdn,
      'product_code': productCode,
      'amount_minor': amountMinor,
      'currency': currency,
      'provider_code': providerCode,
    });
    return TopUp.fromJson(j as Map<String, dynamic>);
  }

  /// فعال‌سازیِ eSIM.
  Future<Esim> activateEsim({
    required String iccid,
    required String countryCode,
    String providerCode = 'sandbox',
  }) async {
    final j = await _post('/v1/telecom/esim/activate', {
      'iccid': iccid,
      'country_code': countryCode,
      'provider_code': providerCode,
    });
    return Esim.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── Messages ───────────────
  /// فهرستِ گفتگوهایِ کاربرِ فعلی (مرتب بر اساسِ جدیدترین فعالیت).
  Future<List<ChatRoom>> listRooms({int limit = 100}) async {
    final list = await _get('/api/v1/messages/rooms') as List;
    return list.map((e) => ChatRoom.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ساختِ (یا بازکردنِ) گفتگویِ مستقیم با یک کاربر به کمکِ Earth ID او.
  Future<ChatRoom> createDirectRoom(String peerEarthId, {String? title}) async {
    final j = await _post('/api/v1/messages/rooms', {
      'earth_id': peerEarthId,
    });
    return ChatRoom.fromJson(j as Map<String, dynamic>);
  }

  /// پیام‌هایِ یک اتاق (جدیدترین در انتها؛ مرتب‌سازی در UI انجام می‌شود).
  Future<List<ChatMessage>> roomMessages(String roomId, {int limit = 50}) async {
    final list = await _get('/api/v1/messages/rooms/$roomId/messages?limit=$limit') as List;
    return list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ارسالِ پیامِ متنی به یک اتاق.
  Future<ChatMessage> sendMessage(String roomId, String content) async {
    final j = await _post('/api/v1/messages/rooms/$roomId/messages', {
      'content': content,
    });
    return ChatMessage.fromJson(j as Map<String, dynamic>);
  }

  // ─────────────── AI ───────────────
  /// تاریخچهٔ گفتگو با دستیار (dilix-api مفهومِ conversation ندارد؛ یک نخِ واحد).
  Future<List<AiMessage>> aiHistory() async {
    final list = await _get('/api/v1/ai/history') as List;
    return list.map((e) => AiMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ارسالِ پیام به دستیار؛ پاسخِ assistant را برمی‌گرداند (`ChatResponse`).
  Future<AiMessage> aiChat(String message) async {
    final j = await _post('/api/v1/ai/chat', {'message': message});
    return AiMessage.fromJson(j as Map<String, dynamic>);
  }
}
