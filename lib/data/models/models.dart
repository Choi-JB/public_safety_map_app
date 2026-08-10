/// pathing utility
double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

// --- Auth ---

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.nickname,
  });

  final int id;
  final String email;
  final String role;
  final String? nickname;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] as num).toInt(),
        email: j['email'] as String? ?? '',
        role: j['role'] as String? ?? 'USER',
        nickname: j['nickname'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'nickname': nickname,
      };
}

// --- Map domain ---

class GridItem {
  const GridItem({
    required this.gridId,
    this.lat,
    this.lng,
    this.infraCount,
    this.safetyGrade,
  });

  final int gridId;
  final double? lat;
  final double? lng;
  final int? infraCount;
  final String? safetyGrade;

  factory GridItem.fromJson(Map<String, dynamic> j) => GridItem(
        gridId: (j['grid_id'] as num).toInt(),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        infraCount: (j['infra_count'] as num?)?.toInt(),
        safetyGrade: j['safety_grade'] as String?,
      );
}

class GridTagStat {
  const GridTagStat({required this.name, required this.count});
  final String name;
  final int count;

  factory GridTagStat.fromJson(Map<String, dynamic> j) => GridTagStat(
        name: j['name'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

class GridDetail {
  const GridDetail({
    required this.gridId,
    this.lat,
    this.lng,
    this.infraCount,
    this.safetyGrade,
    this.tags = const [],
    this.topTag,
    this.safetyFeelingRatio,
    this.recentFeedbacks = const [],
    this.activeReports = const [],
    this.feedbackCount = 0,
    this.participantCount = 0,
  });

  final int gridId;
  final double? lat;
  final double? lng;
  final int? infraCount;
  final String? safetyGrade;
  final List<GridTagStat> tags;
  final String? topTag;
  final Map<String, dynamic>? safetyFeelingRatio;
  final List<Map<String, dynamic>> recentFeedbacks;
  final List<Map<String, dynamic>> activeReports;
  final int feedbackCount;
  final int participantCount;

  factory GridDetail.fromJson(Map<String, dynamic> j) => GridDetail(
        gridId: (j['grid_id'] as num).toInt(),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        infraCount: (j['infra_count'] as num?)?.toInt(),
        safetyGrade: j['safety_grade'] as String?,
        tags: (j['tags'] as List? ?? [])
            .map((e) => GridTagStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        topTag: j['top_tag'] as String?,
        safetyFeelingRatio: j['safety_feeling_ratio'] as Map<String, dynamic>?,
        recentFeedbacks: (j['recent_feedbacks'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        activeReports: (j['active_reports'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        feedbackCount: (j['feedback_count'] as num?)?.toInt() ?? 0,
        participantCount: (j['participant_count'] as num?)?.toInt() ?? 0,
      );
}

class ReportItem {
  const ReportItem({
    required this.id,
    this.type,
    this.lat,
    this.lng,
    this.description,
    this.imgUrl,
    this.userNickname,
    this.createdAt,
    this.expireAt,
    this.isAdminPosted = false,
  });

  final int id;
  final String? type;
  final double? lat;
  final double? lng;
  final String? description;
  final String? imgUrl;
  final String? userNickname;
  final String? createdAt;
  final String? expireAt;
  final bool isAdminPosted;

  factory ReportItem.fromJson(Map<String, dynamic> j) => ReportItem(
        id: (j['id'] as num).toInt(),
        type: j['type'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        description: j['description'] as String?,
        imgUrl: j['img_url'] as String?,
        userNickname: j['user_nickname'] as String?,
        createdAt: j['created_at']?.toString(),
        expireAt: j['expire_at']?.toString(),
        isAdminPosted: j['is_admin_posted'] == true,
      );
}

class CityEventItem {
  const CityEventItem({
    required this.id,
    this.type,
    this.title,
    this.description,
    this.lat,
    this.lng,
    this.startAt,
    this.endAt,
    this.imgUrl,
  });

  final int id;
  final String? type;
  final String? title;
  final String? description;
  final double? lat;
  final double? lng;
  final String? startAt;
  final String? endAt;
  final String? imgUrl;

  factory CityEventItem.fromJson(Map<String, dynamic> j) => CityEventItem(
        id: (j['id'] as num).toInt(),
        type: j['type'] as String?,
        title: j['title'] as String?,
        description: j['description'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        startAt: j['start_at']?.toString(),
        endAt: j['end_at']?.toString(),
        imgUrl: j['img_url'] as String?,
      );
}

class InfrastructureItem {
  const InfrastructureItem({
    required this.id,
    this.type,
    this.address,
    this.lat,
    this.lng,
  });

  final int id;
  final String? type;
  final String? address;
  final double? lat;
  final double? lng;

  
  factory InfrastructureItem.fromJson(Map<String, dynamic> j) =>
      InfrastructureItem(
        id: (j['id'] as num).toInt(),
        type: j['type'] as String?,
        address: j['address'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );
}

class AccidentZoneItem {
  const AccidentZoneItem({
    required this.id,
    required this.type,
    required this.name,
    required this.path,
    this.yearCd,
    this.lat,
    this.lng,
    this.occrrncCnt,
    this.casltCnt,
    this.dthDnvCnt,
  });

  final String id;
  final String type;
  final String name;
  final String? yearCd;
  final double? lat;
  final double? lng;
  final int? occrrncCnt;
  final int? casltCnt;
  final int? dthDnvCnt;
  final List<({double lat, double lng})> path;

  factory AccidentZoneItem.fromJson(Map<String, dynamic> j) {
    final rawPath = j['path'] as List? ?? [];
    return AccidentZoneItem(
      id: j['id']?.toString() ?? '',
      type: j['type'] as String? ?? '',
      name: j['name'] as String? ?? '',
      yearCd: j['yearCd']?.toString(),
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      occrrncCnt: (j['occrrnc_cnt'] as num?)?.toInt(),
      casltCnt: (j['caslt_cnt'] as num?)?.toInt(),
      dthDnvCnt: (j['dth_dnv_cnt'] as num?)?.toInt(),
      path: rawPath.map((e) {
        final m = e as Map<String, dynamic>;
        return (
          lat: (m['lat'] as num).toDouble(),
          lng: (m['lng'] as num).toDouble(),
        );
      }).toList(),
    );
  }
}

// --- MyPage ---

class MyPageSummary {
  const MyPageSummary({this.reportCount = 0, this.feedbackCount = 0});
  final int reportCount;
  final int feedbackCount;

  factory MyPageSummary.fromJson(Map<String, dynamic> j) => MyPageSummary(
        reportCount: _asInt(j['reportCount']) ?? 0,
        feedbackCount: _asInt(j['feedbackCount']) ?? 0,
      );
}

/// 맵에 위치 전달용 클래스
class MapFocusTarget {
  const MapFocusTarget({this.lat, this.lng, this.reportId, this.gridId});
  final double? lat;
  final double? lng;
  final int? reportId;
  final int? gridId;
}

class MyReport {
  const MyReport({
    required this.id,
    this.type,
    this.description,
    this.lat,
    this.lng,
    this.imgUrl,
    this.createdAt,
    this.expireAt,
  });

  final Object id;
  final String? type;
  final String? description;
  final double? lat;
  final double? lng;
  final String? imgUrl;
  final String? createdAt;
  final String? expireAt;

  factory MyReport.fromJson(Map<String, dynamic> j) => MyReport(
        id: j['id'] ?? 0,
        type: j['type'] as String?,
        description: j['description'] as String?,
        lat: _asDouble(j['lat']),
        lng: _asDouble(j['lng']),
        imgUrl: j['img_url'] as String?,
        createdAt: j['created_at']?.toString(),
        expireAt: j['expire_at']?.toString(),
      );
}

class MyFeedback {
  const MyFeedback({
    required this.id,
    this.comment,
    this.safetyFeeling,
    this.imgUrl,
    this.createdAt,
    this.gridId,
    this.tags = const [],
  });

  final int id;
  final String? comment;
  final String? safetyFeeling;
  final String? imgUrl;
  final String? createdAt;
  final Object? gridId;
  final List<String> tags;

  factory MyFeedback.fromJson(Map<String, dynamic> j) {
    final tagsRaw = j['tags'] as List? ?? [];
    return MyFeedback(
      id: _asInt(j['id']) ?? 0,
      comment: j['comment'] as String?,
      safetyFeeling: j['safety_feeling'] as String?,
      imgUrl: j['img_url'] as String?,
      createdAt: j['created_at']?.toString(),
      gridId: j['grid_id'],
      tags: tagsRaw.map((e) {
        if (e is Map) return e['name']?.toString() ?? '';
        return e.toString();
      }).where((s) => s.isNotEmpty).toList(),
    );
  }
}

/// GET /feedbacks/tags
class FeedbackTag {
  const FeedbackTag({required this.id, required this.name});
  final int id;
  final String name;

  factory FeedbackTag.fromJson(Map<String, dynamic> j) => FeedbackTag(
        id: _asInt(j['id']) ?? 0,
        name: j['name']?.toString() ?? '',
      );
}

