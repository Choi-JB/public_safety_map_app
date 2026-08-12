import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../config/env.dart';
import 'api_exception.dart';

/// Express BE와 동일한 envelope: { success, data | message }
class ApiClient {
  ApiClient({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      // headers: {'Content-Type': 'application/json'},
      validateStatus: (code) => 
      code != null && code < 500 && code != 401,
    ),
  );

  CookieJar? _cookieJar;
  bool _ready = false;
  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  Future<void> init() async {
    if (_ready) return;
    final dir = await getApplicationSupportDirectory();
    final cookiePath = '${dir.path}/.cookies/';
    await Directory(cookiePath).create(recursive: true);
    _cookieJar = PersistCookieJar(storage: FileStorage(cookiePath));
    dio.interceptors.add(CookieManager(_cookieJar!));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: _tokenKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          if (err.response?.statusCode == 401 &&
          !(err.requestOptions.path.contains('/auth/refresh'))) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final req = err.requestOptions;
              final token = await _storage.read(key: _tokenKey);
              if (token != null) {
                req.headers['Authorization'] = 'Bearer $token';
              }
              try {
                final clone = await dio.fetch(req);
                return handler.resolve(clone);
              } catch (_) {}
            }
          }
          handler.next(err);
        },
      ),
    );
    _ready = true;
  }

  Future<void> setAccessToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: token);
    }
  }

  Future<void> setRefreshToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _refreshTokenKey);
    } else {
      await _storage.write(key: _refreshTokenKey, value: token);
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _tokenKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> clearSession() async {
    await setAccessToken(null);
    await setRefreshToken(null);
    await _cookieJar?.deleteAll();
  }

  Future<bool> _tryRefresh() async {
    try {
      final refresh = await getRefreshToken();
      if (refresh == null || refresh.isEmpty) return false;

      final res = await dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = _unwrap<Map<String, dynamic>>(res);

      /// 엑세스 토큰 갱신
      final access = data['access_token'] as String?;
      if (access == null || access.isEmpty) return false;
      await setAccessToken(access);

      // 백엔드가 refresh도 갱신해 주면 같이 저장
      final newRefresh = data['refresh_token'] as String?;
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await setRefreshToken(newRefresh);
      }
      return true;
    } catch (_) {
      await clearSession();
      return false;
    }
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    T Function(dynamic raw)? parser,
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      path,
      queryParameters: query,
    );
    return _parse(res, parser);
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    T Function(dynamic raw)? parser,
  }) async {
    final res = await dio.post<Map<String, dynamic>>(
      path,
      data: body,
      queryParameters: query,
    );
    return _parse(res, parser);
  }

  Future<T> patch<T>(
    String path, {
    Object? body,
    T Function(dynamic raw)? parser,
  }) async {
    final res = await dio.patch<Map<String, dynamic>>(path, data: body);
    return _parse(res, parser);
  }

  Future<T> delete<T>(String path, {T Function(dynamic raw)? parser}) async {
    final res = await dio.delete<Map<String, dynamic>>(path);
    return _parse(res, parser);
  }

  /// multipart field name: image
  Future<Map<String, dynamic>> uploadImage(
    String path,
    String filePath, {
    String fieldName = 'image',
  }) async {
    final form = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(filePath),
    });

    // contentType 지정하지 말 것 — Dio가 multipart + boundary 자동 설정
    final res = await dio.post<dynamic>(path, data: form);

    final body = res.data;
    if (body is! Map) {
      throw ApiException(
        '이미지 업로드에 실패했습니다.',
        statusCode: res.statusCode,
      );
    }
    final map = Map<String, dynamic>.from(body as Map);
    if (map['success'] == false ||
        (res.statusCode != null && res.statusCode! >= 400)) {
      throw ApiException(
        (map['message'] as String?) ?? '업로드 실패',
        statusCode: res.statusCode,
      );
    }
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ApiException('이미지 업로드에 실패했습니다.');
  }

  T _parse<T>(
    Response<Map<String, dynamic>> res,
    T Function(dynamic raw)? parser,
  ) {
    final raw = _unwrap(res);
    if (parser != null) return parser(raw);
    return raw as T;
  }

  T _unwrap<T>(Response<Map<String, dynamic>> res) {
    final body = res.data;
    if (body == null) {
      throw ApiException('서버 응답이 비어 있습니다.', statusCode: res.statusCode);
    }
    final success = body['success'];
    if (success == false ||
        (res.statusCode != null && res.statusCode! >= 400)) {
      throw ApiException(
        (body['message'] as String?) ?? '요청에 실패했습니다.',
        statusCode: res.statusCode,
      );
    }
    if (body.containsKey('data')) {
      return body['data'] as T;
    }
    return body as T;
  }
}
