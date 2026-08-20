import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/network/api_client.dart';
import '../firebase_options.dart';
import '../providers/fcm_inbox_store.dart';
import 'nearby_report_alert.dart';

const _fcmChannelId = 'fcm_push';
const _fcmChannelName = '서버 알림';
const _fcmNotifId = 80001;

/// FCM 신규 제보 알림 — 테두리 삼각형 + 채워진 느낌표 (빨강 #DC2626)
const _reportPushAndroidDetails = AndroidNotificationDetails(
  _fcmChannelId,
  _fcmChannelName,
  channelDescription: '새로운 제보 등 서버 푸시',
  icon: 'ic_stat_report_warning',
  color: Color(0xFFDC2626),
  importance: Importance.high,
  priority: Priority.high,
  largeIcon: DrawableResourceAndroidBitmap('ic_notification_report_warning'),
);
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final saved = await FcmInboxStore.appendFromMessage(message);
  if (!saved) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_report_warning'),
      iOS: DarwinInitializationSettings(),
    ),
  );  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      _fcmChannelId,
      _fcmChannelName,
      description: '새로운 제보 등 서버 푸시',
      importance: Importance.high,
    ),
  );
  await _showReportNotification(plugin, message);
}

Future<void> _showReportNotification(
  FlutterLocalNotificationsPlugin plugin,
  RemoteMessage message,
) async {
  final reportId = int.tryParse(
    '${message.data['id'] ?? message.data['reportId'] ?? ''}',
  );
  final title = message.notification?.title ?? '새로운 제보가 등록되었습니다';
  final body = message.notification?.body ?? '지도를 확인해 보세요';
  await plugin.show(
    id: reportId != null ? 10000 + (reportId.abs() % 1000000) : _fcmNotifId,
    title: title,
    body: body,
    payload: reportId != null ? 'report:$reportId' : null,
    notificationDetails: const NotificationDetails(
      android: _reportPushAndroidDetails,
      iOS: DarwinNotificationDetails(),
    ),  );
}

class FcmService {
  ApiClient? _api;
  FlutterLocalNotificationsPlugin? _plugin;
  FcmInboxStore? _inbox;

  Future<void> init({
    required ApiClient api,
    required FlutterLocalNotificationsPlugin localNotifications,
    required FcmInboxStore inbox,
  }) async {
    _api = api;
    _plugin = localNotifications;
    _inbox = inbox;

    final androidImpl = _plugin!
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _fcmChannelId,
        _fcmChannelName,
        description: '새로운 제보 등 서버 푸시',
        importance: Importance.high,
      ),
    );

    await FirebaseMessaging.instance.requestPermission();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen(_handleForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleTap(initial);

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _registerToken(token);
    });
  }

  /// 로그인 직후 / hydrate 직후에 밖에서 호출
  Future<void> registerCurrentToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerToken(token);
  }

  /// 로그아웃 직후에 밖에서 호출
  Future<void> unregisterCurrentToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || _api == null) return;
    try {
      await _api!.patch(
      '/notification/unregister',
      body: {'fcmToken': token},
    );
    } catch (_) {}
  }

  Future<void> _registerToken(String token) async {
    final api = _api;
    if (api == null) return;
    final accessToken = await api.getAccessToken();
    if (accessToken == null) return;
    try {
      await api.post(
        '/notification/register',
        body: {
          'fcmToken': token,
          'device_type': Platform.isAndroid ? 'android' : 'ios',
        },
      );
    } catch (e) {
      //debugPrint('FCM Token 등록 실패: $e');
    }
  }

  void _handleForeground(RemoteMessage message) async {
    final plugin = _plugin;
    if (plugin == null) return;

    if (!await NearbyReportAlert.isGlobalNotificationsEnabled()) return;

    final type = message.data['type'] as String?;

    if (type != 'report') return;
    final saved = await _inbox?.addFromMessage(message) ?? false;
    if (!saved) return;
    await _showReportNotification(plugin, message);
  }

  void _handleTap(RemoteMessage message) {
    if (message.data['type'] != 'report') return;
    _inbox?.addFromMessage(message);
  }
}
