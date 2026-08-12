import '../data/models/route_models.dart';

/// TMAP 보행 경로 단건 응답 메모리 캐시 (일일 한도 절약).
class TmapRouteCache {
  TmapRouteCache._();
  static final TmapRouteCache instance = TmapRouteCache._();

  static const int maxEntries = 50;
  static const Duration successTtl = Duration(minutes: 15);
  static const Duration negativeTtl = Duration(minutes: 3);

  final _entries = <String, _Entry>{};
  final _order = <String>[];

  String makeKey({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    required String searchOption,
    List<String> waypointKeys = const [],
  }) {
    final w = waypointKeys.isEmpty ? '' : '|${waypointKeys.join('_')}';
    return '${_r(startLat)},${_r(startLng)}|${_r(endLat)},${_r(endLng)}|$searchOption$w';
  }

  static String waypointKey(double lat, double lng) => '${_r(lat)},${_r(lng)}';

  /// 성공 hit → route, 실패 hit → error, miss → null
  ({RouteCandidate? route, String? error})? lookup(String key) {
    final e = _entries[key];
    if (e == null) return null;
    if (DateTime.now().isAfter(e.expiresAt)) {
      _remove(key);
      return null;
    }
    if (e.error != null) return (route: null, error: e.error);
    return (route: e.route, error: null);
  }

  void putSuccess(String key, RouteCandidate route) {
    _put(key, _Entry(route: route, expiresAt: DateTime.now().add(successTtl)));
  }

  void putFailure(String key, String message, {required bool negative}) {
    final ttl = negative ? negativeTtl : successTtl;
    _put(key, _Entry(error: message, expiresAt: DateTime.now().add(ttl)));
  }

  void _put(String key, _Entry entry) {
    if (_entries.containsKey(key)) {
      _order.remove(key);
    }
    _entries[key] = entry;
    _order.add(key);
    while (_order.length > maxEntries) {
      final oldest = _order.removeAt(0);
      _entries.remove(oldest);
    }
  }

  void _remove(String key) {
    _entries.remove(key);
    _order.remove(key);
  }

  static String _r(double v) => v.toStringAsFixed(4);
}

class _Entry {
  _Entry({this.route, this.error, required this.expiresAt});

  final RouteCandidate? route;
  final String? error;
  final DateTime expiresAt;
}
