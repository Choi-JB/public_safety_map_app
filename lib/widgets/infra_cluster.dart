import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo/geo_utils.dart';
import '../core/theme/app_theme.dart';
import '../data/models/models.dart';

/// 줌에 따른 CCTV 클러스터 셀 크기(도). null이면 개별 표시.
double? cctvClusterCellDeg(double zoom) {
  final z = safeZoom(zoom);
  if (z >= 17) return null; // 개별
  if (z >= 16) return 0.0008;
  if (z >= 15) return 0.0015;
  if (z >= 14) return 0.003;
  return 0.005;
}

/// 지도에 그릴 인프라 점 (개별 1건 또는 CCTV 클러스터)
class InfraMapPoint {
  const InfraMapPoint.single(this.item)
      : count = 1,
        point = null;

  const InfraMapPoint.cluster({
    required this.point,
    required this.count,
  }) : item = null;

  final InfrastructureItem? item;
  final LatLng? point;
  final int count;

  bool get isCluster => count > 1;

  LatLng? get latLng {
    if (point != null) return point;
    return tryLatLng(item?.lat, item?.lng);
  }
}

/// CCTV는 줌별 셀 클러스터, 나머지 타입은 개별.
List<InfraMapPoint> buildInfraMapPoints({
  required List<InfrastructureItem> items,
  required double zoom,
}) {
  final singles = <InfraMapPoint>[];
  final cctvs = <InfrastructureItem>[];

  for (final i in items) {
    if (!isValidLatLng(i.lat, i.lng)) continue;
    if (i.type == 'CCTV') {
      cctvs.add(i);
    } else {
      singles.add(InfraMapPoint.single(i));
    }
  }

  final cell = cctvClusterCellDeg(zoom);
  if (cell == null || cell <= 0) {
    singles.addAll(cctvs.map(InfraMapPoint.single));
    return singles;
  }

  final buckets = <String, List<InfrastructureItem>>{};
  for (final i in cctvs) {
    final key =
        '${(i.lat! / cell).floor()}_${(i.lng! / cell).floor()}';
    buckets.putIfAbsent(key, () => []).add(i);
  }

  for (final group in buckets.values) {
    if (group.length == 1) {
      singles.add(InfraMapPoint.single(group.first));
      continue;
    }
    var latSum = 0.0;
    var lngSum = 0.0;
    for (final g in group) {
      latSum += g.lat!;
      lngSum += g.lng!;
    }
    final n = group.length;
    singles.add(
      InfraMapPoint.cluster(
        point: LatLng(latSum / n, lngSum / n),
        count: n,
      ),
    );
  }
  return singles;
}

/// CCTV 클러스터 숫자 원
class CctvClusterBadge extends StatelessWidget {
  const CctvClusterBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    final size = count >= 20 ? 40.0 : (count >= 10 ? 36.0 : 32.0);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MapUiColors.cctv,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
