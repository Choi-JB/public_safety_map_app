import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/geo_utils.dart';
import '../data/models/models.dart';

/// 출발–도착 bbox(+여유) 안에서 경유 후보를 고른다.
/// TMAP 직행만으로는 경로가 1개일 때, 경유로 대안을 만들기 위함.
class ViaCandidatePicker {
  ViaCandidatePicker._();

  static const int maxVias = 3;
  static const double bboxPadFactor = 0.25;
  static const double minAwayFromEndsM = 100;
  static const double minViaSpacingM = 120;

  /// [cctvs] 없이도 좌·우 오프셋 경유는 만들 수 있다.
  static List<LatLng> pick({
    required LatLng origin,
    required LatLng destination,
    List<InfrastructureItem> cctvs = const [],
  }) {
    if (!isValidLatLng(origin.latitude, origin.longitude) ||
        !isValidLatLng(destination.latitude, destination.longitude)) {
      return const [];
    }

    final box = _paddedBBox(origin, destination, bboxPadFactor);
    final out = <LatLng>[];

    // 1) 직선 기준 좌·우 살짝 벗어난 점 (경로 다양화)
    for (final p in _sideOffsets(origin, destination)) {
      if (_accept(p, origin, destination, box, out)) out.add(p);
      if (out.length >= maxVias) return out;
    }

    // 2) bbox 안 CCTV — 직선에서 떨어진 순
    final ranked = <({LatLng p, double off})>[];
    for (final c in cctvs) {
      final p = tryLatLng(c.lat, c.lng);
      if (p == null) continue;
      if (!_inBox(p, box)) continue;
      if (_distM(origin, p) < minAwayFromEndsM) continue;
      if (_distM(destination, p) < minAwayFromEndsM) continue;
      final off = _distToSegmentM(p, origin, destination);
      if (off < 40) continue; // 거의 직선 위면 스킵
      ranked.add((p: p, off: off));
    }
    ranked.sort((a, b) => b.off.compareTo(a.off));

    for (final r in ranked) {
      if (_accept(r.p, origin, destination, box, out)) out.add(r.p);
      if (out.length >= maxVias) break;
    }

    return out;
  }

  static bool _accept(
    LatLng p,
    LatLng origin,
    LatLng destination,
    ({double minLat, double maxLat, double minLng, double maxLng}) box,
    List<LatLng> existing,
  ) {
    if (!_inBox(p, box)) return false;
    if (_distM(origin, p) < minAwayFromEndsM) return false;
    if (_distM(destination, p) < minAwayFromEndsM) return false;
    for (final e in existing) {
      if (_distM(e, p) < minViaSpacingM) return false;
    }
    return true;
  }

  static List<LatLng> _sideOffsets(LatLng o, LatLng d) {
    final midLat = (o.latitude + d.latitude) / 2;
    final midLng = (o.longitude + d.longitude) / 2;
    var dx = d.longitude - o.longitude;
    var dy = d.latitude - o.latitude;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-8) return const [];

    // 구간 길이의 ~12%, 약 80~350m 상당으로 클램프
    final segM = _distM(o, d);
    final offsetM = (segM * 0.12).clamp(80.0, 350.0);
    // 대략 위도 1도 ≈ 111km
    final offsetDeg = offsetM / 111000.0;

    final px = -dy / len;
    final py = dx / len;

    final a = LatLng(midLat + py * offsetDeg, midLng + px * offsetDeg);
    final b = LatLng(midLat - py * offsetDeg, midLng - px * offsetDeg);
    return [
      if (isValidLatLng(a.latitude, a.longitude)) a,
      if (isValidLatLng(b.latitude, b.longitude)) b,
    ];
  }

  static ({double minLat, double maxLat, double minLng, double maxLng})
      _paddedBBox(LatLng o, LatLng d, double padFactor) {
    var minLat = math.min(o.latitude, d.latitude);
    var maxLat = math.max(o.latitude, d.latitude);
    var minLng = math.min(o.longitude, d.longitude);
    var maxLng = math.max(o.longitude, d.longitude);
    final dLat = (maxLat - minLat).abs();
    final dLng = (maxLng - minLng).abs();
    final padLat = math.max(dLat * padFactor, 0.003);
    final padLng = math.max(dLng * padFactor, 0.003);
    return (
      minLat: minLat - padLat,
      maxLat: maxLat + padLat,
      minLng: minLng - padLng,
      maxLng: maxLng + padLng,
    );
  }

  static bool _inBox(
    LatLng p,
    ({double minLat, double maxLat, double minLng, double maxLng}) box,
  ) {
    return p.latitude >= box.minLat &&
        p.latitude <= box.maxLat &&
        p.longitude >= box.minLng &&
        p.longitude <= box.maxLng;
  }

  static double _distM(LatLng a, LatLng b) =>
      distKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;

  /// 점 P와 선분 AB의 대략 거리(m)
  static double _distToSegmentM(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;
    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;
    final ab2 = abx * abx + aby * aby;
    if (ab2 < 1e-16) return _distM(p, a);
    var t = (apx * abx + apy * aby) / ab2;
    t = t.clamp(0.0, 1.0);
    final qx = ax + abx * t;
    final qy = ay + aby * t;
    return distKm(py, px, qy, qx) * 1000;
  }

  /// CCTV 조회용 중심·반경
  static ({LatLng center, int radiusM}) queryCircle(
    LatLng origin,
    LatLng destination,
  ) {
    final box = _paddedBBox(origin, destination, bboxPadFactor);
    final center = LatLng(
      (box.minLat + box.maxLat) / 2,
      (box.minLng + box.maxLng) / 2,
    );
    final radiusM = (distKm(
              box.minLat,
              box.minLng,
              box.maxLat,
              box.maxLng,
            ) *
            1000 /
            2)
        .clamp(400, 5000)
        .round();
    return (center: center, radiusM: radiusM);
  }
}
