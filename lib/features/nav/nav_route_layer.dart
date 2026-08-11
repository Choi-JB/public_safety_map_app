import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/nav_provider.dart';

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