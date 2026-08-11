import 'package:latlong2/latlong.dart';

import '../core/geo/geo_utils.dart';
import '../data/models/route_models.dart';

/// 경로 폴리라인 상에서 [me]에 가장 가까운 지점까지의 누적 거리(m)
double distanceTraveledAlongRoute(List<LatLng> points, LatLng me) {
  if (points.length < 2) return 0;
  var bestDist = double.infinity;
  var bestAlong = 0.0;
  var along = 0.0;

  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final segM =
        distKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;
    if (segM <= 0) continue;

    final t = _projectT(me, a, b);
    final proj = LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
    final d = distKm(me.latitude, me.longitude, proj.latitude, proj.longitude) *
        1000;
    if (d < bestDist) {
      bestDist = d;
      bestAlong = along + segM * t;
    }
    along += segM;
  }
  return bestAlong.clamp(0.0, along);
}

double _projectT(LatLng p, LatLng a, LatLng b) {
  final dx = b.longitude - a.longitude;
  final dy = b.latitude - a.latitude;
  final len2 = dx * dx + dy * dy;
  if (len2 <= 0) return 0;
  final t =
      ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
          len2;
  return t.clamp(0.0, 1.0);
}

RouteStep? nextGuideStep({
  required List<RouteStep> steps,
  required double traveledM,
  double lookaheadM = 12,
}) {
  if (steps.isEmpty) return null;
  for (final s in steps) {
    if (s.alongRouteM >= traveledM + lookaheadM) return s;
  }
  return steps.last;
}
