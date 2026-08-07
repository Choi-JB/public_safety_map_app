import 'package:dio/dio.dart';

import '../config/env.dart';
import 'geo_utils.dart';

/// 행정구역 코드 (공단/사고다발 API용). 웹 regionCodeToSiDoGuGun 과 동일.
({String siDo, String guGun})? regionCodeToSiDoGuGun(String code) {
  final digits = code.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 5) return null;
  final siDo = digits.substring(0, 2);
  final guGun = digits.substring(2, 5);
  if (!RegExp(r'^\d{2}$').hasMatch(siDo)) return null;
  return (siDo: siDo, guGun: guGun);
}

/// 카카오 REST 좌표→행정구역 (웹 coord2RegionCode 대응).
Future<({String siDo, String guGun})?> coordToSiDoGuGun({
  required double lat,
  required double lng,
}) async {
  if (!isValidLatLng(lat, lng)) return null;
  final key = Env.kakaoRestApiKey.trim();
  if (key.isEmpty) return null;

  try {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final res = await dio.get<Map<String, dynamic>>(
      'https://dapi.kakao.com/v2/local/geo/coord2regioncode.json',
      queryParameters: {
        'x': lng,
        'y': lat,
      },
      options: Options(
        headers: {'Authorization': 'KakaoAK $key'},
      ),
    );

    final docs = res.data?['documents'];
    if (docs is! List || docs.isEmpty) return null;

    Map<String, dynamic>? preferred;
    for (final raw in docs) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['region_type'] == 'B') {
        preferred = m;
        break;
      }
      preferred ??= m;
    }
    if (preferred == null) return null;
    final code = preferred['code']?.toString();
    if (code == null || code.isEmpty) return null;
    return regionCodeToSiDoGuGun(code);
  } catch (_) {
    return null;
  }
}
