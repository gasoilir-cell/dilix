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
    this.userId,
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

  /// UUIDِ داخلیِ کاربر. ماژول‌هایی مثلِ حمل (`owner_id`/`driver_id`) به‌جای
  /// Earth ID با همین شناسه کار می‌کنند.
  final String? userId;

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
      userId: j['id'] as String?,
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
    this.placeName,
    this.lat,
    this.lng,
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

  /// نامِ مکانِ ثبت‌شده هنگامِ انتشار (اختیاری).
  final String? placeName;

  /// موقعیتِ جغرافیاییِ پست؛ فقط پست‌های دارای این دو در «لحظه‌ها» می‌آیند.
  final double? lat;
  final double? lng;

  /// آیا این پست روی کره جایی دارد؟
  bool get hasLocation => lat != null && lng != null;

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

  /// کپی با وضعیتِ ذخیرهٔ به‌روزشده (پس از toggleِ save).
  Post copyWithSaved(bool saved) => _copy(savedByMe: saved);

  Post _copy({
    int? commentCount,
    bool? likedByMe,
    bool? savedByMe,
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
        savedByMe: savedByMe ?? this.savedByMe,
        isMine: isMine,
        placeName: placeName,
        lat: lat,
        lng: lng,
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
      placeName: j['place_name'] as String?,
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
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

/// یک ریل (`/api/v1/reels`).
///
/// ⚠ ریل در dilix-api موجودیتِ **جدا** از پست است و شکلِ پاسخِ متفاوتی دارد
/// (`media_url`/`media_type` مفرد، `view_count`). پیش‌تر فیدِ ریلز در مدلِ
/// `Post` ریخته می‌شد و کنش‌ها به `/posts/{id}/...` می‌رفتند که برای شناسهٔ ریل
/// همیشه ۴۰۴ می‌داد.
class Reel {
  const Reel({
    required this.id,
    required this.authorEarthId,
    required this.authorName,
    required this.authorAvatar,
    required this.mediaUrl,
    required this.mediaType,
    required this.caption,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    required this.isMine,
  });

  final String id;
  final String authorEarthId;
  final String? authorName;
  final String? authorAvatar;
  final String mediaUrl;

  /// `video` یا `image` — سرور هر دو را می‌پذیرد، پس صفحه باید تصویر را هم
  /// نمایش دهد (نه پیامِ «ویدیویی ندارد»).
  final String mediaType;
  final String? caption;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final bool isMine;

  bool get isVideo => mediaType.startsWith('video');
  String get authorTitle =>
      (authorName?.trim().isNotEmpty ?? false) ? authorName!.trim() : authorEarthId;

  factory Reel.fromJson(Map<String, dynamic> j) => Reel(
        id: j['id'] as String,
        authorEarthId: (j['author_earth_id'] ?? '') as String,
        authorName: j['author_name'] as String?,
        authorAvatar: j['author_avatar'] as String?,
        mediaUrl: (j['media_url'] ?? '') as String,
        mediaType: (j['media_type'] ?? 'video') as String,
        caption: j['caption'] as String?,
        viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
        likeCount: (j['like_count'] as num?)?.toInt() ?? 0,
        commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
        likedByMe: (j['liked_by_me'] ?? false) as bool,
        isMine: (j['is_mine'] ?? false) as bool,
      );
}

/// هشتگِ پرتکرار (`GET /api/v1/posts/topics`).
class Topic {
  const Topic({required this.tag, required this.postCount});

  final String tag;
  final int postCount;

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
        tag: (j['tag'] ?? '') as String,
        postCount: (j['post_count'] as num?)?.toInt() ?? 0,
      );
}

/// نظر روی ریل یا پست. سرور برای هر دو دقیقاً همان اسکیمای `CommentOut` را
/// می‌دهد، پس یک مدلِ مشترک است.
class SocialComment {
  const SocialComment({
    required this.id,
    required this.authorEarthId,
    required this.authorName,
    required this.authorAvatar,
    required this.body,
    required this.isMine,
    required this.createdAt,
  });

  final String id;
  final String authorEarthId;
  final String? authorName;
  final String? authorAvatar;
  final String body;
  final bool isMine;
  final DateTime? createdAt;

  String get authorTitle =>
      (authorName?.trim().isNotEmpty ?? false) ? authorName!.trim() : authorEarthId;

  factory SocialComment.fromJson(Map<String, dynamic> j) => SocialComment(
        id: j['id'] as String,
        authorEarthId: (j['author_earth_id'] ?? '') as String,
        authorName: j['author_name'] as String?,
        authorAvatar: j['author_avatar'] as String?,
        body: (j['body'] ?? '') as String,
        isMine: (j['is_mine'] ?? false) as bool,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String),
      );
}

/// یک کاربر در فهرست‌های اجتماعی (دنبال‌کننده/دنبال‌شونده/پیشنهاد/جستجو).
///
/// همهٔ چهار اندپوینتِ `/api/v1/social/{followers,following,suggestions,search}`
/// دقیقاً همین شکل را برمی‌گردانند، پس یک مدلِ مشترک کافی است.
class SocialUser {
  const SocialUser({
    required this.earthId,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.role,
    required this.kycLevel,
    required this.isFollowing,
  });

  final String earthId;
  final String? name;
  final String? username;
  final String? avatarUrl;
  final String role;
  final int kycLevel;

  /// «من او را دنبال می‌کنم» — حتی در فهرستِ دنبال‌کنندگانِ خودم هم از دیدِ من است.
  final bool isFollowing;

  String get title => (name?.trim().isNotEmpty ?? false) ? name!.trim() : earthId;

  factory SocialUser.fromJson(Map<String, dynamic> j) => SocialUser(
        earthId: j['earth_id'] as String,
        name: j['name'] as String?,
        username: j['username'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        role: (j['role'] ?? 'user') as String,
        kycLevel: (j['kyc_level'] as num?)?.toInt() ?? 0,
        isFollowing: (j['is_following'] ?? false) as bool,
      );
}

/// پروفایلِ کاملِ یک کاربر (`GET /api/v1/social/profile/{earth_id}`).
class SocialProfile {
  const SocialProfile({
    required this.earthId,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.bio,
    required this.role,
    required this.kycLevel,
    required this.followersCount,
    required this.followingCount,
    required this.isFollowing,
    required this.isFollowedBy,
    required this.isMe,
  });

  final String earthId;
  final String? name;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final String role;
  final int kycLevel;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;

  /// او مرا دنبال می‌کند → برچسبِ «دنبال می‌کند شما را» و متنِ دکمه «دنبال متقابل».
  final bool isFollowedBy;
  final bool isMe;

  String get title => (name?.trim().isNotEmpty ?? false) ? name!.trim() : earthId;

  factory SocialProfile.fromJson(Map<String, dynamic> j) => SocialProfile(
        earthId: j['earth_id'] as String,
        name: j['name'] as String?,
        username: j['username'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        bio: j['bio'] as String?,
        role: (j['role'] ?? 'user') as String,
        kycLevel: (j['kyc_level'] as num?)?.toInt() ?? 0,
        followersCount: (j['followers_count'] as num?)?.toInt() ?? 0,
        followingCount: (j['following_count'] as num?)?.toInt() ?? 0,
        isFollowing: (j['is_following'] ?? false) as bool,
        isFollowedBy: (j['is_followed_by'] ?? false) as bool,
        isMe: (j['is_me'] ?? false) as bool,
      );

  SocialProfile copyWith({bool? isFollowing, int? followersCount}) =>
      SocialProfile(
        earthId: earthId,
        name: name,
        username: username,
        avatarUrl: avatarUrl,
        bio: bio,
        role: role,
        kycLevel: kycLevel,
        followersCount: followersCount ?? this.followersCount,
        followingCount: followingCount,
        isFollowing: isFollowing ?? this.isFollowing,
        isFollowedBy: isFollowedBy,
        isMe: isMe,
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
    this.ref,
    this.ownerId,
    this.driverId,
    this.description,
    this.offersCount = 0,
    this.escrowStatus,
    this.podPhotoUrl,
    this.pickupCode,
    this.deliveryCode,
    this.consigneeName,
    this.consigneePhone,
  });

  final String id;
  final String title;
  final String origin;
  final String destination;
  final String status;
  final int weightGrams;
  final int? budgetMinor;
  final String currency;

  /// شناسهٔ خواناىِ حمل (`FRT-XXXXXXXX`).
  final String? ref;
  final String? ownerId;

  /// رانندهٔ تخصیص‌یافته؛ تا وقتی بار `open` است null می‌ماند.
  final String? driverId;
  final String? description;
  final int offersCount;

  /// `locked|released|refunded` — وضعیتِ وجهِ امانی نزدِ سرور.
  final String? escrowStatus;
  final String? podPhotoUrl;

  /// کدهای تأییدِ ۴رقمی؛ سرور آن‌ها را **فقط** به صاحبِ بار برمی‌گرداند، پس برای
  /// راننده همیشه null هستند.
  final String? pickupCode;
  final String? deliveryCode;
  final String? consigneeName;
  final String? consigneePhone;

  bool get isOpen => status == 'open';

  /// آیا این بار در یکی از مرحله‌های در جریانِ حمل است؟
  bool get isActive =>
      status == 'in_progress' || status == 'picked_up' || status == 'in_transit';

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
        ref: j['ref'] as String?,
        ownerId: j['owner_id'] as String?,
        driverId: j['driver_id'] as String?,
        description: j['description'] as String?,
        offersCount: (j['offers_count'] as num?)?.toInt() ?? 0,
        escrowStatus: j['escrow_status'] as String?,
        podPhotoUrl: j['pod_photo_url'] as String?,
        pickupCode: j['pickup_code'] as String?,
        deliveryCode: j['delivery_code'] as String?,
        consigneeName: j['consignee_name'] as String?,
        consigneePhone: j['consignee_phone'] as String?,
      );
}

/// یک رویداد از خطِ زمانیِ رهگیریِ حمل — `GET /freight/posts/{id}/tracking`.
class TrackingEvent {
  TrackingEvent({
    required this.id,
    required this.eventType,
    this.status,
    this.note,
    this.lat,
    this.lng,
    this.createdAt,
  });

  final String id;

  /// `created|accepted|picked_up|location|delivered|received|cancelled`.
  final String eventType;
  final String? status;
  final String? note;
  final double? lat;
  final double? lng;
  final DateTime? createdAt;

  factory TrackingEvent.fromJson(Map<String, dynamic> j) => TrackingEvent(
        id: j['id'] as String,
        eventType: (j['event_type'] ?? '') as String,
        status: j['status'] as String?,
        note: j['note'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String),
      );
}

/// پیشنهادِ قیمتِ راننده روی یک بار — `/freight/posts/{id}/offers`.
///
/// سرور برای صاحبِ بار **همهٔ** پیشنهادهای در انتظار را ارزان‌ترین‌اول می‌دهد و
/// روی اولی [best] می‌زند؛ برای راننده فقط پیشنهادِ خودش را برمی‌گرداند.
class FreightOffer {
  FreightOffer({
    required this.id,
    required this.postId,
    required this.driverId,
    required this.price,
    required this.status,
    this.driverName,
    this.driverAvatar,
    this.driverRating = 0,
    this.driverTrips = 0,
    this.etaDays,
    this.message,
    this.isMine = false,
    this.best = false,
    this.createdAt,
  });

  final String id;
  final String postId;
  final String driverId;
  final String? driverName;
  final String? driverAvatar;

  /// میانگینِ امتیازِ راننده روی مقیاسِ ۰..۵ (سرور از `avg_rating/100` می‌سازد).
  final double driverRating;
  final int driverTrips;

  /// کرایهٔ پیشنهادی به **ریال**.
  final int price;
  final int? etaDays;
  final String? message;

  /// `pending` | `accepted` | `rejected` | `withdrawn`.
  final String status;
  final bool isMine;

  /// ارزان‌ترین پیشنهاد — فقط در دیدِ صاحبِ بار مقداردهی می‌شود.
  final bool best;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory FreightOffer.fromJson(Map<String, dynamic> j) => FreightOffer(
        id: (j['id'] ?? '') as String,
        postId: (j['post_id'] ?? '') as String,
        driverId: (j['driver_id'] ?? '') as String,
        driverName: j['driver_name'] as String?,
        driverAvatar: j['driver_avatar'] as String?,
        driverRating: (j['driver_rating'] as num?)?.toDouble() ?? 0,
        driverTrips: (j['driver_trips'] as num?)?.toInt() ?? 0,
        price: (j['price'] as num?)?.toInt() ?? 0,
        etaDays: (j['eta_days'] as num?)?.toInt(),
        message: j['message'] as String?,
        status: (j['status'] ?? 'pending') as String,
        isMine: (j['is_mine'] ?? false) as bool,
        best: (j['best'] ?? false) as bool,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String? ?? ''),
      );
}

/// یک ردیفِ کاتالوگِ ناوگان — `GET /freight/vehicle-types`.
class VehicleType {
  VehicleType({
    required this.code,
    required this.nameFa,
    required this.category,
    this.maxWeightKg,
    this.icon,
  });

  final String code;
  final String nameFa;
  final String category;
  final double? maxWeightKg;
  final String? icon;

  factory VehicleType.fromJson(Map<String, dynamic> j) => VehicleType(
        code: (j['code'] ?? '') as String,
        nameFa: (j['name_fa'] ?? '') as String,
        category: (j['category'] ?? '') as String,
        maxWeightKg: (j['max_weight_kg'] as num?)?.toDouble(),
        icon: j['icon'] as String?,
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

/// یک ردیفِ صفِ بررسیِ احرازِ هویت — `GET /api/v1/auth/admin/kyc`.
///
/// این با [KycStatus] فرق دارد: آن وضعیتِ *خودِ من* است، این پروندهٔ *یک کاربرِ
/// دیگر* است که فقط ادمین می‌بیند (سرور نقشِ `admin`/`super_admin` می‌خواهد).
class KycRequestItem {
  KycRequestItem({
    required this.id,
    required this.userId,
    required this.level,
    required this.status,
    this.fullName,
    this.nationalId,
    this.dateOfBirth,
    this.docFrontUrl,
    this.docSelfieUrl,
    this.createdAt,
  });

  final String id;
  final String userId;
  final int level;

  /// `pending` | `approved` | `rejected`.
  final String status;
  final String? fullName;
  final String? nationalId;
  final String? dateOfBirth;
  final String? docFrontUrl;
  final String? docSelfieUrl;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory KycRequestItem.fromJson(Map<String, dynamic> j) => KycRequestItem(
        id: (j['id'] ?? '') as String,
        userId: (j['user_id'] ?? '') as String,
        level: (j['level'] ?? 0) as int,
        status: (j['status'] ?? 'pending') as String,
        fullName: j['full_name'] as String?,
        nationalId: j['national_id'] as String?,
        dateOfBirth: j['date_of_birth'] as String?,
        docFrontUrl: j['doc_front_url'] as String?,
        docSelfieUrl: j['doc_selfie_url'] as String?,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String? ?? ''),
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

/// پیش‌نمایشِ پیامی که به آن پاسخ داده شده (`ReplyPreview` در dilix-api).
class ReplyPreview {
  ReplyPreview({
    required this.id,
    required this.content,
    this.senderName,
    this.isDeleted = false,
  });

  final String id;
  final String content;
  final String? senderName;
  final bool isDeleted;

  factory ReplyPreview.fromJson(Map<String, dynamic> j) => ReplyPreview(
        id: (j['id'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        senderName: j['sender_name'] as String?,
        isDeleted: (j['is_deleted'] ?? false) as bool,
      );
}

/// موقعیتِ مکانیِ ثابت یا زنده (`LocationInfo`).
class LocationInfo {
  LocationInfo({
    required this.lat,
    required this.lng,
    this.label,
    this.live = false,
    this.active = false,
    this.updatedAt,
    this.expiresAt,
  });

  final double lat;
  final double lng;
  final String? label;
  final bool live;
  final bool active;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  factory LocationInfo.fromJson(Map<String, dynamic> j) => LocationInfo(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        label: j['label'] as String?,
        live: (j['live'] ?? false) as bool,
        active: (j['active'] ?? false) as bool,
        updatedAt: _parseDate(j['updated_at']),
        expiresAt: _parseDate(j['expires_at']),
      );
}

/// یک گزینهٔ نظرسنجی (`PollOption`).
class PollOption {
  PollOption({required this.text, this.votes = 0, this.voted = false});

  final String text;
  final int votes;
  final bool voted;

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
        text: (j['text'] ?? '') as String,
        votes: (j['votes'] ?? 0) as int,
        voted: (j['voted'] ?? false) as bool,
      );
}

/// نظرسنجیِ داخلِ چت (`PollInfo`).
class PollInfo {
  PollInfo({
    required this.id,
    required this.question,
    required this.options,
    this.multiple = false,
    this.totalVotes = 0,
  });

  final String id;
  final String question;
  final List<PollOption> options;
  final bool multiple;
  final int totalVotes;

  factory PollInfo.fromJson(Map<String, dynamic> j) => PollInfo(
        id: (j['id'] ?? '') as String,
        question: (j['question'] ?? '') as String,
        multiple: (j['multiple'] ?? false) as bool,
        totalVotes: (j['total_votes'] ?? 0) as int,
        options: ((j['options'] ?? const []) as List)
            .map((e) => PollOption.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// مخاطبِ به‌اشتراک‌گذاشته‌شده (`ContactInfo`).
class ContactInfo {
  ContactInfo({required this.earthId, required this.name, this.avatarUrl});

  final String earthId;
  final String name;
  final String? avatarUrl;

  factory ContactInfo.fromJson(Map<String, dynamic> j) => ContactInfo(
        earthId: (j['earth_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        avatarUrl: j['avatar_url'] as String?,
      );
}

/// رویدادِ به‌اشتراک‌گذاشته‌شده در چت (`EventInfo`).
class EventInfo {
  EventInfo({
    required this.id,
    required this.title,
    required this.startsAt,
    this.location,
    this.description,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final String? location;
  final String? description;

  factory EventInfo.fromJson(Map<String, dynamic> j) => EventInfo(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        startsAt: _parseDate(j['starts_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        location: j['location'] as String?,
        description: j['description'] as String?,
      );
}

/// سهمِ برداشته‌شده از هدیهٔ نقدی (`RedPacketClaimOut`).
class RedPacketClaim {
  RedPacketClaim({
    required this.earthId,
    required this.name,
    required this.amount,
    this.avatarUrl,
    this.createdAt,
  });

  final String earthId;
  final String name;
  final int amount;
  final String? avatarUrl;
  final DateTime? createdAt;

  factory RedPacketClaim.fromJson(Map<String, dynamic> j) => RedPacketClaim(
        earthId: (j['earth_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        amount: (j['amount'] ?? 0) as int,
        avatarUrl: j['avatar_url'] as String?,
        createdAt: _parseDate(j['created_at']),
      );
}

/// هدیهٔ نقدیِ داخلِ چت (`RedPacketInfo`).
class RedPacketInfo {
  RedPacketInfo({
    required this.id,
    required this.senderEarthId,
    required this.senderName,
    required this.totalAmount,
    required this.count,
    required this.claimedCount,
    required this.claimedAmount,
    required this.mode,
    required this.status,
    this.greeting,
    this.expiresAt,
    this.isMine = false,
    this.myAmount,
    this.claimed = false,
    this.isExhausted = false,
    this.claims,
  });

  final String id;
  final String senderEarthId;
  final String senderName;
  final int totalAmount;
  final int count;
  final int claimedCount;
  final int claimedAmount;

  /// `equal` یا `random`.
  final String mode;

  /// `active` | `finished` | `refunded`.
  final String status;
  final String? greeting;
  final DateTime? expiresAt;
  final bool isMine;
  final int? myAmount;
  final bool claimed;
  final bool isExhausted;
  final List<RedPacketClaim>? claims;

  bool get isOpenable =>
      status == 'active' && !claimed && !isExhausted && !isMine;

  factory RedPacketInfo.fromJson(Map<String, dynamic> j) => RedPacketInfo(
        id: (j['id'] ?? '') as String,
        senderEarthId: (j['sender_earth_id'] ?? '') as String,
        senderName: (j['sender_name'] ?? '') as String,
        totalAmount: (j['total_amount'] ?? 0) as int,
        count: (j['count'] ?? 0) as int,
        claimedCount: (j['claimed_count'] ?? 0) as int,
        claimedAmount: (j['claimed_amount'] ?? 0) as int,
        mode: (j['mode'] ?? 'equal') as String,
        status: (j['status'] ?? 'active') as String,
        greeting: j['greeting'] as String?,
        expiresAt: _parseDate(j['expires_at']),
        isMine: (j['is_mine'] ?? false) as bool,
        myAmount: j['my_amount'] as int?,
        claimed: (j['claimed'] ?? false) as bool,
        isExhausted: (j['is_exhausted'] ?? false) as bool,
        claims: j['claims'] == null
            ? null
            : ((j['claims'] as List)
                .map((e) =>
                    RedPacketClaim.fromJson((e as Map).cast<String, dynamic>()))
                .toList()),
      );
}

/// عضوِ یک اتاق/گروه (`MemberOut`).
class RoomMember {
  RoomMember({
    required this.earthId,
    this.name,
    this.role,
    this.avatarUrl,
    this.isMe = false,
    this.isAdmin = false,
  });

  final String earthId;
  final String? name;
  final String? role;
  final String? avatarUrl;
  final bool isMe;
  final bool isAdmin;

  String get displayName => name ?? earthId;

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        earthId: (j['earth_id'] ?? '') as String,
        name: j['name'] as String?,
        role: j['role'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        isMe: (j['is_me'] ?? false) as bool,
        isAdmin: (j['is_admin'] ?? false) as bool,
      );
}

/// وضعیتِ لحظه‌ایِ اتاق: حضور، تایپینگ و TTLِ پیامِ ناپدیدشونده (`RoomStatusOut`).
class RoomStatus {
  RoomStatus({
    this.partnerOnline = false,
    this.partnerLastSeen,
    this.typing = const [],
    this.disappearSeconds = 0,
  });

  final bool partnerOnline;
  final DateTime? partnerLastSeen;
  final List<String> typing;
  final int disappearSeconds;

  factory RoomStatus.fromJson(Map<String, dynamic> j) => RoomStatus(
        partnerOnline: (j['partner_online'] ?? false) as bool,
        partnerLastSeen: _parseDate(j['partner_last_seen']),
        typing: ((j['typing'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        disappearSeconds: (j['disappear_seconds'] ?? 0) as int,
      );
}

/// نتیجهٔ ترجمه (`TranslationOut`).
class TranslationResult {
  TranslationResult({
    required this.targetLang,
    required this.original,
    required this.translatedText,
    this.messageId,
    this.detectedLang,
    this.cached = false,
  });

  final String targetLang;
  final String original;
  final String translatedText;
  final String? messageId;
  final String? detectedLang;
  final bool cached;

  factory TranslationResult.fromJson(Map<String, dynamic> j) =>
      TranslationResult(
        targetLang: (j['target_lang'] ?? '') as String,
        original: (j['original'] ?? '') as String,
        translatedText: (j['translated_text'] ?? '') as String,
        messageId: j['message_id'] as String?,
        detectedLang: j['detected_lang'] as String?,
        cached: (j['cached'] ?? false) as bool,
      );
}

/// یک استیکرِ تکی؛ `media_url` نسبی است و با `AppConfig.absoluteMedia` مطلق می‌شود.
class StickerItem {
  StickerItem({
    required this.id,
    required this.packId,
    required this.mediaUrl,
    required this.mediaType,
    this.emojiTag,
    this.title,
    this.starred = false,
  });

  final String id;
  final String packId;
  final String mediaUrl;
  final String mediaType;
  final String? emojiTag;
  final String? title;
  final bool starred;

  factory StickerItem.fromJson(Map<String, dynamic> j) => StickerItem(
        id: (j['id'] ?? '') as String,
        packId: (j['pack_id'] ?? '') as String,
        mediaUrl: (j['media_url'] ?? '') as String,
        mediaType: (j['media_type'] ?? 'image') as String,
        emojiTag: j['emoji_tag'] as String?,
        title: j['title'] as String?,
        starred: (j['is_starred'] ?? false) as bool,
      );

  StickerItem copyWith({bool? starred}) => StickerItem(
        id: id,
        packId: packId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        emojiTag: emojiTag,
        title: title,
        starred: starred ?? this.starred,
      );
}

/// بستهٔ استیکر. `PackOut` بدونِ فهرستِ استیکر می‌آید و `PackDetailOut` با آن.
class StickerPack {
  StickerPack({
    required this.id,
    required this.title,
    required this.installed,
    required this.mine,
    required this.stickerCount,
    this.description,
    this.coverUrl,
    this.ownerName,
    this.animated = false,
    this.isPublic = false,
    this.installCount = 0,
    this.stickers = const [],
  });

  final String id;
  final String title;
  final bool installed;
  final bool mine;
  final int stickerCount;
  final String? description;
  final String? coverUrl;
  final String? ownerName;
  final bool animated;
  final bool isPublic;
  final int installCount;
  final List<StickerItem> stickers;

  factory StickerPack.fromJson(Map<String, dynamic> j) => StickerPack(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        installed: (j['is_installed'] ?? false) as bool,
        mine: (j['is_mine'] ?? false) as bool,
        stickerCount: (j['sticker_count'] as num?)?.toInt() ?? 0,
        description: j['description'] as String?,
        coverUrl: j['cover_url'] as String?,
        ownerName: j['owner_name'] as String?,
        animated: (j['is_animated'] ?? false) as bool,
        isPublic: (j['is_public'] ?? false) as bool,
        installCount: (j['install_count'] as num?)?.toInt() ?? 0,
        stickers: ((j['stickers'] ?? const []) as List)
            .map((e) => StickerItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// یک ردیفِ گردشِ حسابِ کیفِ پول (`TransactionResponse`).
class WalletTransaction {
  WalletTransaction({
    required this.id,
    required this.type,
    required this.status,
    required this.amountMinor,
    required this.balanceAfter,
    this.description,
    this.createdAt,
  });

  final String id;
  final String type;
  final String status;
  final int amountMinor;
  final int balanceAfter;
  final String? description;
  final DateTime? createdAt;

  /// سرور مبلغ را همیشه مثبت می‌دهد و جهت را در `type` می‌گذارد، پس جهتِ نمایش
  /// از نامِ نوع استنتاج می‌شود.
  bool get isOutgoing =>
      type.contains('debit') ||
      type.contains('withdraw') ||
      type.contains('out') ||
      type.contains('purchase');

  factory WalletTransaction.fromJson(Map<String, dynamic> j) =>
      WalletTransaction(
        id: (j['id'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        amountMinor: (j['amount'] as num?)?.toInt() ?? 0,
        balanceAfter: (j['balance_after'] as num?)?.toInt() ?? 0,
        description: j['description'] as String?,
        createdAt: _parseDate(j['created_at']),
      );
}

/// تاریخِ ISO را با تحملِ `null` و مقدارِ نامعتبر پارس می‌کند.
DateTime? _parseDate(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

class ChatRoom {
  ChatRoom({
    required this.id,
    required this.roomType,
    required this.title,
    required this.isE2ee,
    required this.createdBy,
    this.partnerName,
    this.partnerEarthId,
    this.partnerRole,
    this.partnerAvatar,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.partnerOnline = false,
    this.memberCount = 0,
    this.isAdmin = false,
    this.partnerLastSeen,
    this.isMuted = false,
    this.isBlocked = false,
    this.disappearSeconds = 0,
  });

  final String id;
  final String roomType;
  final String? title;
  final bool isE2ee;
  final String createdBy;
  // فیلدهایِ dilix-api (`RoomOut`) برای فهرستِ بومیِ گفتگوها.
  final String? partnerName;
  final String? partnerEarthId;
  final String? partnerRole;
  final String? partnerAvatar;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool partnerOnline;
  final int memberCount;
  final bool isAdmin;
  final DateTime? partnerLastSeen;
  final bool isMuted;
  final bool isBlocked;

  /// TTLِ پیامِ ناپدیدشونده به ثانیه (۰ = خاموش).
  final int disappearSeconds;

  /// آیا این اتاق گروهی است؟
  bool get isGroup => roomType == 'group';

  /// عنوانِ نمایشیِ گفتگو: نامِ گروه یا نامِ طرفِ مقابل.
  String get displayTitle =>
      title ?? partnerName ?? partnerEarthId ?? 'گفتگو';

  factory ChatRoom.fromJson(Map<String, dynamic> j) => ChatRoom(
        id: j['id'] as String,
        // dilix-api: `type`؛ Core: `room_type`.
        roomType: (j['type'] ?? j['room_type'] ?? 'direct') as String,
        // dilix-api: `name`(گروه)؛ Core: `title`.
        title: (j['name'] ?? j['title']) as String?,
        isE2ee: (j['is_e2ee'] ?? false) as bool,
        createdBy: (j['created_by'] ?? '') as String,
        partnerName: j['partner_name'] as String?,
        partnerEarthId: j['partner_earth_id'] as String?,
        partnerRole: j['partner_role'] as String?,
        partnerAvatar: j['partner_avatar'] as String?,
        lastMessage: j['last_message'] as String?,
        lastMessageAt: j['last_message_at'] != null
            ? DateTime.tryParse(j['last_message_at'] as String)
            : null,
        unreadCount: (j['unread_count'] ?? 0) as int,
        partnerOnline: (j['partner_online'] ?? false) as bool,
        memberCount: (j['member_count'] ?? 0) as int,
        isAdmin: (j['is_admin'] ?? false) as bool,
        partnerLastSeen: _parseDate(j['partner_last_seen']),
        isMuted: (j['is_muted'] ?? false) as bool,
        isBlocked: (j['is_blocked'] ?? false) as bool,
        disappearSeconds: (j['disappear_seconds'] ?? 0) as int,
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
    this.senderName,
    this.isMine = false,
    this.mediaType,
    this.edited = false,
    this.isRead = false,
    this.replyTo,
    this.reactions = const {},
    this.myReaction,
    this.mediaName,
    this.mediaMeta,
    this.stickerId,
    this.location,
    this.poll,
    this.contact,
    this.event,
    this.redPacket,
    this.isForwarded = false,
    this.forwardedFrom,
    this.isPinned = false,
  });

  final String id;
  final String roomId;
  final String senderEarthId;
  final String msgType;
  final String content;
  final DateTime sentAt;
  final bool deleted;
  final String? mediaUrl;
  // فیلدهایِ dilix-api (`MessageOut`) برای نمایِ بومیِ گفتگو.
  final String? senderName;
  final bool isMine;
  final String? mediaType;
  final bool edited;
  final bool isRead;
  final ReplyPreview? replyTo;

  /// شمارشِ واکنش‌ها: ایموجی → تعداد.
  final Map<String, int> reactions;

  /// ایموجیِ واکنشِ خودم روی این پیام (اگر باشد).
  final String? myReaction;
  final String? mediaName;
  final String? mediaMeta;
  final String? stickerId;
  final LocationInfo? location;
  final PollInfo? poll;
  final ContactInfo? contact;
  final EventInfo? event;
  final RedPacketInfo? redPacket;
  final bool isForwarded;
  final String? forwardedFrom;
  final bool isPinned;

  /// پیامِ صرفاً متنی است (بدونِ رسانه و بدونِ محتوایِ ساختاری).
  bool get isPlainText => mediaType == null && stickerId == null;

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
        senderName: j['sender_name'] as String?,
        isMine: (j['is_mine'] ?? false) as bool,
        mediaType: j['media_type'] as String?,
        edited: (j['edited'] ?? false) as bool,
        isRead: (j['is_read'] ?? false) as bool,
        replyTo: j['reply_to'] == null
            ? null
            : ReplyPreview.fromJson(
                (j['reply_to'] as Map).cast<String, dynamic>()),
        reactions: ((j['reactions'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v ?? 0) as int)),
        myReaction: j['my_reaction'] as String?,
        mediaName: j['media_name'] as String?,
        mediaMeta: j['media_meta'] as String?,
        stickerId: j['sticker_id'] as String?,
        location: j['location'] == null
            ? null
            : LocationInfo.fromJson(
                (j['location'] as Map).cast<String, dynamic>()),
        poll: j['poll'] == null
            ? null
            : PollInfo.fromJson((j['poll'] as Map).cast<String, dynamic>()),
        contact: j['contact'] == null
            ? null
            : ContactInfo.fromJson(
                (j['contact'] as Map).cast<String, dynamic>()),
        event: j['event'] == null
            ? null
            : EventInfo.fromJson((j['event'] as Map).cast<String, dynamic>()),
        redPacket: j['red_packet'] == null
            ? null
            : RedPacketInfo.fromJson(
                (j['red_packet'] as Map).cast<String, dynamic>()),
        isForwarded: (j['is_forwarded'] ?? false) as bool,
        forwardedFrom: j['forwarded_from'] as String?,
        isPinned: (j['is_pinned'] ?? false) as bool,
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

/// یک گزینه در جدولِ مقایسهٔ نرخ (`QuoteOption`).
///
/// [premium] به ارزِ همان مرکز است ([currency])؛ سرور برای رتبه‌بندیِ منصفانه
/// همه را به سنتِ دلار ([premiumUsd]) نرمال می‌کند، پس ترتیبِ آرایه معتبر است
/// حتی اگر عددهای خام مستقیماً قابلِ مقایسه نباشند.
class InsuranceQuoteOption {
  InsuranceQuoteOption({
    required this.source,
    required this.premium,
    this.providerId,
    this.providerName,
    this.currency = 'IRR',
    this.premiumUsd,
    this.commissionRate,
    this.best = false,
  });

  /// `provider` (نرخِ واقعیِ یک مرکز) یا `internal` (نرخِ پایهٔ دیلیکس).
  final String source;
  final int premium;
  final String? providerId;
  final String? providerName;
  final String currency;
  final int? premiumUsd;
  final double? commissionRate;

  /// ارزان‌ترین گزینه پس از نرمال‌سازیِ ارز.
  final bool best;

  factory InsuranceQuoteOption.fromJson(Map<String, dynamic> j) =>
      InsuranceQuoteOption(
        source: (j['source'] ?? 'internal') as String,
        premium: (j['premium'] as num?)?.toInt() ?? 0,
        providerId: j['provider_id'] as String?,
        providerName: j['provider_name'] as String?,
        currency: (j['currency'] ?? 'IRR') as String,
        premiumUsd: (j['premium_usd'] as num?)?.toInt(),
        commissionRate: (j['commission_rate'] as num?)?.toDouble(),
        best: j['best'] == true,
      );
}

/// خروجیِ `POST /insurance/compare` — نرخِ همهٔ مراکز به‌صورتِ هم‌زمان.
class InsuranceCompare {
  InsuranceCompare({
    required this.productLabel,
    required this.coverageLabel,
    required this.cargoValue,
    required this.options,
    required this.providerCount,
  });

  final String productLabel;
  final String coverageLabel;
  final int cargoValue;
  final List<InsuranceQuoteOption> options;

  /// تعدادِ مراکزی که پاسخ داده‌اند (صفر یعنی فقط نرخِ پایهٔ داخلی).
  final int providerCount;

  factory InsuranceCompare.fromJson(Map<String, dynamic> j) => InsuranceCompare(
        productLabel: (j['product_label'] ?? '') as String,
        coverageLabel: (j['coverage_label'] ?? '') as String,
        cargoValue: (j['cargo_value'] as num?)?.toInt() ?? 0,
        options: ((j['options'] ?? const []) as List)
            .map((e) => InsuranceQuoteOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        providerCount: (j['provider_count'] as num?)?.toInt() ?? 0,
      );
}

/// خروجیِ `POST /insurance/inquiry` — استعلامِ سوابق برای پیش‌پُرکردنِ فرم.
class InsuranceInquiry {
  InsuranceInquiry({
    required this.found,
    required this.source,
    required this.message,
    required this.prefill,
    this.bonusMalus,
  });

  final bool found;

  /// `sanhab` (استعلامِ واقعی) یا `mock` (sandbox).
  final String source;
  final String message;

  /// فیلدهای آمادهٔ `form_data`؛ مقادیر را رشته نگه می‌داریم.
  final Map<String, String> prefill;

  /// سطحِ تخفیفِ عدم‌خسارت ۰..۱۰ (فقط بیمهٔ خودرو).
  final int? bonusMalus;

  factory InsuranceInquiry.fromJson(Map<String, dynamic> j) => InsuranceInquiry(
        found: j['found'] == true,
        source: (j['source'] ?? '') as String,
        message: (j['message'] ?? '') as String,
        prefill: ((j['prefill'] ?? const <String, dynamic>{}) as Map)
            .map((k, v) => MapEntry('$k', '$v')),
        bonusMalus: (j['bonus_malus'] as num?)?.toInt(),
      );
}

/// یک ردیفِ کارمزدِ بیمه (`CommissionOut`). مبالغ به تومان‌اند.
class InsuranceCommission {
  InsuranceCommission({
    required this.id,
    required this.premium,
    required this.commissionRate,
    required this.commissionAmount,
    required this.status,
    this.requestRef,
    this.providerId,
    this.providerName,
    this.product,
    this.settledAt,
  });

  final String id;
  final int premium;
  final double commissionRate;
  final int commissionAmount;

  /// `accrued` (تعهدشده) | `settled` (تسویه‌شده).
  final String status;
  final String? requestRef;
  final String? providerId;
  final String? providerName;
  final String? product;
  final DateTime? settledAt;

  bool get isSettled => status == 'settled';

  factory InsuranceCommission.fromJson(Map<String, dynamic> j) =>
      InsuranceCommission(
        id: (j['id'] ?? '') as String,
        premium: (j['premium'] as num?)?.toInt() ?? 0,
        commissionRate: (j['commission_rate'] as num?)?.toDouble() ?? 0,
        commissionAmount: (j['commission_amount'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? '') as String,
        requestRef: j['request_ref'] as String?,
        providerId: j['provider_id'] as String?,
        providerName: j['provider_name'] as String?,
        product: j['product'] as String?,
        settledAt: DateTime.tryParse((j['settled_at'] ?? '') as String),
      );
}

/// جمع‌بندیِ کارمزدِ یک مرکز (`ProviderCommissionSummary`).
class InsuranceCommissionSummary {
  InsuranceCommissionSummary({
    required this.policies,
    required this.totalPremium,
    required this.totalCommission,
    required this.accruedCommission,
    required this.settledCommission,
    this.providerId,
    this.providerName,
  });

  final int policies;
  final int totalPremium;
  final int totalCommission;

  /// بخشِ تسویه‌نشده — همان چیزی که «تسویهٔ دسته‌ای» پرداخت می‌کند.
  final int accruedCommission;
  final int settledCommission;
  final String? providerId;
  final String? providerName;

  factory InsuranceCommissionSummary.fromJson(Map<String, dynamic> j) =>
      InsuranceCommissionSummary(
        policies: (j['policies'] as num?)?.toInt() ?? 0,
        totalPremium: (j['total_premium'] as num?)?.toInt() ?? 0,
        totalCommission: (j['total_commission'] as num?)?.toInt() ?? 0,
        accruedCommission: (j['accrued_commission'] as num?)?.toInt() ?? 0,
        settledCommission: (j['settled_commission'] as num?)?.toInt() ?? 0,
        providerId: j['provider_id'] as String?,
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
    this.providerTypeLabel = '',
    this.kybStatusLabel = '',
    this.countryFlag = '',
    this.currency = 'IRR',
    this.commissionRate = 0,
    this.products = const [],
    this.productsLabels = const [],
  });

  final String id;
  final String legalName;
  final String providerType;
  final String country;

  /// `pending` | `verified` | `rejected` — تا `verified` نشود نرخِ این مرکز
  /// در مقایسه شرکت داده نمی‌شود.
  final String kybStatus;
  final String providerTypeLabel;
  final String kybStatusLabel;
  final String countryFlag;
  final String currency;
  final double commissionRate;

  /// کدهای محصولِ پوشش‌داده‌شده؛ خالی یعنی «همه».
  final List<String> products;
  final List<String> productsLabels;

  bool get isVerified => kybStatus == 'verified';

  factory Provider.fromJson(Map<String, dynamic> j) => Provider(
        id: j['id'] as String,
        legalName: (j['legal_name'] ?? '') as String,
        providerType: (j['provider_type'] ?? '') as String,
        country: (j['country'] ?? 'IR') as String,
        kybStatus: (j['kyb_status'] ?? '') as String,
        providerTypeLabel: (j['provider_type_label'] ?? '') as String,
        kybStatusLabel: (j['kyb_status_label'] ?? '') as String,
        countryFlag: (j['country_flag'] ?? '') as String,
        currency: (j['currency'] ?? 'IRR') as String,
        commissionRate: (j['commission_rate'] as num?)?.toDouble() ?? 0,
        products: ((j['products'] ?? const []) as List).map((e) => '$e').toList(),
        productsLabels:
            ((j['products_labels'] ?? const []) as List).map((e) => '$e').toList(),
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

  bool get isActive => status != 'revoked';
}

/// یک رویدادِ دریافتیِ webhook (`EventOut`) — برای عیب‌یابیِ اتصال.
class WebhookEvent {
  WebhookEvent({
    required this.id,
    required this.eventType,
    required this.receivedAt,
  });

  final String id;
  final String eventType;
  final DateTime? receivedAt;

  factory WebhookEvent.fromJson(Map<String, dynamic> j) => WebhookEvent(
        id: (j['id'] ?? '') as String,
        eventType: (j['event_type'] ?? '') as String,
        receivedAt: DateTime.tryParse((j['received_at'] ?? '') as String),
      );
}

/// یک ردیفِ کاتالوگِ ساده‌ی `{id, label, emoji?}` — انواعِ ارائه‌دهنده و
/// محصولاتِ قابلِ پوشش هر دو همین شکل را دارند.
class CatalogEntry {
  CatalogEntry({required this.id, required this.label, this.emoji});

  final String id;
  final String label;
  final String? emoji;

  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
        id: (j['id'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        emoji: j['emoji'] as String?,
      );
}

// ─────────────── کیفِ چندارزی (holdings) و درگاهِ پرداخت ───────────────

/// یک «جیب» ارزی در کیفِ چندارزی. مبالغ همیشه در واحدِ **خرد** (minor) هستند و
/// [scale] تعدادِ واحدِ خرد در یک واحدِ اصلی است (IRR=1، USD=100، BTC=1e8).
class Pocket {
  Pocket({
    required this.currency,
    required this.balance,
    required this.scale,
    required this.isPrimary,
    this.usdValue,
    this.baseValue,
  });

  final String currency;
  final int balance;
  final int scale;
  final bool isPrimary;
  final double? usdValue;
  final int? baseValue;

  /// مبلغ در واحدِ اصلی (برای نمایش).
  double get major => scale <= 0 ? balance.toDouble() : balance / scale;

  factory Pocket.fromJson(Map<String, dynamic> j) => Pocket(
        currency: ((j['currency'] ?? '') as String).toUpperCase(),
        balance: (j['balance'] as num?)?.toInt() ?? 0,
        scale: (j['scale'] as num?)?.toInt() ?? 1,
        isPrimary: (j['is_primary'] ?? false) as bool,
        usdValue: (j['usd_value'] as num?)?.toDouble(),
        baseValue: (j['base_value'] as num?)?.toInt(),
      );
}

/// نمایِ کاملِ کیفِ چندارزی (`GET /api/v1/holdings`).
class HoldingsSnapshot {
  HoldingsSnapshot({
    required this.baseCurrency,
    required this.pockets,
    required this.totalBase,
    required this.totalUsd,
  });

  final String baseCurrency;
  final List<Pocket> pockets;
  final int totalBase;
  final double totalUsd;

  factory HoldingsSnapshot.fromJson(Map<String, dynamic> j) => HoldingsSnapshot(
        baseCurrency: ((j['base_currency'] ?? 'IRR') as String).toUpperCase(),
        pockets: ((j['pockets'] as List?) ?? const [])
            .map((e) => Pocket.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        totalBase: (j['total_base'] as num?)?.toInt() ?? 0,
        totalUsd: (j['total_usd'] as num?)?.toDouble() ?? 0,
      );
}

/// تراکنشِ یک جیبِ ارزی (`GET /api/v1/holdings/transactions`).
class HoldingTx {
  HoldingTx({
    required this.id,
    required this.currency,
    required this.type,
    required this.status,
    required this.amount,
    required this.balanceAfter,
    this.counterparty,
    this.description,
    this.createdAt,
  });

  final String id;
  final String currency;

  /// `deposit` | `withdrawal` | `transfer_in` | `transfer_out` | `exchange_in` | `exchange_out`
  final String type;
  final String status;
  final int amount;
  final int balanceAfter;
  final String? counterparty;
  final String? description;
  final DateTime? createdAt;

  /// آیا این تراکنش موجودی را زیاد می‌کند؟ (برای علامتِ +/− و رنگ)
  bool get isCredit =>
      type == 'deposit' || type == 'transfer_in' || type == 'exchange_in';

  factory HoldingTx.fromJson(Map<String, dynamic> j) => HoldingTx(
        id: (j['id'] ?? '') as String,
        currency: ((j['currency'] ?? '') as String).toUpperCase(),
        type: (j['type'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        balanceAfter: (j['balance_after'] as num?)?.toInt() ?? 0,
        counterparty: j['counterparty'] as String?,
        description: j['description'] as String?,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String),
      );
}

/// اطلاعاتِ دریافت (`GET /api/v1/holdings/{currency}/receive`).
/// برای ارزِ غیرکریپتو فقط [earthId] پر است و [address] خالی می‌ماند.
class ReceiveInfo {
  ReceiveInfo({
    required this.currency,
    required this.earthId,
    required this.isCrypto,
    this.address,
    this.network,
    this.note,
  });

  final String currency;
  final String earthId;
  final bool isCrypto;
  final String? address;
  final String? network;
  final String? note;

  factory ReceiveInfo.fromJson(Map<String, dynamic> j) => ReceiveInfo(
        currency: ((j['currency'] ?? '') as String).toUpperCase(),
        earthId: (j['earth_id'] ?? '') as String,
        isCrypto: (j['is_crypto'] ?? false) as bool,
        address: j['address'] as String?,
        network: j['network'] as String?,
        note: j['note'] as String?,
      );
}

/// پیش‌فاکتورِ تبدیلِ ارز (`POST /api/v1/fx/quote`).
class FxQuote {
  FxQuote({
    required this.fromCurrency,
    required this.toCurrency,
    required this.amount,
    required this.converted,
    required this.rate,
    required this.fromScale,
    required this.toScale,
  });

  final String fromCurrency;
  final String toCurrency;
  final int amount;
  final int converted;
  final double rate;
  final int fromScale;
  final int toScale;

  factory FxQuote.fromJson(Map<String, dynamic> j) => FxQuote(
        fromCurrency: ((j['from_currency'] ?? '') as String).toUpperCase(),
        toCurrency: ((j['to_currency'] ?? '') as String).toUpperCase(),
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        converted: (j['converted'] as num?)?.toInt() ?? 0,
        rate: (j['rate'] as num?)?.toDouble() ?? 0,
        fromScale: (j['from_scale'] as num?)?.toInt() ?? 1,
        toScale: (j['to_scale'] as num?)?.toInt() ?? 1,
      );
}

/// درگاهِ پرداختِ فعال (`GET /api/v1/paygate/gateways`).
class PayGateway {
  PayGateway({
    required this.code,
    required this.name,
    required this.supportedCurrencies,
    required this.countries,
    required this.isSandbox,
    this.logoUrl,
  });

  final String code;
  final String name;
  final List<String> supportedCurrencies;
  final List<String> countries;
  final bool isSandbox;
  final String? logoUrl;

  factory PayGateway.fromJson(Map<String, dynamic> j) => PayGateway(
        code: (j['code'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        supportedCurrencies: ((j['supported_currencies'] as List?) ?? const [])
            .map((e) => e.toString().toUpperCase())
            .toList(),
        countries: ((j['countries'] as List?) ?? const [])
            .map((e) => e.toString().toUpperCase())
            .toList(),
        isSandbox: (j['is_sandbox'] ?? false) as bool,
        logoUrl: j['logo_url'] as String?,
      );
}

/// قصدِ شارژِ کیف‌پول (`POST /api/v1/paygate/topup/initiate`).
///
/// دو حالتِ کاملاً متفاوت دارد: درگاهِ معمولی [paymentUrl] می‌دهد که باید باز
/// شود، ولی درگاهِ کریپتو ([crypto]=true) هیچ ریدایرکتی ندارد و به‌جای آن
/// [address]/[network] را نشان می‌دهیم تا کاربر واریز کند.
class TopupIntent {
  TopupIntent({
    required this.intentId,
    required this.gateway,
    required this.amount,
    required this.currency,
    required this.creditAmount,
    required this.creditCurrency,
    required this.sandbox,
    required this.crypto,
    this.paymentUrl,
    this.authority,
    this.fxRate,
    this.address,
    this.network,
  });

  final String intentId;
  final String gateway;
  final int amount;
  final String currency;
  final int creditAmount;
  final String creditCurrency;
  final bool sandbox;
  final bool crypto;
  final String? paymentUrl;
  final String? authority;
  final double? fxRate;
  final String? address;
  final String? network;

  factory TopupIntent.fromJson(Map<String, dynamic> j) => TopupIntent(
        intentId: (j['intent_id'] ?? '') as String,
        gateway: (j['gateway'] ?? '') as String,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        currency: ((j['currency'] ?? '') as String).toUpperCase(),
        creditAmount: (j['credit_amount'] as num?)?.toInt() ?? 0,
        creditCurrency: ((j['credit_currency'] ?? '') as String).toUpperCase(),
        sandbox: (j['sandbox'] ?? false) as bool,
        crypto: (j['crypto'] ?? false) as bool,
        paymentUrl: j['payment_url'] as String?,
        authority: j['authority'] as String?,
        fxRate: (j['fx_rate'] as num?)?.toDouble(),
        address: j['address'] as String?,
        network: j['network'] as String?,
      );
}

// ─────────────── داستان‌ها: هایلایت، حلقهٔ مخاطب، بازدیدکننده ───────────────

/// یک هایلایتِ پروفایل (`HighlightOut`) — مجموعهٔ ماندگارِ داستان‌ها.
///
/// هایلایت **اسنپ‌شات** است: پس از ساخته‌شدن به انقضای داستانِ اصلی وابسته
/// نیست، پس حذفِ داستان آیتمِ هایلایت را پاک نمی‌کند.
class StoryHighlight {
  StoryHighlight({
    required this.id,
    required this.title,
    required this.itemCount,
    required this.isMine,
    required this.updatedAt,
    this.coverUrl,
  });

  final String id;
  final String title;
  final int itemCount;
  final bool isMine;
  final DateTime updatedAt;
  final String? coverUrl;

  factory StoryHighlight.fromJson(Map<String, dynamic> j) => StoryHighlight(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
        isMine: (j['is_mine'] ?? false) as bool,
        updatedAt: DateTime.tryParse((j['updated_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        coverUrl: j['cover_url'] as String?,
      );
}

/// یک آیتمِ داخلِ هایلایت (`HighlightItemOut`).
class HighlightItem {
  HighlightItem({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    required this.sortOrder,
    this.storyId,
    this.caption,
  });

  final String id;
  final String mediaUrl;
  final String mediaType; // image | video
  final int sortOrder;
  final String? storyId;
  final String? caption;

  factory HighlightItem.fromJson(Map<String, dynamic> j) => HighlightItem(
        id: (j['id'] ?? '') as String,
        mediaUrl: (j['media_url'] ?? '') as String,
        mediaType: (j['media_type'] ?? 'image') as String,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        storyId: j['story_id'] as String?,
        caption: j['caption'] as String?,
      );
}

/// جزئیاتِ یک هایلایت با آیتم‌هایش (`HighlightDetailOut`).
class HighlightDetail {
  HighlightDetail({
    required this.id,
    required this.title,
    required this.isMine,
    required this.ownerEarthId,
    required this.ownerName,
    required this.items,
    this.coverUrl,
  });

  final String id;
  final String title;
  final bool isMine;
  final String ownerEarthId;
  final String ownerName;
  final List<HighlightItem> items;
  final String? coverUrl;

  factory HighlightDetail.fromJson(Map<String, dynamic> j) => HighlightDetail(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        isMine: (j['is_mine'] ?? false) as bool,
        ownerEarthId: (j['owner_earth_id'] ?? '') as String,
        ownerName: (j['owner_name'] ?? '') as String,
        items: ((j['items'] as List?) ?? const [])
            .map((e) => HighlightItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        coverUrl: j['cover_url'] as String?,
      );
}

/// عضوِ یک حلقهٔ مخاطب (`CircleMember`).
class CircleMember {
  CircleMember({required this.earthId, required this.name, this.avatarUrl});

  final String earthId;
  final String name;
  final String? avatarUrl;

  factory CircleMember.fromJson(Map<String, dynamic> j) => CircleMember(
        earthId: (j['earth_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        avatarUrl: j['avatar_url'] as String?,
      );
}

/// سه حلقهٔ مخاطب (`CirclesOut`). نامِ کلیدها همان مقادیرِ مجازِ `audience` در
/// ساختِ داستان است، پس مستقیماً برای انتخابِ مخاطبِ داستان هم به کار می‌رود.
class ContactCircles {
  ContactCircles({
    required this.colleagues,
    required this.family,
    required this.friends,
  });

  final List<CircleMember> colleagues;
  final List<CircleMember> family;
  final List<CircleMember> friends;

  static List<CircleMember> _list(dynamic v) => ((v as List?) ?? const [])
      .map((e) => CircleMember.fromJson(e as Map<String, dynamic>))
      .toList();

  factory ContactCircles.fromJson(Map<String, dynamic> j) => ContactCircles(
        colleagues: _list(j['colleagues']),
        family: _list(j['family']),
        friends: _list(j['friends']),
      );

  List<CircleMember> of(String circle) => switch (circle) {
        'colleagues' => colleagues,
        'family' => family,
        _ => friends,
      };
}

/// یک بازدیدکنندهٔ داستان (`ViewerOut`) — فقط نویسندهٔ داستان آن را می‌بیند.
class StoryViewerEntry {
  StoryViewerEntry({
    required this.earthId,
    required this.name,
    required this.viewedAt,
    this.avatarUrl,
  });

  final String earthId;
  final String name;
  final DateTime viewedAt;
  final String? avatarUrl;

  factory StoryViewerEntry.fromJson(Map<String, dynamic> j) => StoryViewerEntry(
        earthId: (j['earth_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        viewedAt: DateTime.tryParse((j['viewed_at'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        avatarUrl: j['avatar_url'] as String?,
      );
}

// ─────────────── پخشِ زنده (live) ───────────────

/// میزبانِ یک پخشِ زنده (`_host_out`).
class LiveHost {
  LiveHost({required this.earthId, required this.name, this.avatarUrl});

  final String earthId;
  final String name;
  final String? avatarUrl;

  factory LiveHost.fromJson(Map<String, dynamic> j) => LiveHost(
        earthId: (j['earth_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        avatarUrl: j['avatar_url'] as String?,
      );
}

/// یک پخشِ زندهٔ فعال در فهرستِ کشف (`GET /live`).
class LiveItem {
  LiveItem({
    required this.sessionId,
    required this.host,
    required this.viewerCount,
    required this.hearts,
    required this.isMine,
    this.title,
    this.startedAt,
  });

  final String sessionId;
  final LiveHost host;
  final int viewerCount;
  final int hearts;
  final bool isMine;
  final String? title;
  final DateTime? startedAt;

  factory LiveItem.fromJson(Map<String, dynamic> j) => LiveItem(
        sessionId: (j['session_id'] ?? '') as String,
        host: LiveHost.fromJson(
            (j['host'] as Map?)?.cast<String, dynamic>() ?? const {}),
        viewerCount: (j['viewer_count'] as num?)?.toInt() ?? 0,
        hearts: (j['hearts'] as num?)?.toInt() ?? 0,
        isMine: (j['is_mine'] ?? false) as bool,
        title: j['title'] as String?,
        startedAt: DateTime.tryParse((j['started_at'] ?? '') as String),
      );
}

/// پاسخِ `POST /live/{id}/join` — همه‌چیزِ لازم برای شروعِ تماشا.
class LiveJoinInfo {
  LiveJoinInfo({
    required this.sessionId,
    required this.host,
    required this.hostEarthId,
    required this.status,
    required this.iceServers,
    required this.viewerCount,
    required this.hearts,
    required this.isHost,
    this.title,
  });

  final String sessionId;
  final LiveHost host;
  final String hostEarthId;
  final String status;
  final List<Map<String, dynamic>> iceServers;
  final int viewerCount;
  final int hearts;
  final bool isHost;
  final String? title;

  factory LiveJoinInfo.fromJson(Map<String, dynamic> j) => LiveJoinInfo(
        sessionId: (j['session_id'] ?? '') as String,
        host: LiveHost.fromJson(
            (j['host'] as Map?)?.cast<String, dynamic>() ?? const {}),
        hostEarthId: (j['host_earth_id'] ?? '') as String,
        status: (j['status'] ?? 'live') as String,
        iceServers: ((j['iceServers'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(),
        viewerCount: (j['viewer_count'] as num?)?.toInt() ?? 0,
        hearts: (j['hearts'] as num?)?.toInt() ?? 0,
        isHost: (j['is_host'] ?? false) as bool,
        title: j['title'] as String?,
      );
}

/// پیامِ چتِ زنده. روی Redis نگهداری می‌شود و ماندگار نیست.
class LiveChatMessage {
  LiveChatMessage({
    required this.id,
    required this.fromEarthId,
    required this.fromName,
    required this.text,
    this.fromAvatar,
  });

  final String id;
  final String fromEarthId;
  final String fromName;
  final String text;
  final String? fromAvatar;

  factory LiveChatMessage.fromJson(Map<String, dynamic> j) => LiveChatMessage(
        id: (j['id'] ?? '') as String,
        fromEarthId: (j['from'] ?? '') as String,
        fromName: (j['from_name'] ?? '') as String,
        text: (j['text'] ?? '') as String,
        fromAvatar: j['from_avatar'] as String?,
      );
}

/// وضعیتِ لحظه‌ایِ پخش (`GET /live/{id}/state`). خواندنِ آن برای بیننده
/// heartbeatِ حضور هم هست، پس نباید قطع شود وگرنه از شمارش خارج می‌شود.
class LiveState {
  LiveState({
    required this.status,
    required this.viewerCount,
    required this.hearts,
  });

  final String status;
  final int viewerCount;
  final int hearts;

  bool get isLive => status == 'live';

  factory LiveState.fromJson(Map<String, dynamic> j) => LiveState(
        status: (j['status'] ?? 'ended') as String,
        viewerCount: (j['viewer_count'] as num?)?.toInt() ?? 0,
        hearts: (j['hearts'] as num?)?.toInt() ?? 0,
      );
}

// ─────────────── جهانی‌سازی (i18n): زبان، ارز و ترجیحات ───────────────

/// یک زبانِ پشتیبانی‌شده در کاتالوگِ سرور.
class LocaleOption {
  LocaleOption({
    required this.code,
    required this.native,
    required this.english,
    required this.dir,
    required this.defaultCurrency,
    this.flag,
  });

  final String code;
  final String native;
  final String english;

  /// `rtl` یا `ltr`.
  final String dir;
  final String defaultCurrency;
  final String? flag;

  bool get isRtl => dir == 'rtl';

  factory LocaleOption.fromJson(Map<String, dynamic> j) => LocaleOption(
        code: j['code'] as String,
        native: (j['native'] ?? j['code']) as String,
        english: (j['english'] ?? j['code']) as String,
        dir: (j['dir'] ?? 'ltr') as String,
        defaultCurrency: (j['default_currency'] ?? 'USD') as String,
        flag: j['flag'] as String?,
      );
}

/// یک ارزِ پشتیبانی‌شده در کاتالوگِ سرور.
class CurrencyOption {
  CurrencyOption({
    required this.code,
    required this.nameFa,
    required this.nameEn,
    required this.symbol,
    required this.decimals,
    this.subunit,
  });

  final String code;
  final String nameFa;
  final String nameEn;
  final String symbol;
  final int decimals;

  /// واحدِ نمایشِ محلی (برای IRR: «تومان»)؛ برای بقیه null.
  final String? subunit;

  factory CurrencyOption.fromJson(Map<String, dynamic> j) => CurrencyOption(
        code: j['code'] as String,
        nameFa: (j['name_fa'] ?? j['code']) as String,
        nameEn: (j['name_en'] ?? j['code']) as String,
        symbol: (j['symbol'] ?? '') as String,
        decimals: (j['decimals'] as num?)?.toInt() ?? 2,
        subunit: j['subunit'] as String?,
      );
}

/// `GET /api/v1/i18n/catalog` — عمومی، بدونِ نیاز به ورود.
class I18nCatalog {
  I18nCatalog({
    required this.locales,
    required this.currencies,
    required this.defaultLocale,
    required this.defaultCurrency,
  });

  final List<LocaleOption> locales;
  final List<CurrencyOption> currencies;
  final String defaultLocale;
  final String defaultCurrency;

  factory I18nCatalog.fromJson(Map<String, dynamic> j) => I18nCatalog(
        locales: ((j['locales'] ?? const []) as List)
            .map((e) => LocaleOption.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        currencies: ((j['currencies'] ?? const []) as List)
            .map((e) => CurrencyOption.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        defaultLocale: (j['default_locale'] ?? 'en') as String,
        defaultCurrency: (j['default_currency'] ?? 'USD') as String,
      );
}

/// `GET /api/v1/i18n/detect` — فقط «پیشنهاد» است و کاربر می‌تواند نادیده بگیرد.
class I18nSuggestion {
  I18nSuggestion({
    required this.locale,
    required this.currency,
    required this.direction,
    this.country,
    this.source,
  });

  final String locale;
  final String currency;
  final String direction;
  final String? country;

  /// `geoip|accept-language|default`.
  final String? source;

  factory I18nSuggestion.fromJson(Map<String, dynamic> j) => I18nSuggestion(
        locale: (j['suggested_locale'] ?? 'en') as String,
        currency: (j['suggested_currency'] ?? 'USD') as String,
        direction: (j['direction'] ?? 'ltr') as String,
        country: j['country'] as String?,
        source: j['source'] as String?,
      );
}

/// ترجیحاتِ ذخیره‌شدهٔ کاربر — `GET/PUT /api/v1/i18n/preferences`.
class I18nPreferences {
  I18nPreferences({
    required this.locale,
    required this.currency,
    required this.direction,
    this.countryCode,
    this.timezone,
  });

  final String locale;
  final String currency;
  final String direction;
  final String? countryCode;
  final String? timezone;

  bool get isRtl => direction == 'rtl';

  factory I18nPreferences.fromJson(Map<String, dynamic> j) => I18nPreferences(
        locale: (j['locale'] ?? 'fa') as String,
        currency: (j['currency'] ?? 'IRR') as String,
        direction: (j['direction'] ?? 'rtl') as String,
        countryCode: j['country_code'] as String?,
        timezone: j['timezone'] as String?,
      );
}

// ─────────────── کمیسیونِ بازاریابیِ چندسطحی ───────────────

/// یک ردیفِ لِجِرِ کمیسیون — `GET /api/v1/referral/commissions`.
class MlmCommission {
  MlmCommission({
    required this.id,
    required this.level,
    required this.amount,
    required this.currency,
    required this.rateBps,
    this.sourceType,
    this.createdAt,
  });

  final String id;

  /// سطحِ زیرمجموعه‌ای که این کمیسیون از آن آمده (۱ تا ۳).
  final int level;

  /// مبلغ در واحدِ خردِ همان ارز.
  final int amount;
  final String currency;

  /// نرخ بر حسبِ صدمِ درصد (۸۰۰ = ۸٪).
  final int rateBps;
  final String? sourceType;
  final DateTime? createdAt;

  /// نرخ به درصد، برای نمایش.
  double get ratePercent => rateBps / 100;

  factory MlmCommission.fromJson(Map<String, dynamic> j) => MlmCommission(
        id: j['id'] as String,
        level: (j['level'] as num?)?.toInt() ?? 1,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        currency: (j['currency'] ?? 'IRR') as String,
        rateBps: (j['rate_bps'] as num?)?.toInt() ?? 0,
        sourceType: j['source_type'] as String?,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String),
      );
}

/// لِجِرِ کمیسیون + جمعِ درآمد به تفکیکِ ارز.
class CommissionLedger {
  CommissionLedger({required this.items, required this.totals});

  final List<MlmCommission> items;

  /// ارز → جمعِ مبلغ در واحدِ خرد.
  final Map<String, int> totals;

  factory CommissionLedger.fromJson(Map<String, dynamic> j) => CommissionLedger(
        items: ((j['commissions'] ?? const []) as List)
            .map((e) => MlmCommission.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        totals: ((j['totals'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
      );
}
