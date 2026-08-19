import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/static_data_sync_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    final sync = context.read<StaticDataSyncService>();
    sync.addListener(_checkDone);
    // main()에서 이미 동기화가 끝나 있었을 수 있음 — addListener는 이후 변화만 잡으므로
    // 첫 프레임 이후 현재 상태를 한 번 직접 확인한다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDone());
  }

  void _checkDone() {
    if (_navigated || !mounted) return;
    final phase = context.read<StaticDataSyncService>().status.phase;
    if (phase == SyncPhase.upToDate ||
        phase == SyncPhase.done ||
        phase == SyncPhase.failed) {
      _goMap();
    }
  }

  void _goMap() {
    if (_navigated) return;
    _navigated = true; // 건너뛰어도 동기화는 백그라운드에서 계속 진행됨
    context.go('/map');
  }

  @override
  void dispose() {
    context.read<StaticDataSyncService>().removeListener(_checkDone);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<StaticDataSyncService>().status;
    final isSyncing = status.phase == SyncPhase.syncing;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'android/app/src/main/res/drawable/public_safaty_map_splash_1440x2560.png',
            fit: BoxFit.cover,
          ),
          Align(
            alignment: const Alignment(0, 0.78),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: MapUiColors.accent,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _statusText(status),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (isSyncing) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _goMap,
                    child: const Text('건너뛰기'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(StaticDataSyncStatus s) {
    switch (s.phase) {
      case SyncPhase.checkingVersion:
        return '최신 정보 확인 중...';
      case SyncPhase.syncing:
        final label = s.currentType == 'infra' ? '인프라' : '격자';
        return s.currentType == 'infra' && s.receivedCount > 0
            ? '$label 데이터 받는 중... (${s.receivedCount}건)'
            : '$label 데이터 받는 중...';
      case SyncPhase.upToDate:
      case SyncPhase.done:
      case SyncPhase.failed:
        return '이동 중...';
    }
  }
}
