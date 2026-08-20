import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/geo/geo_utils.dart';
import '../core/geo/region_code.dart';
import '../data/models/models.dart';
import '../data/repositories/map_repository.dart';
import '../providers/fcm_inbox_store.dart';
import 'guidance_notification.dart';

const _accidentTypeLabel = {
  'pedestrian': '보행자',
  'bicycle': '자전거',
  'motorcycle': '이륜차',
  'schoolzone': '어린이보호구역',
};

const _nearbyNotifIcon = 'ic_stat_report_warning';
const _nearbyNotifColor = Color(0xFFDC2626);

/// 내 GPS 기준 반경 [radiusM] 내 제보·(옵션) 위험구간 로컬 알림.
class NearbyReportAlert {
  NearbyReportAlert(this._repo);

  static const double radiusM = 400;
  static const String channelId = 'nearby_reports';
  static const String channelName = '주변 제보';
  static const String accidentChannelId = 'nearby_accidents';
  static const String accidentChannelName = '주변 위험구간';
  static const String groupKey = 'nearby_reports_group';
  static const String accidentGroupKey = 'nearby_accidents_group';
  static const int summaryNotificationId = 1;
  static const int accidentSummaryId = 2;
  static const Duration minCheckInterval = Duration(seconds: 12);
  static const String _prefsNotifiedKey = 'nearby_notified_report_ids';
  static const String _prefsAccidentKey = 'nearby_notified_accident_ids';
  static const String prefsGlobalNotifKey = 'app_notifications_enabled';
  static const int _maxNotifiedStored = 400;

  /// 앱 전역 알림 ON/OFF (SharedPreferences 기반)
  static Future<bool> isGlobalNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsGlobalNotifKey) ?? true;
  }

  static Future<void> setGlobalNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsGlobalNotifKey, value);
  }

  /// 400m 원 포함용 bbox 반경(~610m)
  static const double _bboxDeltaDeg = 0.0055;

  final MapRepository _repo;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get notificationsPlugin => _plugin;

  GuidanceNotification? guidanceNotification;
  FcmInboxStore? inbox;

  SharedPreferences? _prefs;

  /// 위험구간 칩 ON 일 때만 다발 알림 검사
  bool accidentAlertsEnabled = false;

  /// 주변알림 마스터. false면 앱 전·후경 모두 checkNear 스킵
  bool alertsMasterEnabled = false;

  final Set<int> _trayIds = {};
  final Set<int> _notifiedIds = {};
  Set<int> _lastSummaryIds = {};
  final Map<int, ReportItem> _reportCache = {};

  final Set<String> _accidentTrayIds = {};
  final Set<String> _accidentNotifiedIds = {};
  Set<String> _lastAccidentSummaryIds = {};
  final Map<String, AccidentZoneItem> _accidentCache = {};
  String? _accidentRegionKey;
  List<AccidentZoneItem> _accidentRegionCache = [];

  final StreamController<int> _openReportCtrl =
      StreamController<int>.broadcast();
  final StreamController<AccidentZoneItem> _openAccidentCtrl =
      StreamController<AccidentZoneItem>.broadcast();

  Stream<int> get openReportStream => _openReportCtrl.stream;
  Stream<AccidentZoneItem> get openAccidentStream => _openAccidentCtrl.stream;

  int? _pendingOpenReportId;
  AccidentZoneItem? _pendingOpenAccident;

  bool _ready = false;
  bool _checking = false;
  DateTime? _lastCheck;

  Future<void> init({GuidanceNotification? guidance}) async {
    guidanceNotification = guidance;
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs?.getStringList(_prefsNotifiedKey) ?? const [];
    for (final s in saved) {
      final id = int.tryParse(s);
      if (id != null) _notifiedIds.add(id);
    }
    final aSaved = _prefs?.getStringList(_prefsAccidentKey) ?? const [];
    _accidentNotifiedIds.addAll(aSaved);

    const android = AndroidInitializationSettings(_nearbyNotifIcon);
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: '내 위치 반경 400m 내 제보 알림',
        importance: Importance.high,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        accidentChannelId,
        accidentChannelName,
        description: '내 위치 반경 400m 내 사고다발·위험구간 알림',
        importance: Importance.high,
      ),
    );
    await androidImpl?.requestNotificationsPermission();

    if (guidance != null) {
      await guidance.attach(_plugin);
    }

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final resp = launch!.notificationResponse;
      if (resp != null &&
          guidanceNotification?.handleResponse(resp) == true) {
        // 안내 종료 액션으로 기동
      } else {
        _handlePayload(resp?.payload);
      }
    }

    _ready = true;
  }

  /// 위험구간 표시 ON/OFF 와 동기화. OFF 시 상태바 다발 알림 정리.
  Future<void> setAccidentAlertsEnabled(bool enabled) async {
    accidentAlertsEnabled = enabled;
    if (!enabled) {
      for (final id in _accidentTrayIds.toList()) {
        await _plugin.cancel(id: _accidentNotifId(id));
      }
      _accidentTrayIds.clear();
      if (_lastAccidentSummaryIds.isNotEmpty) {
        await _plugin.cancel(id: accidentSummaryId);
        _lastAccidentSummaryIds = {};
      }
    }
  }

  /// 주변알림(NearbyMonitor) ON/OFF. OFF 시 상태바 제보·다발 알림 정리.
  Future<void> setAlertsMasterEnabled(bool enabled) async {
    alertsMasterEnabled = enabled;
    if (!enabled) {
      await clearAllTrayNotifications();
    }
  }

  Future<void> clearAllTrayNotifications() async {
    for (final id in _trayIds.toList()) {
      await _plugin.cancel(id: _childNotificationId(id));
    }
    _trayIds.clear();
    if (_lastSummaryIds.isNotEmpty) {
      await _plugin.cancel(id: summaryNotificationId);
      _lastSummaryIds = {};
    }

    for (final id in _accidentTrayIds.toList()) {
      await _plugin.cancel(id: _accidentNotifId(id));
    }
    _accidentTrayIds.clear();
    if (_lastAccidentSummaryIds.isNotEmpty) {
      await _plugin.cancel(id: accidentSummaryId);
      _lastAccidentSummaryIds = {};
    }
  }

  Future<void> _persistNotified() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    var list = _notifiedIds.map((e) => e.toString()).toList();
    if (list.length > _maxNotifiedStored) {
      list = list.sublist(list.length - _maxNotifiedStored);
      _notifiedIds
        ..clear()
        ..addAll(list.map(int.parse));
    }
    await prefs.setStringList(_prefsNotifiedKey, list);
  }

  Future<void> _persistAccidentNotified() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    var list = _accidentNotifiedIds.toList();
    if (list.length > _maxNotifiedStored) {
      list = list.sublist(list.length - _maxNotifiedStored);
      _accidentNotifiedIds
        ..clear()
        ..addAll(list);
    }
    await prefs.setStringList(_prefsAccidentKey, list);
  }

  ReportItem? cachedReport(int id) => _reportCache[id];

  void cacheReport(ReportItem report) {
    _reportCache[report.id] = report;
  }

  /// FCM 등으로 이미 알림을 띄운 제보 — 주변 감시가 같은 id로 재알림하지 않음.
  Future<void> markReportNotified(int reportId) async {
    if (!_notifiedIds.add(reportId)) return;
    await _persistNotified();
  }

  /// 백그라운드 isolate용. prefs만 갱신. checkNear 시작 시 메모리와 병합한다.
  static Future<void> markReportNotifiedPersist(int reportId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = List<String>.from(
        prefs.getStringList(_prefsNotifiedKey) ?? const [],
      );
      final idStr = reportId.toString();
      if (list.contains(idStr)) return;
      list.add(idStr);
      final trimmed = list.length > _maxNotifiedStored
          ? list.sublist(list.length - _maxNotifiedStored)
          : list;
      await prefs.setStringList(_prefsNotifiedKey, trimmed);
    } catch (_) {}
  }

  Future<void> _mergeNotifiedFromPrefs() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.reload();
      final saved = prefs.getStringList(_prefsNotifiedKey) ?? const [];
      for (final s in saved) {
        final id = int.tryParse(s);
        if (id != null) _notifiedIds.add(id);
      }
    } catch (_) {}
  }

  AccidentZoneItem? cachedAccident(String id) => _accidentCache[id];

  int? takePendingOpenReportId() {
    final id = _pendingOpenReportId;
    _pendingOpenReportId = null;
    return id;
  }

  AccidentZoneItem? takePendingOpenAccident() {
    final z = _pendingOpenAccident;
    _pendingOpenAccident = null;
    return z;
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (guidanceNotification?.handleResponse(response) == true) return;
    _handlePayload(response.payload);
  }

  void _handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith('report:')) {
      final id = int.tryParse(payload.substring('report:'.length));
      if (id == null) return;
      _pendingOpenReportId = id;
      if (!_openReportCtrl.isClosed) _openReportCtrl.add(id);
      return;
    }
    if (payload.startsWith('accident:')) {
      final body = payload.substring('accident:'.length);
      // id|lat|lng|type|name  (앱 종료 후 탭 시 캐시 없어도 이동 가능)
      final parts = body.split('|');
      if (parts.isEmpty || parts[0].isEmpty) return;
      final id = parts[0];
      var z = _accidentCache[id];
      if (z == null && parts.length >= 4) {
        final lat = double.tryParse(parts[1]);
        final lng = double.tryParse(parts[2]);
        final type = parts[3];
        final name = parts.length > 4 ? parts.sublist(4).join('|') : '';
        z = AccidentZoneItem(
          id: id,
          type: type,
          name: name,
          path: const [],
          lat: lat,
          lng: lng,
        );
      }
      if (z == null) return;
      _accidentCache[id] = z;
      _pendingOpenAccident = z;
      if (!_openAccidentCtrl.isClosed) _openAccidentCtrl.add(z);
    }
  }

  static String reportPayload(int id) => 'report:$id';
  static String accidentPayload(AccidentZoneItem z) {
    final lat = z.lat ??
        (z.path.isNotEmpty ? z.path.first.lat : null);
    final lng = z.lng ??
        (z.path.isNotEmpty ? z.path.first.lng : null);
    // | 은 이름 내에 드물게 있을 수 있어 뒤쪽 join
    return 'accident:${z.id}|${lat ?? ''}|${lng ?? ''}|${z.type}|${z.name}';
  }
  static const String nearbyPayload = 'nearby';

  int _childNotificationId(int reportId) => 10000 + (reportId.abs() % 1000000);

  int _accidentNotifId(String id) =>
      30000 + (id.hashCode.abs() % 100000);

  Future<void> checkNear(LatLng me, {bool force = false}) async {
    if (!alertsMasterEnabled) return;
    if (!await isGlobalNotificationsEnabled()) return;
    if (!_ready) return;
    if (!isValidLatLng(me.latitude, me.longitude)) return;

    final now = DateTime.now();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < minCheckInterval) {
      return;
    }
    if (_checking) return;
    _checking = true;
    _lastCheck = now;

    try {
      await _mergeNotifiedFromPrefs();
      await _checkReports(me);
      if (accidentAlertsEnabled) {
        await _checkAccidents(me);
      }
    } catch (_) {
      // ignore
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkReports(LatLng me) async {
    final list = await _repo.fetchReports(
      swLat: me.latitude - _bboxDeltaDeg,
      swLng: me.longitude - _bboxDeltaDeg,
      neLat: me.latitude + _bboxDeltaDeg,
      neLng: me.longitude + _bboxDeltaDeg,
    );

    final inRadius = <_NearReport>[];
    for (final r in list) {
      final lat = r.lat;
      final lng = r.lng;
      if (!isValidLatLng(lat, lng)) continue;
      final m = Geolocator.distanceBetween(
        me.latitude,
        me.longitude,
        lat!,
        lng!,
      );
      if (m <= radiusM) {
        inRadius.add(_NearReport(r, m));
        _reportCache[r.id] = r;
      }
    }

    inRadius.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    final currentIds = inRadius.map((e) => e.report.id).toSet();

    var compositionChanged = false;

    final left = _trayIds.difference(currentIds);
    for (final id in left) {
      await _plugin.cancel(id: _childNotificationId(id));
      _trayIds.remove(id);
      compositionChanged = true;
    }

    for (final item in inRadius) {
      final id = item.report.id;
      if (_notifiedIds.contains(id)) continue;
      await _showReportIndividual(item);
      _notifiedIds.add(id);
      _trayIds.add(id);
      compositionChanged = true;
    }
    if (compositionChanged) unawaited(_persistNotified());

    if (_trayIds.isEmpty) {
      if (_lastSummaryIds.isNotEmpty) {
        await _plugin.cancel(id: summaryNotificationId);
        _lastSummaryIds = {};
      }
    } else if (compositionChanged || !_setEquals(_lastSummaryIds, _trayIds)) {
      final active =
          inRadius.where((e) => _trayIds.contains(e.report.id)).toList();
      await _showReportSummary(active);
      _lastSummaryIds = Set<int>.from(_trayIds);
    }
  }

  Future<void> _checkAccidents(LatLng me) async {
    final region = await coordToSiDoGuGun(lat: me.latitude, lng: me.longitude);
    if (region == null) return;

    final regionKey = '${region.siDo}|${region.guGun}';
    if (_accidentRegionKey != regionKey) {
      final list = await _repo.fetchAccidentZones(
        siDo: region.siDo,
        guGun: region.guGun,
      );
      _accidentRegionCache = list;
      _accidentRegionKey = regionKey;
    }

    final inRadius = <_NearAccident>[];
    for (final z in _accidentRegionCache) {
      final d = _distanceToZone(me, z);
      if (d == null || d > radiusM) continue;
      final clean = _withValidPath(z);
      if (clean == null) continue;
      inRadius.add(_NearAccident(clean, d));
      _accidentCache[clean.id] = clean;
    }
    inRadius.sort((a, b) => a.distanceM.compareTo(b.distanceM));

    final currentIds = inRadius.map((e) => e.zone.id).toSet();
    var compositionChanged = false;

    final left = _accidentTrayIds.difference(currentIds);
    for (final id in left) {
      await _plugin.cancel(id: _accidentNotifId(id));
      _accidentTrayIds.remove(id);
      compositionChanged = true;
    }

    for (final item in inRadius) {
      final id = item.zone.id;
      if (_accidentNotifiedIds.contains(id)) continue;
      await _showAccidentIndividual(item);
      _accidentNotifiedIds.add(id);
      _accidentTrayIds.add(id);
      compositionChanged = true;
    }
    if (compositionChanged) unawaited(_persistAccidentNotified());

    if (_accidentTrayIds.isEmpty) {
      if (_lastAccidentSummaryIds.isNotEmpty) {
        await _plugin.cancel(id: accidentSummaryId);
        _lastAccidentSummaryIds = {};
      }
    } else if (compositionChanged ||
        !_setEqualsStr(_lastAccidentSummaryIds, _accidentTrayIds)) {
      final active = inRadius
          .where((e) => _accidentTrayIds.contains(e.zone.id))
          .toList();
      await _showAccidentSummary(active);
      _lastAccidentSummaryIds = Set<String>.from(_accidentTrayIds);
    }
  }

  /// path 최근접 점 또는 zone 중심까지 거리(m)
  double? _distanceToZone(LatLng me, AccidentZoneItem z) {
    double? best;
    for (final p in z.path) {
      if (!isValidLatLng(p.lat, p.lng)) continue;
      final m = Geolocator.distanceBetween(
        me.latitude,
        me.longitude,
        p.lat,
        p.lng,
      );
      if (best == null || m < best) best = m;
    }
    if (best != null) return best;
    if (isValidLatLng(z.lat, z.lng)) {
      return Geolocator.distanceBetween(
        me.latitude,
        me.longitude,
        z.lat!,
        z.lng!,
      );
    }
    return null;
  }

  AccidentZoneItem? _withValidPath(AccidentZoneItem z) {
    final path = z.path.where((p) => isValidLatLng(p.lat, p.lng)).toList();
    if (path.length < 3 && !isValidLatLng(z.lat, z.lng)) return null;
    return AccidentZoneItem(
      id: z.id,
      type: z.type,
      name: z.name,
      path: path,
      yearCd: z.yearCd,
      lat: z.lat,
      lng: z.lng,
      occrrncCnt: z.occrrncCnt,
      casltCnt: z.casltCnt,
      dthDnvCnt: z.dthDnvCnt,
    );
  }

  bool _setEquals(Set<int> a, Set<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }

  bool _setEqualsStr(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }

  Future<void> _showReportIndividual(_NearReport item) async {
    final r = item.report;
    final type = formatReportAlertTitle(r);
    final body = formatReportAlertBody(r, distanceM: item.distanceM);

    await _plugin.show(
      id: _childNotificationId(r.id),
      title: type,
      body: body,
      payload: reportPayload(r.id),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: '내 위치 반경 400m 내 제보 알림',
          icon: _nearbyNotifIcon,
          color: _nearbyNotifColor,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: groupKey,
          onlyAlertOnce: true,
          styleInformation: BigTextStyleInformation(body, contentTitle: type),
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: groupKey),
      ),
    );
    await _logInbox(
      id: 'nearby-report-${r.id}',
      title: type,
      body: body,
      lat: r.lat,
      lng: r.lng,
      reportId: r.id,
    );
  }

  Future<void> _showReportSummary(List<_NearReport> active) async {
    final n = active.length;
    final lines = active.map((e) {
      final type = (e.report.type ?? '제보').trim();
      final dist = e.distanceM.round();
      final desc = (e.report.description ?? '').trim();
      if (desc.isEmpty) return '$type · 약 ${dist}m';
      return '$type · 약 ${dist}m · ${_clip(desc, 32)}';
    }).toList();

    final inbox = InboxStyleInformation(
      lines,
      contentTitle: '주변 제보 $n건',
      summaryText: '내 위치 400m 이내',
    );

    await _plugin.show(
      id: summaryNotificationId,
      title: '주변 제보',
      body: '내 위치 400m 안에 제보 $n건이 있습니다',
      payload: nearbyPayload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: '내 위치 반경 400m 내 제보 알림',
          icon: _nearbyNotifIcon,
          color: _nearbyNotifColor,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: groupKey,
          setAsGroupSummary: true,
          onlyAlertOnce: true,
          styleInformation: inbox,
        ),
        iOS: const DarwinNotificationDetails(threadIdentifier: groupKey),
      ),
    );
  }

  Future<void> _showAccidentIndividual(_NearAccident item) async {
    final z = item.zone;
    final typeLabel = _accidentTypeLabel[z.type] ?? z.type;
    final dist = item.distanceM.round();
    final name = z.name.trim().isEmpty ? '위험구간' : z.name.trim();
    final body = '약 ${dist}m · ${_clip(name, 48)}';

    await _plugin.show(
      id: _accidentNotifId(z.id),
      title: '위험구간 · $typeLabel',
      body: body,
      payload: accidentPayload(z),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          accidentChannelId,
          accidentChannelName,
          channelDescription: '내 위치 반경 400m 내 사고다발 알림',
          icon: _nearbyNotifIcon,
          color: _nearbyNotifColor,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: accidentGroupKey,
          onlyAlertOnce: true,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: '위험구간 · $typeLabel',
          ),
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: accidentGroupKey),
      ),
    );
    await _logInbox(
      id: 'nearby-accident-${z.id}',
      title: '위험구간 · $typeLabel',
      body: body,
      lat: z.lat ?? (z.path.isNotEmpty ? z.path.first.lat : null),
      lng: z.lng ?? (z.path.isNotEmpty ? z.path.first.lng : null),
    );
  }

  Future<void> _showAccidentSummary(List<_NearAccident> active) async {
    final n = active.length;
    final lines = active.map((e) {
      final typeLabel = _accidentTypeLabel[e.zone.type] ?? e.zone.type;
      final dist = e.distanceM.round();
      final name =
          e.zone.name.trim().isEmpty ? typeLabel : e.zone.name.trim();
      return '$typeLabel · 약 ${dist}m · ${_clip(name, 28)}';
    }).toList();

    final inbox = InboxStyleInformation(
      lines,
      contentTitle: '주변 위험구간 $n곳',
      summaryText: '내 위치 400m 이내',
    );

    await _plugin.show(
      id: accidentSummaryId,
      title: '주변 위험구간',
      body: '내 위치 400m 안에 위험구간 $n곳이 있습니다',
      payload: 'accident_nearby',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          accidentChannelId,
          accidentChannelName,
          channelDescription: '내 위치 반경 400m 내 사고다발 알림',
          icon: _nearbyNotifIcon,
          color: _nearbyNotifColor,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: accidentGroupKey,
          setAsGroupSummary: true,
          onlyAlertOnce: true,
          styleInformation: inbox,
        ),
        iOS: const DarwinNotificationDetails(
          threadIdentifier: accidentGroupKey,
        ),
      ),
    );
  }

  String _clip(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  /// FCM·주변 감시 공통 제보 알림 제목
  static String formatReportAlertTitle(ReportItem r) {
    final t = (r.type ?? '제보').trim();
    return t.isEmpty ? '제보' : t;
  }

  /// FCM·주변 감시 공통 제보 알림 본문 (`약 120m · 설명…`)
  static String formatReportAlertBody(ReportItem r, {double? distanceM}) {
    final desc = (r.description ?? '').trim();
    final clipped = desc.isEmpty
        ? ''
        : (desc.length <= 48 ? desc : '${desc.substring(0, 48)}…');
    if (distanceM != null) {
      final dist = '약 ${distanceM.round()}m';
      return clipped.isEmpty ? dist : '$dist · $clipped';
    }
    return clipped.isEmpty ? '주변에 새 제보가 있습니다' : clipped;
  }

  Future<void> _logInbox({
    required String id,
    required String title,
    String? body,
    double? lat,
    double? lng,
    int? reportId,
  }) async {
    final store = inbox;
    if (store == null) return;
    await store.addItem(
      AppNotification(
        id: id,
        title: title,
        body: body,
        lat: lat,
        lng: lng,
        reportId: reportId,
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  void dispose() {
    _openReportCtrl.close();
    _openAccidentCtrl.close();
  }
}

class _NearReport {
  const _NearReport(this.report, this.distanceM);
  final ReportItem report;
  final double distanceM;
}

class _NearAccident {
  const _NearAccident(this.zone, this.distanceM);
  final AccidentZoneItem zone;
  final double distanceM;
}
