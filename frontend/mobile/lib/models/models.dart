/// مدل‌هایِ دامنه — هم‌خوان با سند ۵ (مشخصاتِ API).

class TokenPair {
  TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.mfaRequired,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final bool mfaRequired;

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
        accessToken: j['access_token'] as String,
        refreshToken: (j['refresh_token'] ?? '') as String,
        tokenType: (j['token_type'] ?? 'bearer') as String,
        mfaRequired: (j['mfa_required'] ?? false) as bool,
      );
}

class Identity {
  Identity({
    required this.earthId,
    required this.entityType,
    required this.status,
    required this.kycLevel,
    required this.homeRegion,
    required this.displayName,
    this.role,
    this.username,
    this.bio,
    this.email,
    this.phone,
    this.avatarUrl,
    this.kycStatus = 'pending',
    this.nationalIdSet = false,
    this.privacyOnMap = false,
    this.trustScore = 0,
    this.avgRating = 0,
    this.totalTrips = 0,
  });

  final String earthId;
  final String entityType;
  final String status;
  final int kycLevel;
  final String homeRegion;
  final String? displayName;
  final String? role;
  final String? username;
  final String? bio;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String kycStatus;
  final bool nationalIdSet;
  final bool privacyOnMap;
  final num trustScore;
  final num avgRating;
  final int totalTrips;

  factory Identity.fromJson(Map<String, dynamic> j) {
    // dilix-api پاسخِ تخت (UserResponse) می‌دهد؛ نامِ نمایشی در `full_name`.
    final profile = j['profile'] as Map<String, dynamic>?;
    return Identity(
      earthId: j['earth_id'] as String,
      // dilix-api نقش را در `role` می‌دهد (نه entity_type).
      entityType: (j['role'] ?? j['entity_type'] ?? 'user') as String,
      status: (j['status'] ?? 'active') as String,
      kycLevel: (j['kyc_level'] ?? 0) as int,
      homeRegion: (j['home_region'] ?? j['country_code'] ?? 'IR') as String,
      displayName: (j['full_name'] ?? profile?['display_name']) as String?,
      role: j['role'] as String?,
      username: j['username'] as String?,
      bio: j['bio'] as String?,
      email: j['email'] as String?,
      phone: j['phone'] as String?,
      avatarUrl: j['avatar_url'] as String?,
      kycStatus: (j['kyc_status'] ?? 'pending') as String,
      nationalIdSet: (j['national_id_set'] ?? false) as bool,
      privacyOnMap: (j['privacy_on_map'] ?? false) as bool,
      trustScore: (j['trust_score'] ?? 0) as num,
      avgRating: (j['avg_rating'] ?? 0) as num,
      totalTrips: (j['total_trips'] ?? 0) as int,
    );
  }
}

class Post {
  Post({
    required this.id,
    required this.authorEarthId,
    this.authorName,
    this.authorAvatar,
    required this.postType,
    required this.content,
    required this.media,
    required this.reactionCounts,
    required this.commentCount,
    this.likedByMe = false,
    this.savedByMe = false,
    this.isMine = false,
  });

  final String id;
  final String authorEarthId;
  final String? authorName;
  final String? authorAvatar;
  final String postType;
  final String? content;

  /// آرایه‌ی رسانه‌ها؛ هر آیتم آبجکتی با کلیدِ url/media_url (و اختیاری type).
  final List<Map<String, dynamic>> media;
  final Map<String, int> reactionCounts;
  final int commentCount;
  final bool likedByMe;
  final bool savedByMe;
  final bool isMine;

  /// اولین نشانیِ ویدیوی پست (برای ریلز). اگر ویدیویی نباشد null.
  String? get videoUrl {
    for (final m in media) {
      final url = (m['url'] ?? m['media_url']) as String?;
      final kind = (m['type'] ?? m['media_type'] ?? '') as String;
      if (url != null && kind.startsWith('video')) return url;
    }
    return null;
  }

  /// اولین نشانیِ تصویرِ پست (رسانهٔ غیرِویدیویی).
  String? get imageUrl {
    for (final m in media) {
      final url = (m['url'] ?? m['media_url']) as String?;
      final kind = (m['type'] ?? m['media_type'] ?? '') as String;
      if (url != null && !kind.startsWith('video')) return url;
    }
    return null;
  }

  /// کپیِ سبک با شمارِ نظرِ به‌روزشده (برای افزایشِ خوش‌بینانه پس از ثبتِ نظر).
  Post copyWithCommentCount(int count) => _copy(commentCount: count);

  /// کپی با وضعیتِ لایکِ به‌روزشده (پس از toggleِ لایک).
  Post copyWithLike({required bool liked, required int likeCount}) => _copy(
        likedByMe: liked,
        reactionCounts: {...reactionCounts, 'like': likeCount},
      );

  Post _copy({
    int? commentCount,
    bool? likedByMe,
    Map<String, int>? reactionCounts,
  }) =>
      Post(
        id: id,
        authorEarthId: authorEarthId,
        authorName: authorName,
        authorAvatar: authorAvatar,
        postType: postType,
        content: content,
        media: media,
        reactionCounts: reactionCounts ?? this.reactionCounts,
        commentCount: commentCount ?? this.commentCount,
        likedByMe: likedByMe ?? this.likedByMe,
        savedByMe: savedByMe,
        isMine: isMine,
      );

  /// سازگار با هر دو قرارداد: dilix-api (`PostOut`/`ReelOut`: تک `media_url`،
  /// `caption`، `like_count`) و شکلِ قدیمیِ Core (`media[]`, `content`).
  factory Post.fromJson(Map<String, dynamic> j) {
    final List<Map<String, dynamic>> media;
    if (j['media_url'] != null) {
      media = [
        {'url': j['media_url'], 'type': (j['media_type'] ?? 'image')},
      ];
    } else if (j['media'] is List) {
      media = (j['media'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } else {
      media = const [];
    }
    final Map<String, int> reactions;
    if (j['reaction_counts'] is Map) {
      reactions = (j['reaction_counts'] as Map)
          .map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } else {
      reactions = {'like': (j['like_count'] as num?)?.toInt() ?? 0};
    }
    return Post(
      id: j['id'] as String,
      authorEarthId: (j['author_earth_id'] ?? '') as String,
      authorName: j['author_name'] as String?,
      authorAvatar: j['author_avatar'] as String?,
      postType: (j['media_type'] ?? j['post_type'] ?? 'text') as String,
      content: (j['caption'] ?? j['content']) as String?,
      media: media,
      reactionCounts: reactions,
      commentCount: (j['comment_count'] ?? 0) as int,
      likedByMe: (j['liked_by_me'] ?? false) as bool,
      savedByMe: (j['saved_by_me'] ?? false) as bool,
      isMine: (j['is_mine'] ?? false) as bool,
    );
  }
}

class NearbyPerson {
  NearbyPerson({
    required this.earthId,
    required this.entityType,
    required this.displayName,
    required this.geoPrecision,
    required this.profession,
    required this.ageRange,
    required this.languages,
    required this.lat,
    required this.lon,
  });

  final String earthId;
  final String entityType;
  final String? displayName;
  final String geoPrecision;
  final String? profession;
  final String? ageRange;
  final List<String> languages;
  final double lat;
  final double lon;

  /// سازگار با dilix-api (`earth/users`: `name`/`role`/`city`/`lat`/`lng`) و
  /// شکلِ قدیمیِ Core (`display_name`/`entity_type`/`profession`/`lon`).
  factory NearbyPerson.fromJson(Map<String, dynamic> j) => NearbyPerson(
        earthId: j['earth_id'] as String,
        entityType: (j['entity_type'] ?? j['role'] ?? 'individual') as String,
        displayName: (j['display_name'] ?? j['name']) as String?,
        geoPrecision: (j['geo_precision'] ?? 'region') as String,
        // dilix-api موقعیت را تا سطحِ شهر می‌دهد؛ آن را به‌عنوان توضیح نشان می‌دهیم.
        profession: (j['profession'] ?? j['city']) as String?,
        ageRange: j['age_range'] as String?,
        languages: ((j['languages'] ?? const []) as List).whereType<String>().toList(),
        lat: (j['lat'] as num).toDouble(),
        lon: ((j['lon'] ?? j['lng']) as num).toDouble(),
      );
}

class CargoPost {
  CargoPost({
    required this.id,
    required this.title,
    required this.origin,
    required this.destination,
    required this.status,
    required this.weightGrams,
    this.budgetMinor,
    this.currency = 'IRR',
  });

  final String id;
  final String title;
  final String origin;
  final String destination;
  final String status;
  final int weightGrams;
  final int? budgetMinor;
  final String currency;

  /// سازگار با dilix-api (`CargoPostOut`: `cargo_type`/`weight_kg`/`price`) و
  /// شکلِ قدیمیِ Core (`title`/`weight_grams`/`budget_minor`).
  factory CargoPost.fromJson(Map<String, dynamic> j) => CargoPost(
        id: j['id'] as String,
        title: (j['title'] ?? j['cargo_type'] ?? j['description'] ?? 'بار') as String,
        origin: j['origin'] as String,
        destination: j['destination'] as String,
        status: (j['status'] ?? 'open') as String,
        weightGrams: (j['weight_grams'] as num?)?.toInt() ??
            (((j['weight_kg'] as num?) ?? 0) * 1000).round(),
        budgetMinor: (j['budget_minor'] as num?)?.toInt() ??
            (j['price'] as num?)?.toInt(),
        currency: (j['currency'] ?? 'IRR') as String,
      );
}

/// آگهیِ خدمتِ بازارگاه — منطبق با `ListingOut` بک‌اند.
class Listing {
  Listing({
    required this.id,
    required this.providerEarthId,
    required this.title,
    required this.description,
    required this.category,
    required this.basePriceMinor,
    required this.currency,
    required this.deliveryDays,
    required this.status,
  });

  final String id;
  final String providerEarthId;
  final String title;
  final String description;
  final String category;
  final int basePriceMinor;
  final String currency;
  final int deliveryDays;
  final String status;

  factory Listing.fromJson(Map<String, dynamic> j) => Listing(
        id: j['id'] as String,
        providerEarthId: j['provider_earth_id'] as String,
        title: j['title'] as String,
        description: (j['description'] ?? '') as String,
        category: (j['category'] ?? '') as String,
        basePriceMinor: (j['base_price_minor'] as num).toInt(),
        currency: (j['currency'] ?? 'IRR') as String,
        deliveryDays: (j['delivery_days'] ?? 0) as int,
        status: (j['status'] ?? 'active') as String,
      );
}

/// سفارشِ بازارگاه — منطبق با `OrderOut` بک‌اند.
class MarketOrder {
  MarketOrder({
    required this.id,
    required this.listingId,
    required this.buyerEarthId,
    required this.providerEarthId,
    required this.agreedPriceMinor,
    required this.currency,
    required this.status,
  });

  final String id;
  final String listingId;
  final String buyerEarthId;
  final String providerEarthId;
  final int agreedPriceMinor;
  final String currency;
  final String status;

  factory MarketOrder.fromJson(Map<String, dynamic> j) => MarketOrder(
        id: j['id'] as String,
        listingId: j['listing_id'] as String,
        buyerEarthId: j['buyer_earth_id'] as String,
        providerEarthId: j['provider_earth_id'] as String,
        agreedPriceMinor: (j['agreed_price_minor'] as num).toInt(),
        currency: (j['currency'] ?? 'IRR') as String,
        status: (j['status'] ?? 'pending') as String,
      );
}

class ReferralLink {
  ReferralLink({
    required this.code,
    required this.url,
    this.totalReferred = 0,
    this.totalNetwork = 0,
    this.totalRewardToman = 0,
  });
  final String code;
  final String url;
  final int totalReferred;
  final int totalNetwork;
  final int totalRewardToman;
  factory ReferralLink.fromJson(Map<String, dynamic> j) => ReferralLink(
        code: (j['code'] ?? '') as String,
        // dilix-api: `link`؛ Core: `url`.
        url: (j['url'] ?? j['link'] ?? '') as String,
        totalReferred: (j['total_referred'] ?? 0) as int,
        totalNetwork: (j['total_network'] ?? 0) as int,
        totalRewardToman: (j['total_reward_toman'] ?? 0) as int,
      );
}

/// وضعیتِ احرازِ هویت (KYC) — `GET /api/v1/auth/me/kyc`.
class KycStatus {
  KycStatus({required this.status, this.level = 0, this.message});
  final String status; // none | pending | approved | rejected
  final int level;
  final String? message;
  factory KycStatus.fromJson(Map<String, dynamic> j) => KycStatus(
        status: (j['status'] ?? 'none') as String,
        level: (j['level'] ?? 0) as int,
        message: j['message'] as String?,
      );
}

/// تنظیمِ مخاطبِ پیش‌فرضِ داستان — `GET/PUT /api/v1/stories/settings`.
class StorySettings {
  StorySettings({required this.defaultAudience, this.isSet = false});
  final String defaultAudience; // public|followers|colleagues|family|friends
  final bool isSet;
  factory StorySettings.fromJson(Map<String, dynamic> j) => StorySettings(
        defaultAudience: (j['default_audience'] ?? 'public') as String,
        isSet: (j['is_set'] ?? false) as bool,
      );
}

/// شبکهٔ بازاریابیِ چندسطحی — `GET /api/v1/referral/network`.
class ReferralNetwork {
  ReferralNetwork({
    required this.levels,
    required this.totalNetwork,
    required this.direct,
  });
  final List<ReferralLevel> levels;
  final int totalNetwork;
  final List<ReferralMember> direct;
  factory ReferralNetwork.fromJson(Map<String, dynamic> j) => ReferralNetwork(
        levels: ((j['levels'] ?? const []) as List)
            .map((e) => ReferralLevel.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalNetwork: (j['total_network'] ?? 0) as int,
        direct: ((j['direct'] ?? const []) as List)
            .map((e) => ReferralMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ReferralLevel {
  ReferralLevel({required this.level, required this.count, required this.rateBps});
  final int level;
  final int count;
  final int rateBps;
  factory ReferralLevel.fromJson(Map<String, dynamic> j) => ReferralLevel(
        level: (j['level'] ?? 0) as int,
        count: (j['count'] ?? 0) as int,
        rateBps: (j['rate_bps'] ?? 0) as int,
      );
}

class ReferralMember {
  ReferralMember({required this.earthId, required this.name, this.joinedAt});
  final String earthId;
  final String name;
  final String? joinedAt;
  factory ReferralMember.fromJson(Map<String, dynamic> j) => ReferralMember(
        earthId: (j['earth_id'] ?? '') as String,
        name: (j['name'] ?? j['earth_id'] ?? '') as String,
        joinedAt: j['joined_at'] as String?,
      );
}

class ChatRoom {
  ChatRoom({
    required this.id,
    required this.roomType,
    required this.title,
    required this.isE2ee,
    required this.createdBy,
  });

  final String id;
  final String roomType;
  final String? title;
  final bool isE2ee;
  final String createdBy;

  factory ChatRoom.fromJson(Map<String, dynamic> j) => ChatRoom(
        id: j['id'] as String,
        // dilix-api: `type`؛ Core: `room_type`.
        roomType: (j['type'] ?? j['room_type'] ?? 'direct') as String,
        // dilix-api: `name`/`partner_name`؛ Core: `title`.
        title: (j['name'] ?? j['title'] ?? j['partner_name']) as String?,
        isE2ee: (j['is_e2ee'] ?? false) as bool,
        createdBy: (j['created_by'] ?? '') as String,
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderEarthId,
    required this.msgType,
    required this.content,
    required this.sentAt,
    required this.deleted,
    this.mediaUrl,
  });

  final String id;
  final String roomId;
  final String senderEarthId;
  final String msgType;
  final String content;
  final DateTime sentAt;
  final bool deleted;
  final String? mediaUrl;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        roomId: (j['room_id'] ?? '') as String,
        senderEarthId: (j['sender_earth_id'] ?? '') as String,
        msgType: (j['msg_type'] ?? j['media_type'] ?? 'text') as String,
        content: (j['content'] ?? '') as String,
        mediaUrl: j['media_url'] as String?,
        // dilix-api: `created_at`؛ Core: `sent_at`.
        sentAt: DateTime.tryParse((j['created_at'] ?? j['sent_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        // dilix-api: `is_deleted`؛ Core: `deleted`.
        deleted: (j['is_deleted'] ?? j['deleted'] ?? false) as bool,
      );
}

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String channel;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
        id: j['id'] as String,
        // dilix-api: `type`؛ Core: `channel`.
        channel: (j['type'] ?? j['channel'] ?? 'system') as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        // dilix-api: `is_read`؛ Core: `read`.
        read: (j['is_read'] ?? j['read'] ?? false) as bool,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class AiConversation {
  AiConversation({
    required this.id,
    required this.agentType,
    required this.title,
    required this.createdAt,
  });

  final String id;
  final String agentType;
  final String? title;
  final DateTime createdAt;

  factory AiConversation.fromJson(Map<String, dynamic> j) => AiConversation(
        id: j['id'] as String,
        agentType: (j['agent_type'] ?? 'personal') as String,
        title: j['title'] as String?,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class AiMessage {
  AiMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.sentAt,
  });

  final String id;
  final String conversationId;
  final String role; // user | assistant | system
  final String content;
  final DateTime sentAt;

  /// سازگار با dilix-api (`ChatResponse`: `id`/`role`/`content`/`created_at`).
  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        id: (j['id'] ?? '') as String,
        conversationId: (j['conversation_id'] ?? '') as String,
        role: (j['role'] ?? 'assistant') as String,
        content: (j['content'] ?? '') as String,
        sentAt: DateTime.tryParse((j['created_at'] ?? j['sent_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// حلقهٔ داستانِ یک نویسنده در فیدِ داستان‌ها (`RingOut`).
class StoryRing {
  StoryRing({
    required this.authorEarthId,
    required this.storyCount,
    required this.hasUnseen,
    required this.isMe,
    required this.latestAt,
  });

  final String authorEarthId;
  final int storyCount;
  final bool hasUnseen;
  final bool isMe;
  final DateTime latestAt;

  factory StoryRing.fromJson(Map<String, dynamic> j) => StoryRing(
        authorEarthId: (j['earth_id'] ?? j['author_earth_id']) as String,
        storyCount: (j['story_count'] ?? 0) as int,
        hasUnseen: (j['has_unseen'] ?? false) as bool,
        isMe: (j['is_me'] ?? false) as bool,
        latestAt: DateTime.tryParse((j['latest_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// یک داستانِ منفرد (`StoryOut`).
class Story {
  Story({
    required this.id,
    required this.authorEarthId,
    required this.mediaUrl,
    required this.mediaType,
    required this.caption,
    required this.audience,
    required this.viewCount,
    required this.viewedByMe,
    required this.isMine,
    required this.createdAt,
  });

  final String id;
  final String authorEarthId;
  final String mediaUrl;
  final String mediaType; // image | video
  final String? caption;
  final String audience;
  final int viewCount;
  final bool viewedByMe;
  final bool isMine;
  final DateTime createdAt;

  factory Story.fromJson(Map<String, dynamic> j) => Story(
        id: j['id'] as String,
        authorEarthId: j['author_earth_id'] as String,
        mediaUrl: (j['media_url'] ?? '') as String,
        mediaType: (j['media_type'] ?? 'image') as String,
        caption: j['caption'] as String?,
        audience: (j['audience'] ?? 'public') as String,
        viewCount: (j['view_count'] ?? 0) as int,
        viewedByMe: (j['viewed_by_me'] ?? false) as bool,
        isMine: (j['is_mine'] ?? false) as bool,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// موجودیِ پاداش برای یک ارز (`RewardBalance`).
class RewardBalance {
  RewardBalance({
    required this.currency,
    required this.amountMinor,
    required this.rewardCount,
  });

  final String currency;
  final int amountMinor;
  final int rewardCount;

  factory RewardBalance.fromJson(Map<String, dynamic> j) => RewardBalance(
        currency: (j['currency'] ?? '') as String,
        amountMinor: (j['amount_minor'] ?? 0) as int,
        rewardCount: (j['reward_count'] ?? 0) as int,
      );
}

/// کیفِ پاداش (`RewardWallet`): موجودی‌ها + شمارِ در انتظار.
class RewardWallet {
  RewardWallet({required this.balances, required this.pendingCount});

  final List<RewardBalance> balances;
  final int pendingCount;

  factory RewardWallet.fromJson(Map<String, dynamic> j) {
    // شکلِ قدیمیِ Core: {balances:[...], pending_count}
    if (j['balances'] != null) {
      return RewardWallet(
        balances: (j['balances'] as List)
            .map((e) => RewardBalance.fromJson(e as Map<String, dynamic>))
            .toList(),
        pendingCount: (j['pending_count'] ?? 0) as int,
      );
    }
    // dilix-api `WalletResponse`: {currency, balance_available, balance_escrow,
    // balance_bonus}. موجودیِ در دسترس + پاداش در یک ردیف؛ امانت جدا.
    final currency = (j['currency'] ?? 'IRR') as String;
    final available = (j['balance_available'] as num?)?.toInt() ?? 0;
    final bonus = (j['balance_bonus'] as num?)?.toInt() ?? 0;
    final escrow = (j['balance_escrow'] as num?)?.toInt() ?? 0;
    return RewardWallet(
      balances: [
        RewardBalance(
            currency: currency, amountMinor: available + bonus, rewardCount: 0),
        if (escrow > 0)
          RewardBalance(
              currency: '$currency · امانت', amountMinor: escrow, rewardCount: 0),
      ],
      pendingCount: 0,
    );
  }
}

/// سهم از درآمد (`RevenueShare`).
class RevenueShare {
  RevenueShare({
    required this.eligible,
    required this.plan,
    required this.entitlementBps,
    required this.investmentUnits,
    required this.note,
  });

  final bool eligible;
  final String plan;
  final int entitlementBps;
  final int investmentUnits;
  final String note;

  factory RevenueShare.fromJson(Map<String, dynamic> j) => RevenueShare(
        eligible: (j['eligible'] ?? false) as bool,
        plan: (j['plan'] ?? '') as String,
        entitlementBps: (j['entitlement_bps'] ?? 0) as int,
        investmentUnits: (j['investment_units'] ?? 0) as int,
        note: (j['note'] ?? '') as String,
      );
}

/// سفارشِ پرداختِ امانی (`PaymentOrderOut`).
class PaymentOrder {
  PaymentOrder({
    required this.id,
    required this.payerEarthId,
    required this.payeeEarthId,
    required this.amountMinor,
    required this.currency,
    required this.providerCode,
    required this.externalRef,
    required this.status,
  });

  final String id;
  final String payerEarthId;
  final String payeeEarthId;
  final int amountMinor;
  final String currency;
  final String providerCode;
  final String? externalRef;
  final String status;

  factory PaymentOrder.fromJson(Map<String, dynamic> j) => PaymentOrder(
        id: j['id'] as String,
        payerEarthId: (j['payer_earth_id'] ?? '') as String,
        payeeEarthId: (j['payee_earth_id'] ?? '') as String,
        amountMinor: (j['amount_minor'] ?? 0) as int,
        currency: (j['currency'] ?? 'IRR') as String,
        providerCode: (j['provider_code'] ?? '') as String,
        externalRef: j['external_ref'] as String?,
        status: (j['status'] ?? '') as String,
      );
}

/// نرخِ روزِ صندوقِ سرمایه‌گذاری (`NavOut`).
class NavQuote {
  NavQuote({required this.fundCode, required this.navMinor});
  final String fundCode;
  final int navMinor;
  factory NavQuote.fromJson(Map<String, dynamic> j) => NavQuote(
        fundCode: (j['fund_code'] ?? '') as String,
        navMinor: (j['nav_minor'] ?? 0) as int,
      );
}

/// موقعیتِ سرمایه‌گذاریِ کاربر (`PositionOut`).
class InvestmentPosition {
  InvestmentPosition({
    required this.id,
    required this.fundCode,
    required this.units,
    required this.status,
  });
  final String id;
  final String fundCode;
  final num units;
  final String status;
  factory InvestmentPosition.fromJson(Map<String, dynamic> j) => InvestmentPosition(
        id: j['id'] as String,
        fundCode: (j['fund_code'] ?? '') as String,
        units: (j['units'] ?? 0) as num,
        status: (j['status'] ?? '') as String,
      );
}

/// عضویت/اشتراک (`MembershipOut`).
class Membership {
  Membership({
    required this.id,
    required this.earthId,
    required this.plan,
    required this.status,
    required this.cashbackBps,
    required this.expiresAt,
  });
  final String id;
  final String earthId;
  final String plan;
  final String status;
  final int cashbackBps;
  final DateTime? expiresAt;
  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        id: (j['id'] ?? '') as String,
        earthId: (j['earth_id'] ?? '') as String,
        plan: (j['plan'] ?? 'free') as String,
        status: (j['status'] ?? '') as String,
        cashbackBps: (j['cashback_bps'] ?? 0) as int,
        expiresAt: j['expires_at'] == null
            ? null
            : DateTime.tryParse(j['expires_at'] as String),
      );
}

/// نشانِ کسب‌شده (`BadgeOut`).
class Badge {
  Badge({
    required this.id,
    required this.badgeCode,
    required this.description,
    required this.awardedAt,
  });
  final String id;
  final String badgeCode;
  final String? description;
  final DateTime awardedAt;
  factory Badge.fromJson(Map<String, dynamic> j) => Badge(
        id: (j['id'] ?? '') as String,
        badgeCode: (j['badge_code'] ?? '') as String,
        description: j['description'] as String?,
        awardedAt: DateTime.tryParse((j['awarded_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// امتیازِ اعتبار در یک حوزه (`ScoreOut`).
class ReputationScore {
  ReputationScore({
    required this.earthId,
    required this.domain,
    required this.score,
    required this.reviewCount,
  });
  final String earthId;
  final String domain;
  final int score;
  final int reviewCount;
  factory ReputationScore.fromJson(Map<String, dynamic> j) => ReputationScore(
        earthId: (j['earth_id'] ?? '') as String,
        domain: (j['domain'] ?? '') as String,
        score: (j['score'] ?? 0) as int,
        reviewCount: (j['review_count'] ?? 0) as int,
      );
}

/// نظرِ دریافتی (`ReviewOut`).
class Review {
  Review({
    required this.id,
    required this.revieweeEarthId,
    required this.reviewerEarthId,
    required this.domain,
    required this.transactionRef,
    required this.rating,
    required this.comment,
  });
  final String id;
  final String revieweeEarthId;
  final String reviewerEarthId;
  final String domain;
  final String transactionRef;
  final int rating;
  final String? comment;
  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: (j['id'] ?? '') as String,
        revieweeEarthId: (j['reviewee_earth_id'] ?? '') as String,
        reviewerEarthId: (j['reviewer_earth_id'] ?? '') as String,
        domain: (j['domain'] ?? '') as String,
        transactionRef: (j['transaction_ref'] ?? '') as String,
        rating: (j['rating'] ?? 0) as int,
        comment: j['comment'] as String?,
      );
}

/// محصولِ بیمه در کاتالوگ (`ProductOut`).
class InsuranceProduct {
  InsuranceProduct({
    required this.id,
    required this.label,
    required this.emoji,
    required this.needsRoute,
    required this.needsCargoType,
    required this.valueLabel,
    this.baseRatePct,
  });
  final String id;
  final String label;
  final String emoji;
  final bool needsRoute;
  final bool needsCargoType;
  final String valueLabel;
  final double? baseRatePct;
  factory InsuranceProduct.fromJson(Map<String, dynamic> j) => InsuranceProduct(
        id: j['id'] as String,
        label: (j['label'] ?? '') as String,
        emoji: (j['emoji'] ?? '') as String,
        needsRoute: (j['needs_route'] ?? false) as bool,
        needsCargoType: (j['needs_cargo_type'] ?? false) as bool,
        valueLabel: (j['value_label'] ?? 'ارزش') as String,
        baseRatePct: (j['base_rate_pct'] as num?)?.toDouble(),
      );
}

/// نتیجهٔ استعلامِ نرخ (`QuoteResponse`). مبالغ به تومان‌اند.
class InsuranceQuote {
  InsuranceQuote({
    required this.product,
    required this.productLabel,
    required this.cargoValue,
    required this.coverageType,
    required this.coverageLabel,
    required this.baseRatePct,
    required this.premium,
    this.providerName,
  });
  final String product;
  final String productLabel;
  final int cargoValue;
  final String coverageType;
  final String coverageLabel;
  final double baseRatePct;
  final int premium;
  final String? providerName;
  factory InsuranceQuote.fromJson(Map<String, dynamic> j) => InsuranceQuote(
        product: (j['product'] ?? '') as String,
        productLabel: (j['product_label'] ?? '') as String,
        cargoValue: (j['cargo_value'] ?? 0) as int,
        coverageType: (j['coverage_type'] ?? '') as String,
        coverageLabel: (j['coverage_label'] ?? '') as String,
        baseRatePct: (j['base_rate_pct'] as num?)?.toDouble() ?? 0,
        premium: (j['premium'] ?? 0) as int,
        providerName: j['provider_name'] as String?,
      );
}

/// درخواستِ بیمهٔ ثبت‌شده (`RequestOut`). مبالغ به تومان‌اند.
class InsuranceRequest {
  InsuranceRequest({
    required this.id,
    required this.ref,
    required this.product,
    required this.productLabel,
    required this.cargoValue,
    required this.coverageType,
    required this.premium,
    required this.status,
    this.providerName,
  });
  final String id;
  final String ref;
  final String product;
  final String productLabel;
  final int cargoValue;
  final String coverageType;
  final int premium;
  final String status;
  final String? providerName;
  factory InsuranceRequest.fromJson(Map<String, dynamic> j) => InsuranceRequest(
        id: j['id'] as String,
        ref: (j['ref'] ?? '') as String,
        product: (j['product'] ?? '') as String,
        productLabel: (j['product_label'] ?? '') as String,
        cargoValue: (j['cargo_value'] ?? 0) as int,
        coverageType: (j['coverage_type'] ?? '') as String,
        premium: (j['premium'] ?? 0) as int,
        status: (j['status'] ?? '') as String,
        providerName: j['provider_name'] as String?,
      );
}

/// شارژِ موبایل (`TopUpOut`).
class TopUp {
  TopUp({
    required this.id,
    required this.msisdn,
    required this.productCode,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.externalRef,
  });
  final String id;
  final String msisdn;
  final String productCode;
  final int amountMinor;
  final String currency;
  final String status;
  final String? externalRef;
  factory TopUp.fromJson(Map<String, dynamic> j) => TopUp(
        id: j['id'] as String,
        msisdn: (j['msisdn'] ?? '') as String,
        productCode: (j['product_code'] ?? '') as String,
        amountMinor: (j['amount_minor'] ?? 0) as int,
        currency: (j['currency'] ?? 'IRR') as String,
        status: (j['status'] ?? '') as String,
        externalRef: j['external_ref'] as String?,
      );
}

/// eSIMِ فعال‌شده (`EsimOut`).
class Esim {
  Esim({
    required this.id,
    required this.iccid,
    required this.countryCode,
    required this.status,
  });
  final String id;
  final String iccid;
  final String countryCode;
  final String status;
  factory Esim.fromJson(Map<String, dynamic> j) => Esim(
        id: j['id'] as String,
        iccid: (j['iccid'] ?? '') as String,
        countryCode: (j['country_code'] ?? '') as String,
        status: (j['status'] ?? '') as String,
      );
}

/// ارائه‌دهنده (`ProviderOut`) — پورتالِ خودسرویس.
class Provider {
  Provider({
    required this.id,
    required this.legalName,
    required this.providerType,
    required this.country,
    required this.kybStatus,
  });

  final String id;
  final String legalName;
  final String providerType;
  final String country;
  final String kybStatus;

  factory Provider.fromJson(Map<String, dynamic> j) => Provider(
        id: j['id'] as String,
        legalName: (j['legal_name'] ?? '') as String,
        providerType: (j['provider_type'] ?? '') as String,
        country: (j['country'] ?? 'IR') as String,
        kybStatus: (j['kyb_status'] ?? '') as String,
      );
}

/// APIِ ثبت‌شدهٔ ارائه‌دهنده (`APIOut`). `status`: registered/tested/failed.
class ProviderApi {
  ProviderApi({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.env,
    required this.status,
    this.specUrl,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String env;
  final String status;
  final String? specUrl;

  factory ProviderApi.fromJson(Map<String, dynamic> j) => ProviderApi(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        baseUrl: (j['base_url'] ?? '') as String,
        env: (j['env'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        specUrl: j['spec_url'] as String?,
      );
}

/// Webhookِ ثبت‌شده (`WebhookOut`)؛ `secret` فقط هنگامِ ساخت.
class Webhook {
  Webhook({
    required this.id,
    required this.url,
    required this.status,
    this.secret,
  });

  final String id;
  final String url;
  final String status;
  final String? secret;

  factory Webhook.fromJson(Map<String, dynamic> j) => Webhook(
        id: j['id'] as String,
        url: (j['url'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        secret: j['secret'] as String?,
      );
}

/// رازِ ثبت‌شده برای فراخوانیِ API خدمات‌دهنده (`CredentialOut`).
/// رازِ خام هرگز برنمی‌گردد؛ فقط `keyPrefix` برای شناسایی نمایش داده می‌شود.
class Credential {
  Credential({
    required this.id,
    required this.label,
    required this.env,
    required this.keyPrefix,
    required this.status,
  });

  final String id;
  final String label;
  final String env;
  final String keyPrefix;
  final String status;

  factory Credential.fromJson(Map<String, dynamic> j) => Credential(
        id: j['id'] as String,
        label: (j['label'] ?? '') as String,
        env: (j['env'] ?? '') as String,
        keyPrefix: (j['key_prefix'] ?? '') as String,
        status: (j['status'] ?? '') as String,
      );
}
