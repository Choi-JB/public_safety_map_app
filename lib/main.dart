import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'data/local/static_data_local_store.dart';
import 'data/models/models.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/feedback_repository.dart';
import 'data/repositories/map_repository.dart';
import 'data/repositories/mypage_repository.dart';
import 'data/repositories/report_repository.dart';
import 'features/auth/login_page.dart';
import 'features/auth/signup_page.dart';
import 'features/feedback/create_feedback_page.dart';
import 'features/map/map_page.dart';
import 'features/mypage/mypage_page.dart';
import 'features/report/create_report_page.dart';
import 'features/splash/splash_page.dart';
import 'providers/auth_provider.dart';
import 'providers/map_provider.dart';
import 'services/nearby_monitor.dart';
import 'services/nearby_report_alert.dart';
import 'services/guidance_notification.dart';
import 'services/static_data_sync_service.dart';
//nav
import 'data/repositories/direction_repository.dart';
import 'providers/nav_provider.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'providers/fcm_inbox_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //firebase 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final api = ApiClient();
  await api.init();

  final localStore = StaticDataLocalStore.instance;
  await localStore.init();
  final staticDataSync = StaticDataSyncService(api, localStore);
  unawaited(staticDataSync.syncIfNeeded());

  final authRepo = AuthRepository(api);
  final mapRepo = MapRepository(api, localStore: localStore);
  //nav
  final directionRepo = DirectionRepository();

  final reportRepo = ReportRepository(api);
  final feedbackRepo = FeedbackRepository(api);
  final mypageRepo = MyPageRepository(api);

  final guidanceNotif = GuidanceNotification();
  final nearbyAlert = NearbyReportAlert(mapRepo);
  await nearbyAlert.init(guidance: guidanceNotif);

  final fcmInbox = FcmInboxStore();
  await fcmInbox.start();
  nearbyAlert.inbox = fcmInbox;
  guidanceNotif.inbox = fcmInbox;

  //fcm 초기화
  final fcm = FcmService();
  await fcm.init(
    api: api,
    localNotifications: nearbyAlert.notificationsPlugin,
    inbox: fcmInbox,
  );

  final nearbyMonitor = NearbyMonitor(nearbyAlert);
  await nearbyMonitor.hydrate();

  final mapProvider = MapProvider(mapRepo, nearbyAlert: nearbyAlert);
  await mapProvider.hydrateLastPosition();

  final auth = AuthProvider(api, authRepo, fcm);
  await auth.hydrate();

  final navProvider = NavProvider(directionRepo, mapRepo);
  guidanceNotif.onStopRequested = () {
    if (navProvider.guiding) {
      navProvider.stopGuidance();
    }
  };

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: api),
        Provider.value(value: authRepo),
        Provider.value(value: mapRepo),
        Provider.value(value: reportRepo),
        Provider.value(value: feedbackRepo),
        Provider.value(value: mypageRepo),
        Provider.value(value: nearbyAlert),
        Provider.value(value: guidanceNotif),
        ChangeNotifierProvider.value(value: staticDataSync),
        ChangeNotifierProvider.value(value: fcmInbox),
        ChangeNotifierProvider.value(value: nearbyMonitor),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: mapProvider),
        ChangeNotifierProvider.value(value: navProvider),
      ],
      child: SafetyMapApp(auth: auth, nearbyAlert: nearbyAlert),
    ),
  );
}

class SafetyMapApp extends StatefulWidget {
  const SafetyMapApp({
    super.key,
    required this.auth,
    required this.nearbyAlert,
  });

  final AuthProvider auth;
  final NearbyReportAlert nearbyAlert;

  @override
  State<SafetyMapApp> createState() => _SafetyMapAppState();
}

class _SafetyMapAppState extends State<SafetyMapApp> {
  StreamSubscription<int>? _openReportSub;
  StreamSubscription<AccidentZoneItem>? _openAccidentSub;

  late final GoRouter _router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: widget.auth,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupPage()),
      GoRoute(
        path: '/map', 
        builder: (context, state){
            final extra = state.extra;
            final focus = extra is MapFocusTarget ? extra : null;
            return MapPage(focus: focus);
          },
        ),
      GoRoute(path: '/mypage', builder: (_, __) => const MyPage()),
      GoRoute(
        path: '/report/create',
        builder: (context, state) {
          final extra = state.extra;
          final pos = extra is LatLng ? extra : null;
          return CreateReportPage(initialPos: pos);
        },
      ),
      GoRoute(
        path: '/feedback/create/:gridId',
        builder: (context, state) {
          final raw = state.pathParameters['gridId'] ?? '';
          final id = int.tryParse(raw) ?? 0;
          return CreateFeedbackPage(gridId: id);
        },
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    void goMap() {
      if (_router.state.uri.path != '/map') {
        _router.go('/map');
      }
    }

    _openReportSub = widget.nearbyAlert.openReportStream.listen((_) => goMap());
    _openAccidentSub =
        widget.nearbyAlert.openAccidentStream.listen((_) => goMap());
  }

  @override
  void dispose() {
    _openReportSub?.cancel();
    _openAccidentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Public Safety Map',
      theme: buildAppTheme(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
