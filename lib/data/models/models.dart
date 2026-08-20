import 'dart:convert';

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

bool? _asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'y' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'n' || s == 'no') return false;
  }
  return null;
}

/// FCM/JS Date·KST 벽시계 문자열 → ISO8601. 실패 시 null.
String? _normalizeDateTimeString(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  DateTime? parsed = DateTime.tryParse(s);
  if (parsed == null && !s.contains('T') && RegExp(r'^\d{4}-\d{2}-\d{2} ').hasMatch(s)) {
    parsed = DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }
  if (parsed == null) {
    final cleaned = s.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), ' ').trim();
    parsed = DateTime.tryParse(cleaned);
  }
  if (parsed == null) return null;
  return parsed.toIso8601String();
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

  GridDetail copyWith({
    List<Map<String, dynamic>>? recentFeedbacks,
    List<Map<String, dynamic>>? activeReports,
    int? feedbackCount,
  }) =>
      GridDetail(
        gridId: gridId,
        lat: lat,
        lng: lng,
        infraCount: infraCount,
        safetyGrade: safetyGrade,
        tags: tags,
        topTag: topTag,
        safetyFeelingRatio: safetyFeelingRatio,
        recentFeedbacks: recentFeedbacks ?? this.recentFeedbacks,
        activeReports: activeReports ?? this.activeReports,
        feedbackCount: feedbackCount ?? this.feedbackCount,
        participantCount: participantCount,
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
        id: _asInt(j['id']) ?? 0,
        type: j['type'] as String?,
        lat: _asDouble(j['lat'] ?? j['latitude']),
        lng: _asDouble(j['lng'] ?? j['lnt'] ?? j['lon'] ?? j['longitude']),
        description: j['description'] as String?,
        imgUrl: (j['img_url'] ?? j['imgUrl']) as String?,
        userNickname: j['user_nickname'] as String?,
        createdAt: _normalizeDateTimeString(j['created_at'] ?? j['createdAt']),
        expireAt: _normalizeDateTimeString(j['expire_at'] ?? j['expireAt']),
        isAdminPosted: j['is_admin_posted'] == true,
      );

  /// FCM data 구조:
  /// `{ type: 'report', title: '...', body: { id, type, description, img_url, lat, lng, created_at } }`
  /// Android는 body가 JSON 문자열. flatten(`body.lat`)·이중 JSON도 허용.
  static bool isFcmReportPush(Map<String, dynamic> data) {
    return data['type']?.toString().trim().toLowerCase() == 'report';
  }

  static ReportItem? fromFcmData(Map<String, dynamic> data) {
    if (!isFcmReportPush(data) && _fcmReportFields(data) == null) return null;
    final src = _fcmReportFields(data);
    if (src == null) return null;
    final id = _asInt(src['id'] ?? src['reportId'] ?? src['report_id']);
    final lat = _asDouble(src['lat'] ?? src['latitude']);
    final lng = _asDouble(
      src['lng'] ?? src['lnt'] ?? src['lon'] ?? src['longitude'],
    );
    if (id == null || lat == null || lng == null) return null;
    final rawType = src['type']?.toString().trim();
    final type =
        (rawType == null || rawType.isEmpty || rawType == 'report')
            ? null
            : rawType;
    final desc = src['description']?.toString().trim();
    final img = (src['img_url'] ?? src['imgUrl'])?.toString().trim();
    final created = src['created_at'] ?? src['createdAt'];
    final imgOk = img != null &&
            img.isNotEmpty &&
            img.toLowerCase() != 'null' &&
            img.toLowerCase() != 'undefined'
        ? img
        : null;
    return ReportItem(
      id: id,
      type: type,
      lat: lat,
      lng: lng,
      description: (desc == null || desc.isEmpty) ? null : desc,
      imgUrl: imgOk,
      createdAt: _normalizeDateTimeString(created) ??
          DateTime.now().toIso8601String(),
    );
  }

  static Map<String, dynamic>? _fcmReportFields(Map<String, dynamic> data) {
    final fromBody = _asStringKeyMap(data['body']);
    if (fromBody != null) {
      return _asStringKeyMap(fromBody['data']) ?? fromBody;
    }

    final flat = <String, dynamic>{};
    for (final e in data.entries) {
      final k = e.key.toString();
      if (k.startsWith('body.') && k.length > 5) {
        flat[k.substring(5)] = e.value;
      } else if (k.startsWith('body[') && k.endsWith(']') && k.length > 6) {
        flat[k.substring(5, k.length - 1)] = e.value;
      }
    }
    if (flat.isNotEmpty) {
      return _asStringKeyMap(flat['data']) ?? flat;
    }

    if (_asInt(data['id'] ?? data['reportId'] ?? data['report_id']) != null) {
      return data;
    }
    return null;
  }

  static Map<String, dynamic>? _asStringKeyMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      var s = v.trim();
      if (s.isEmpty || s == '[object Object]') return null;
      for (var i = 0; i < 2; i++) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
          if (decoded is String) {
            s = decoded.trim();
            continue;
          }
        } catch (_) {}
        break;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'lat': lat,
        'lng': lng,
        'description': description,
        'img_url': imgUrl,
        'user_nickname': userNickname,
        'created_at': createdAt,
        'expire_at': expireAt,
        'is_admin_posted': isAdminPosted,
      };
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

/// 기기에 저장한 FCM 알림
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.body,
    this.lat,
    this.lng,
    this.reportId,
    this.gridId,
    this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String? body;
  final double? lat;
  final double? lng;
  final int? reportId;
  final int? gridId;
  final String? createdAt;
  final bool isRead;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        body: body,
        lat: lat,
        lng: lng,
        reportId: reportId,
        gridId: gridId,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final titleRaw = (j['title'] ?? j['subject'])?.toString().trim();
    final type = j['type']?.toString();
    final title = (titleRaw != null && titleRaw.isNotEmpty)
        ? titleRaw
        : switch (type) {
            'report' => '새로운 제보가 등록되었습니다',
            'accident' || 'accident_zone' => '주변 위험구간 알림',
            _ => '알림',
          };
    final bodyRaw = (j['body'] ??
            j['content'] ??
            j['message'] ??
            j['description'])
        ?.toString()
        .trim();
    return AppNotification(
      id: '${j['id'] ?? ''}',
      title: title,
      body: (bodyRaw == null || bodyRaw.isEmpty) ? null : bodyRaw,
      lat: _asDouble(j['lat']) ?? _asDouble(j['latitude']),
      lng: _asDouble(j['lng']) ??
          _asDouble(j['lnt']) ??
          _asDouble(j['lon']) ??
          _asDouble(j['longitude']),
      reportId: _asInt(j['report_id']) ?? _asInt(j['reportId']),
      gridId: _asInt(j['grid_id']) ?? _asInt(j['gridId']),
      createdAt: (j['created_at'] ?? j['createdAt'] ?? j['sent_at'])
          ?.toString(),
      isRead: _asBool(j['is_read']) ??
          _asBool(j['isRead']) ??
          _asBool(j['read']) ??
          false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'lat': lat,
        'lng': lng,
        'report_id': reportId,
        'grid_id': gridId,
        'created_at': createdAt,
        'is_read': isRead,
      };
}

