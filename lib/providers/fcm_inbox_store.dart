import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/models.dart';
import '../services/fcm_report_proximity.dart';

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

  /// 백그라운드 isolate에서 호출 가능. 제보(type=report)이고 400m 안일 때만 보관.
  static Future<bool> appendFromMessage(RemoteMessage message) async {
    if (message.data['type'] != 'report') return false;
    if (!await FcmReportProximity.isWithinRadius(message)) return false;
    return appendItem(fromRemoteMessage(message));
  }

  static Future<bool> appendItem(AppNotification item) async {
    if (item.id.isEmpty) return false;
    final current = await load();
    if (current.any((e) => e.id == item.id)) return true;
    final next = [item, ...current].take(maxItems).toList();
    await persist(next);
    return true;
  }

  static AppNotification fromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString();
    final titleRaw = (message.notification?.title ?? data['title'] ?? '')
        .toString()
        .trim();
    final title = titleRaw.isNotEmpty
        ? titleRaw
        : switch (type) {
            'report' => '새로운 제보가 등록되었습니다',
            'accident' || 'accident_zone' => '주변 위험구간 알림',
            _ => '알림',
          };
    final bodyRaw = (message.notification?.body ??
            data['body'] ??
            data['content'] ??
            data['message'] ??
            '')
        .toString()
        .trim();
    final sent = message.sentTime ?? DateTime.now();
    var id = (message.messageId ?? '').trim();
    if (id.isEmpty) {
      id = 'local-${sent.millisecondsSinceEpoch}-${title.hashCode}';
    }
    return AppNotification(
      id: id,
      title: title,
      body: bodyRaw.isEmpty ? null : bodyRaw,
      lat: _asDouble(data['lat'] ?? data['latitude']),
      lng: _asDouble(
        data['lng'] ?? data['lnt'] ?? data['lon'] ?? data['longitude'],
      ),
      reportId: _asInt(data['report_id'] ?? data['reportId']) ??
          (type == 'report' ? _asInt(data['id']) : null),
      gridId: _asInt(data['grid_id'] ?? data['gridId']),
      createdAt: sent.toIso8601String(),
      isRead: false,
    );
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
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
