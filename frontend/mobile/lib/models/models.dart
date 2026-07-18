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
  });

  final String earthId;
  final String entityType;
  final String status;
  final int kycLevel;
  final String homeRegion;
  final String? displayName;

  factory Identity.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] as Map<String, dynamic>?;
    return Identity(
      earthId: j['earth_id'] as String,
      entityType: (j['entity_type'] ?? 'individual') as String,
      status: (j['status'] ?? 'active') as String,
      kycLevel: (j['kyc_level'] ?? 0) as int,
      homeRegion: (j['home_region'] ?? 'IR') as String,
      displayName: profile?['display_name'] as String?,
    );
  }
}

class Post {
  Post({
    required this.id,
    required this.authorEarthId,
    required this.postType,
    required this.content,
    required this.media,
    required this.reactionCounts,
    required this.commentCount,
  });

  final String id;
  final String authorEarthId;
  final String postType;
  final String? content;

  /// آرایه‌ی رسانه‌ها؛ هر آیتم آبجکتی با کلیدِ url/media_url (و اختیاری type).
  final List<Map<String, dynamic>> media;
  final Map<String, int> reactionCounts;
  final int commentCount;

  /// اولین نشانیِ ویدیوی پست (برای ریلز). اگر ویدیویی نباشد null.
  String? get videoUrl {
    for (final m in media) {
      final url = (m['url'] ?? m['media_url']) as String?;
      final kind = (m['type'] ?? m['media_type'] ?? '') as String;
      if (url != null && (kind.isEmpty || kind.startsWith('video'))) return url;
    }
    return null;
  }

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'] as String,
        authorEarthId: j['author_earth_id'] as String,
        postType: (j['post_type'] ?? 'text') as String,
        content: j['content'] as String?,
        media: ((j['media'] ?? const []) as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
        reactionCounts: ((j['reaction_counts'] ?? {}) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
        commentCount: (j['comment_count'] ?? 0) as int,
      );
}

class NearbyPerson {
  NearbyPerson({
    required this.earthId,
    required this.entityType,
    required this.displayName,
    required this.geoPrecision,
    required this.profession,
    required this.lat,
    required this.lon,
  });

  final String earthId;
  final String entityType;
  final String? displayName;
  final String geoPrecision;
  final String? profession;
  final double lat;
  final double lon;

  factory NearbyPerson.fromJson(Map<String, dynamic> j) => NearbyPerson(
        earthId: j['earth_id'] as String,
        entityType: (j['entity_type'] ?? 'individual') as String,
        displayName: j['display_name'] as String?,
        geoPrecision: (j['geo_precision'] ?? 'region') as String,
        profession: j['profession'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );
}

class CargoPost {
  CargoPost({
    required this.id,
    required this.title,
    required this.origin,
    required this.destination,
    required this.status,
  });

  final String id;
  final String title;
  final String origin;
  final String destination;
  final String status;

  factory CargoPost.fromJson(Map<String, dynamic> j) => CargoPost(
        id: j['id'] as String,
        title: j['title'] as String,
        origin: j['origin'] as String,
        destination: j['destination'] as String,
        status: (j['status'] ?? 'open') as String,
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
  ReferralLink({required this.code, required this.url});
  final String code;
  final String url;
  factory ReferralLink.fromJson(Map<String, dynamic> j) =>
      ReferralLink(code: j['code'] as String, url: j['url'] as String);
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
        roomType: (j['room_type'] ?? 'direct') as String,
        title: j['title'] as String?,
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
  });

  final String id;
  final String roomId;
  final String senderEarthId;
  final String msgType;
  final String content;
  final DateTime sentAt;
  final bool deleted;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        roomId: (j['room_id'] ?? '') as String,
        senderEarthId: (j['sender_earth_id'] ?? '') as String,
        msgType: (j['msg_type'] ?? 'text') as String,
        content: (j['content'] ?? '') as String,
        sentAt: DateTime.tryParse((j['sent_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        deleted: (j['deleted'] ?? false) as bool,
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
        channel: (j['channel'] ?? 'system') as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        read: (j['read'] ?? false) as bool,
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

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        id: (j['id'] ?? '') as String,
        conversationId: (j['conversation_id'] ?? '') as String,
        role: (j['role'] ?? 'assistant') as String,
        content: (j['content'] ?? '') as String,
        sentAt: DateTime.tryParse((j['sent_at'] ?? '') as String) ??
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
        authorEarthId: j['author_earth_id'] as String,
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
