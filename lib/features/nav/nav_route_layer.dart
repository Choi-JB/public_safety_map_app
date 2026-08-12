import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/geo/geo_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/nav_provider.dart';

/// 선택 경로 폴리라인
class NavRouteLayer extends StatelessWidget {
  const NavRouteLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    final pts = nav.selected?.points;
    if (pts == null || pts.length < 2) {
      return const SizedBox.shrink();
    }
    return PolylineLayer(
      polylines: [
        Polyline(
          points: pts,
          strokeWidth: 5,
          color: MapUiColors.accent,
          borderStrokeWidth: 2,
          borderColor: Colors.white,
        ),
      ],
    );
  }
}

/// 길찾기 출발지 핀
class NavOriginMarker extends StatelessWidget {
  const NavOriginMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    final o = nav.origin;
    if (!nav.active ||
        o == null ||
        !isValidLatLng(o.latitude, o.longitude)) {
      return const SizedBox.shrink();
    }
    return MarkerLayer(
      markers: [
        Marker(
          point: o,
          width: 40,
          height: 48,
          alignment: Alignment.topCenter,
          child: const Icon(
            Icons.location_on,
            color: Color(0xFF16A34A),
            size: 40,
            shadows: [
              Shadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 길찾기 도착지 핀
class NavDestinationMarker extends StatelessWidget {
  const NavDestinationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    final dest = nav.destination;
    if (!nav.active ||
        dest == null ||
        !isValidLatLng(dest.latitude, dest.longitude)) {
      return const SizedBox.shrink();
    }
    return MarkerLayer(
      markers: [
        Marker(
          point: dest,
          width: 40,
          height: 48,
          alignment: Alignment.topCenter,
          child: const Icon(
            Icons.location_on,
            color: Color(0xFFDC2626),
            size: 40,
            shadows: [
              Shadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
