import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/models.dart';
import '../services/fcm_report_proximity.dart';
import '../services/nearby_report_alert.dart';

/// 앱에서 발생한 알림을 기기에 보관한다. 백그라운드 isolate에서도 동일 키로 기록한다.
class FcmInboxStore extends ChangeNotifier with WidgetsBindingObserver {
  static const prefsKey = 'fcm_inbox_v1';
  static const maxItems = 200;

  List<AppNotification> items = const [];
  bool _observing = false;

  int get unreadCount => items.where((n) => !n.isRead).length;

  Future<void> start() async {
    await hydrate();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      hydrate();
    }
  }

  Future<void> hydrate() async {
    items = await load();
    notifyListeners();
  }

  Future<bool> addFromMessage(RemoteMessage message) async {
    final saved = await appendFromMessage(message);
    if (saved) await hydrate();
    return saved;
  }

  Future<void> addItem(AppNotification item) async {
    final saved = await appendItem(item);
    if (saved) await hydrate();
  }

  Future<void> markRead(String id) async {
    if (id.isEmpty) return;
    final next = [
      for (final n in items)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
    await persist(next);
    items = next;
    notifyListeners();
  }

  Future<void> clearAll() async {
    await persist(const []);
    items = const [];
    notifyListeners();
  }

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  static Future<List<AppNotification>> load() async {
    final prefs = await _prefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .where((n) => n.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> persist(List<AppNotification> items) async {
    final prefs = await _prefs();
    await prefs.setString(
      prefsKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  /// 백그라운드 isolate에서 호출 가능. 제보 페이로드이고 400m 안(GPS 없으면 허용)일 때 보관.
  static Future<bool> appendFromMessage(RemoteMessage message) async {
    final report = ReportItem.fromFcmData(message.data);
    if (report == null) return false;
    if (!await FcmReportProximity.isReportWithinRadius(report)) return false;
    final distM = await FcmReportProximity.distanceToReportMeters(report);
    return appendItem(fromRemoteMessage(message, distanceM: distM));
  }

  static Future<bool> appendItem(AppNotification item) async {
    if (item.id.isEmpty) return false;
    final current = await load();
    if (current.any((e) => e.id == item.id)) return true;
    final next = [item, ...current].take(maxItems).toList();
    await persist(next);
    return true;
  }

  static AppNotification fromRemoteMessage(
    RemoteMessage message, {
    double? distanceM,
  }) {
    final data = message.data;
    final report = ReportItem.fromFcmData(data);
    final title = report != null
        ? NearbyReportAlert.formatReportAlertTitle(report)
        : '제보';
    final body = report != null
        ? NearbyReportAlert.formatReportAlertBody(report, distanceM: distanceM)
        : null;
    final sent = message.sentTime ?? DateTime.now();
    var id = (message.messageId ?? '').trim();
    if (id.isEmpty) {
      id = 'local-${sent.millisecondsSinceEpoch}-${title.hashCode}';
    }
    return AppNotification(
      id: id,
      title: title,
      body: body,
      lat: report?.lat,
      lng: report?.lng,
      reportId: report?.id,
      gridId: _asInt(data['grid_id'] ?? data['gridId']),
      createdAt: report?.createdAt ?? sent.toIso8601String(),
      isRead: false,
    );
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    super.dispose();
  }
}
