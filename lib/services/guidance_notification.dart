import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/models/models.dart';
import '../data/models/route_models.dart';
import '../providers/fcm_inbox_store.dart';
import '../providers/nav_provider.dart';

/// 보행 안내 ongoing 알림 (턴 문구 + 「안내 종료」액션).
/// [FlutterLocalNotificationsPlugin] 은 NearbyReportAlert 와 공유한다.
class GuidanceNotification {
  GuidanceNotification();

  static const int notificationId = 71001;
  static const String channelId = 'nav_guidance';
  static const String channelName = '보행 안내';
  static const String stopActionId = 'nav_stop';
  static const String stopPayload = 'nav:stop';
  static const String openPayload = 'nav:open';

  FlutterLocalNotificationsPlugin? _plugin;
  FcmInboxStore? inbox;
  VoidCallback? onStopRequested;

  String? _lastTitle;
  String? _lastBody;

  Future<void> attach(FlutterLocalNotificationsPlugin plugin) async {
    _plugin = plugin;
    final androidImpl = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: '길안내 진행 상태 및 안내 종료',
        importance: Importance.low,
      ),
    );
  }

  /// 알림 액션/페이로드 처리. 처리했으면 true.
  bool handleResponse(NotificationResponse response) {
    final action = response.actionId;
    final payload = response.payload;
    if (action == stopActionId || payload == stopPayload) {
      onStopRequested?.call();
      return true;
    }
    return false;
  }

  Future<void> syncFromNav(NavProvider nav) async {
    if (!nav.guiding) {
      await clear();
      return;
    }

    final String title;
    final String body;
    final bool arrival;
    if (nav.arrived) {
      arrival = true;
      title = '목적지 주변 도착';
      body = '목적지에 거의 도착했습니다. 안내를 종료하세요.';
    } else {
      arrival = false;
      final dist = formatWalkDistance(nav.distanceToStepM);
      final step =
          (nav.currentStep?.description ?? '경로를 따라 이동하세요').trim();
      title = dist;
      body = step.isEmpty ? '경로를 따라 이동하세요' : step;
    }

    if (title == _lastTitle && body == _lastBody) return;
    final firstArrival = arrival && _lastTitle != title;
    _lastTitle = title;
    _lastBody = body;
    await _show(title: title, body: body, alertOnce: firstArrival);
    if (firstArrival) {
      await inbox?.addItem(
        AppNotification(
          id: 'nav-arrival-${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          body: body,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
    }
  }

  Future<void> _show({
    required String title,
    required String body,
    bool alertOnce = false,
  }) async {
    final plugin = _plugin;
    if (plugin == null) return;

    await plugin.show(
      id: notificationId,
      title: title,
      body: body,
      payload: openPayload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: '길안내 진행 상태 및 안내 종료',
          importance: alertOnce ? Importance.high : Importance.low,
          priority: Priority.high,
          ongoing: true,
          onlyAlertOnce: true,
          playSound: alertOnce,
          enableVibration: alertOnce,
          category: AndroidNotificationCategory.navigation,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              stopActionId,
              '안내 종료',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: '보행 안내',
          ),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: alertOnce,
          presentBadge: false,
        ),
      ),
    );
  }

  Future<void> clear() async {
    _lastTitle = null;
    _lastBody = null;
    final plugin = _plugin;
    if (plugin == null) return;
    await plugin.cancel(id: notificationId);
  }
}
