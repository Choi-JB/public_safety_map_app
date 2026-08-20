import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo/geo_utils.dart';
import '../data/models/models.dart';
import 'nearby_report_alert.dart';

/// FCM 제보 알림을 내 위치 [NearbyReportAlert.radiusM] 안으로만 허용.
class FcmReportProximity {
  FcmReportProximity._();

  static Future<bool> isWithinRadius(RemoteMessage message) async {
    final report = ReportItem.fromFcmData(message.data);
    if (report == null) return false;
    return isReportWithinRadius(report);
  }

  /// GPS를 못 읽으면 서버가 보낸 푸시를 막지 않는다.
  static Future<bool> isReportWithinRadius(ReportItem report) async {
    if (!isValidLatLng(report.lat, report.lng)) return false;
    final me = await _myPosition();
    if (me == null) return true;
    final m = Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      report.lat!,
      report.lng!,
    );
    return m <= NearbyReportAlert.radiusM;
  }

  /// 내 위치~제보 거리(m). GPS 없으면 null.
  static Future<double?> distanceToReportMeters(ReportItem report) async {
    if (!isValidLatLng(report.lat, report.lng)) return null;
    final me = await _myPosition();
    if (me == null) return null;
    return Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      report.lat!,
      report.lng!,
    );
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
}
