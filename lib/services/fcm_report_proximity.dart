import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo/geo_utils.dart';
import 'nearby_report_alert.dart';

/// FCM 제보 알림을 내 위치 [NearbyReportAlert.radiusM] 안으로만 허용.
class FcmReportProximity {
  FcmReportProximity._();

  static Future<bool> isWithinRadius(RemoteMessage message) async {
    if (message.data['type'] != 'report') return false;
    final report = _reportLatLng(message);
    if (report == null) return false;

    final me = await _myPosition();
    if (me == null) return false;

    final m = Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      report.latitude,
      report.longitude,
    );
    return m <= NearbyReportAlert.radiusM;
  }

  static ({double latitude, double longitude})? _reportLatLng(
    RemoteMessage message,
  ) {
    final data = message.data;
    final lat = _asDouble(data['lat'] ?? data['latitude']);
    final lng = _asDouble(
      data['lng'] ?? data['lnt'] ?? data['lon'] ?? data['longitude'],
    );
    if (!isValidLatLng(lat, lng)) return null;
    return (latitude: lat!, longitude: lng!);
  }

  static Future<Position?> _myPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && isValidLatLng(last.latitude, last.longitude)) {
          final age = DateTime.now().difference(last.timestamp);
          if (age.abs() <= const Duration(minutes: 2)) return last;
        }
      } catch (_) {}

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (isValidLatLng(pos.latitude, pos.longitude)) return pos;
      } catch (_) {}

      final stale = await Geolocator.getLastKnownPosition();
      if (stale != null && isValidLatLng(stale.latitude, stale.longitude)) {
        return stale;
      }
    } catch (_) {}
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
