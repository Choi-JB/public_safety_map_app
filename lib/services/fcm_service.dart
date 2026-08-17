import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/network/api_client.dart';
import '../firebase_options.dart'; // flutterfire configure 후 생김

import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class FcmService {
  ApiClient? _api;
  FlutterLocalNotificationsPlugin? _plugin;

  static const _channelId = 'fcm_push';
  static const _channelName = '서버 알림';
  static const _notifId = 80001;

  Future<void> init({
    required ApiClient api,
    required FlutterLocalNotificationsPlugin localNotifications,
  }) async {
    _api = api; // 반드시 저장
    _plugin = localNotifications;

    final androidImpl = _plugin!
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
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

    // 토큰 갱신 구독
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _registerToken(token); // 인자 1개만
    });

    // 앱 시작 시 현재 토큰도 한 번 시도 (로그인 전이면 내부에서 return)
    // final token = await FirebaseMessaging.instance.getToken();
    // if (token != null) await _registerToken(token);
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
      await _api!.delete('/notification/아직없음');
    } catch (_) {}
  }

  /// 토큰 등록 (내부에서 호출)
  Future<void> _registerToken(String token) async {
    final api = _api;
    if (api == null) return;
    final accessToken = await api.getAccessToken();
    if (accessToken == null) return;
    try {
      await api.post(
        '/notification/set-token',
        body: {
          'fcmToken': token,
          'device_type': Platform.isAndroid ? 'android' : 'ios',
        },
      );
    } catch (e) {
      print('FCM Token 등록 실패: $e');
    }
  }

  /// 포그라운드 수신
  void _handleForeground(RemoteMessage message) async {
    final plugin = _plugin;
    if (plugin == null) return;

    final data = message.data;
    // 예: { "type": "report", "reportId": "123" }
    //final type = data['type'];

    // 백엔드 type 값이 다르면 여기가 실행 안 됨. 일단 로그로 확인

    debugPrint('FCM data=${message.data}');
debugPrint('FCM notif=${message.notification?.title} / ${message.notification?.body}');

  
    if (data.containsKey('report_id')) {
      // 기존 NearbyReportAlert 패턴처럼 알림 표시 + 탭 시 지도 이동
      final reportId = int.tryParse('${message.data['report_id'] ?? ''}');
  final title = message.notification?.title ?? '새로운 제보가 등록되었습니다';
  final body = message.notification?.body ?? '지도를 확인해 보세요';
  await plugin.show(
    id: reportId != null ? 10000 + (reportId.abs() % 1000000) : _notifId,
    title: title,
    body: body,
    payload: reportId != null ? 'report:$reportId' : null,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: '새로운 제보 등 서버 푸시',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
    }
  }

  /// 알림 탭 시 화면 이동
  void _handleTap(RemoteMessage message) {
    // 9단계에서 알림 탭 시 화면 이동
  }
}
