import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
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
import 'providers/auth_provider.dart';
import 'providers/map_provider.dart';
import 'services/nearby_monitor.dart';
import 'services/nearby_report_alert.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  await api.init();

  final authRepo = AuthRepository(api);
  final mapRepo = MapRepository(api);
  final reportRepo = ReportRepository(api);
  final feedbackRepo = FeedbackRepository(api);
  final mypageRepo = MyPageRepository(api);

  final nearbyAlert = NearbyReportAlert(mapRepo);
  await nearbyAlert.init();

  final nearbyMonitor = NearbyMonitor(nearbyAlert);
  await nearbyMonitor.hydrate();

  final mapProvider = MapProvider(mapRepo, nearbyAlert: nearbyAlert);

  final auth = AuthProvider(api, authRepo);
  await auth.hydrate();

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
        ChangeNotifierProvider.value(value: nearbyMonitor),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: mapProvider),
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
    initialLocation: '/map',
    refreshListenable: widget.auth,
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupPage()),
      GoRoute(path: '/map', builder: (_, __) => const MapPage()),
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
