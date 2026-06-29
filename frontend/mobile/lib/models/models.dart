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
    required this.reactionCounts,
    required this.commentCount,
  });

  final String id;
  final String authorEarthId;
  final String postType;
  final String? content;
  final Map<String, int> reactionCounts;
  final int commentCount;

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'] as String,
        authorEarthId: j['author_earth_id'] as String,
        postType: (j['post_type'] ?? 'text') as String,
        content: j['content'] as String?,
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

class ReferralLink {
  ReferralLink({required this.code, required this.url});
  final String code;
  final String url;
  factory ReferralLink.fromJson(Map<String, dynamic> j) =>
      ReferralLink(code: j['code'] as String, url: j['url'] as String);
}
