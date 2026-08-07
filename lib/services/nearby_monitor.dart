import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/geo/geo_utils.dart';
import 'nearby_report_alert.dart';

/// 백그라운드 포함 400m 주변 제보 감시 ON/OFF.
///
/// Android: Geolocator Foreground Service 로 앱 백그라운드에서도 위치 수신.
/// 설정값은 SharedPreferences 에 저장 (나중 마이페이지 이전 가능).
class NearbyMonitor extends ChangeNotifier {
  NearbyMonitor(this._alert);

  static const String prefEnabledKey = 'nearby_monitor_enabled';

  final NearbyReportAlert _alert;

  bool _enabled = false;
  bool _busy = false;
  StreamSubscription<Position>? _posSub;
  Timer? _timer;
  LatLng? _lastPos;

  bool get enabled => _enabled;
  bool get busy => _busy;

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final want = prefs.getBool(prefEnabledKey) ?? false;
    if (!want) {
      _enabled = false;
      notifyListeners();
      return;
    }
    final err = await start(persist: false);
    if (err != null) {
      // 권한 등으로 재시작 실패 → OFF 유지
      _enabled = false;
      await prefs.setBool(prefEnabledKey, false);
      notifyListeners();
    }
  }

  /// 토글. 실패 시 사용자에게 보여줄 메시지, 성공 시 null.
  Future<String?> toggle() async {
    if (_busy) return '처리 중입니다';
    if (_enabled) {
      await stop();
      return null;
    }
    return start(persist: true);
  }

  /// 감시 시작. [persist] true 이면 설정을 저장.
  Future<String?> start({bool persist = true}) async {
    if (_busy) return '처리 중입니다';
    _busy = true;
    notifyListeners();
    try {
      final permErr = await _ensurePermissions();
      if (permErr != null) return permErr;

      await _posSub?.cancel();
      _timer?.cancel();

      // 즉시 1회
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
        final p = tryLatLng(pos.latitude, pos.longitude);
        if (p != null) {
          _lastPos = p;
          unawaited(_alert.checkNear(p, force: true));
        }
      } catch (_) {
        // 스트림으로 이어감
      }

      final settings = _locationSettings();
      _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) {
          final p = tryLatLng(pos.latitude, pos.longitude);
          if (p == null) return;
          _lastPos = p;
          unawaited(_alert.checkNear(p));
        },
        onError: (_) {},
      );

      _timer = Timer.periodic(const Duration(seconds: 60), (_) {
        final p = _lastPos;
        if (p == null) return;
        unawaited(_alert.checkNear(p, force: true));
      });

      _enabled = true;
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(prefEnabledKey, true);
      }
      return null;
    } catch (e) {
      await _teardownStreams();
      _enabled = false;
      return '주변 감시 시작에 실패했습니다';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> stop({bool persist = true}) async {
    _busy = true;
    notifyListeners();
    try {
      await _teardownStreams();
      _enabled = false;
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(prefEnabledKey, false);
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _teardownStreams() async {
    _timer?.cancel();
    _timer = null;
    await _posSub?.cancel();
    _posSub = null;
  }

  LocationSettings _locationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      );
    }
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '주변 안전 감시 중',
          notificationText: '400m 안 제보·위험구간을 확인합니다',
          notificationChannelName: '주변 안전 감시',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 25,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25,
    );
  }

  Future<String?> _ensurePermissions() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return '위치 서비스를 켜 주세요';

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return '위치 권한이 필요합니다';
    }
    if (perm == LocationPermission.deniedForever) {
      return '설정에서 위치 권한을 허용해 주세요';
    }
    return null;
  }

  @override
  void dispose() {
    unawaited(_teardownStreams());
    super.dispose();
  }
}
