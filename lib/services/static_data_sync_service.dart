import 'package:flutter/foundation.dart';

import '../core/config/env.dart';
import '../core/network/api_client.dart';
import '../data/local/static_data_local_store.dart';

class _RemoteVersion {
  const _RemoteVersion({
    required this.dataType,
    required this.version,
    required this.updatedAt,
  });

  final String dataType;
  final String version;
  final String updatedAt;
}

enum SyncPhase { checkingVersion, upToDate, syncing, done, failed }

/// 스플래시 등 UI가 구독하는 동기화 진행 상태 스냅샷.
class StaticDataSyncStatus {
  const StaticDataSyncStatus({
    this.phase = SyncPhase.checkingVersion,
    this.currentType,
    this.receivedCount = 0,
  });

  final SyncPhase phase;

  /// 지금 동기화 중인 데이터 타입 ('grid' | 'infra')
  final String? currentType;

  /// infra 페이지네이션 누적 수신 건수 (grid는 단건 요청이라 미사용)
  final int receivedCount;
}

/// 앱 부팅 시 격자/인프라 정적 데이터 버전을 확인해, 바뀐 타입만 덤프를 받아 로컬 SQLite에 반영한다.
class StaticDataSyncService extends ChangeNotifier {
  StaticDataSyncService(this._api, this._local);
  final ApiClient _api;
  final StaticDataLocalStore _local;

  bool _syncing = false;

  StaticDataSyncStatus _status = const StaticDataSyncStatus();
  StaticDataSyncStatus get status => _status;

  void _setStatus(StaticDataSyncStatus s) {
    _status = s;
    notifyListeners();
  }

  Future<void> syncIfNeeded() async {
    if (_syncing) return;
    _syncing = true;
    _setStatus(const StaticDataSyncStatus(phase: SyncPhase.checkingVersion));
    try {
      final remote = await _fetchRemoteVersions();
      final local = await _local.getVersions();

      var syncedAny = false;
      for (final entry in remote) {
        if (!Env.staticDataTypes.contains(entry.dataType)) continue;
        final localVersion = local[entry.dataType]?.version;
        if (localVersion == entry.version) {
          debugPrint('[StaticDataSync] ${entry.dataType} 최신 버전 (${entry.version})');
          continue;
        }
        debugPrint(
          '[StaticDataSync] ${entry.dataType} 버전 변경 감지: '
          '$localVersion -> ${entry.version}, 덤프 받는 중...',
        );
        _setStatus(
          StaticDataSyncStatus(
            phase: SyncPhase.syncing,
            currentType: entry.dataType,
          ),
        );
        try {
          await _syncOne(entry);
          syncedAny = true;
        } catch (e) {
          // 이 타입만 실패 — 다른 타입 동기화는 계속 진행, 다음 부팅에 재시도
          debugPrint('[StaticDataSync] ${entry.dataType} 동기화 실패, 폴백 유지: $e');
        }
      }
      _setStatus(
        StaticDataSyncStatus(phase: syncedAny ? SyncPhase.done : SyncPhase.upToDate),
      );
    } catch (e) {
      debugPrint('[StaticDataSync] 버전 확인 실패, 기존 API 폴백 유지: $e');
      _setStatus(const StaticDataSyncStatus(phase: SyncPhase.failed));
    } finally {
      _syncing = false;
    }
  }

  /// 인프라 덤프 페이지 크기. 25만 건급 응답을 한 번에 받으면 기기에서
  /// 메인 isolate가 오래 막혀 디버그 연결이 끊길 정도였음 — 커서 페이지네이션으로 분할.
  static const int _pageLimit = 2000;
  static const int _maxPages = 2000; // 안전장치: has_more 오동작 시 무한루프 방지

  /// 덤프 응답은 `/grids`, `/infrastructures` 리스트 API와 달리
  /// `{ data_type, version, updated_at, items: [...] }`로 감싸져 온다.
  /// version/updated_at은 dump 응답이 아니라 /sync/version에서 받은 값을 그대로 저장한다
  /// (infra 덤프는 자체 version 필드가 null로 내려오는 걸 확인함).
  Future<void> _syncOne(_RemoteVersion entry) async {
    if (entry.dataType == 'grid') {
      final data = await _api.get<Map<String, dynamic>>(
        Env.staticDataGridsPath,
        receiveTimeout: const Duration(minutes: 2),
      );
      final items = _extractItems(data);
      await _local.replaceGrids(
        items,
        version: entry.version,
        updatedAt: entry.updatedAt,
      );
      debugPrint('[StaticDataSync] grid 동기화 완료 (${items.length}건)');
      return;
    }

    // infra: limit/cursor 페이지네이션 — has_more가 false가 될 때까지 이어받음
    final items = <Map<String, dynamic>>[];
    int? cursor;
    for (var page = 0; page < _maxPages; page++) {
      final data = await _api.get<Map<String, dynamic>>(
        Env.staticDataInfraPath,
        query: {
          'limit': _pageLimit,
          if (cursor != null) 'cursor': cursor,
        },
        receiveTimeout: const Duration(seconds: 30),
      );
      items.addAll(_extractItems(data));
      _setStatus(
        StaticDataSyncStatus(
          phase: SyncPhase.syncing,
          currentType: 'infra',
          receivedCount: items.length,
        ),
      );
      if (data['has_more'] != true) break;
      final next = (data['next_cursor'] as num?)?.toInt();
      if (next == null) break; // has_more=true인데 next_cursor 없으면 방어적으로 중단
      cursor = next;
    }
    await _local.replaceInfrastructures(
      items,
      version: entry.version,
      updatedAt: entry.updatedAt,
    );
    debugPrint('[StaticDataSync] infra 동기화 완료 (${items.length}건)');
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> data) {
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<_RemoteVersion>> _fetchRemoteVersions() async {
    final data = await _api.get<dynamic>(Env.checkDataVersionPath);
    final list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map(
          (e) => _RemoteVersion(
            dataType: e['data_type']?.toString() ?? '',
            version: e['version']?.toString() ?? '',
            updatedAt: e['updated_at']?.toString() ?? '',
          ),
        )
        .where((e) => e.dataType.isNotEmpty && e.version.isNotEmpty)
        .toList();
  }
}
