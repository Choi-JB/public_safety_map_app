import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/network/user_error.dart';
import '../data/models/models.dart';
import '../data/repositories/auth_repository.dart';
import '../services/fcm_service.dart';
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._api, this._authRepo, this._fcm);

  final ApiClient _api;
  final AuthRepository _authRepo;
  final _storage = const FlutterSecureStorage();
  static const _userKey = 'auth_user';
  final FcmService _fcm;

  AuthUser? user;
  bool loading = false;
  String? error;
  bool hydrated = false;

  bool get isLoggedIn => user != null;

  Future<void> hydrate() async {
    final token = await _api.getAccessToken();
    final raw = await _storage.read(key: _userKey);
    if (token != null && raw != null) {
      try {
        user = AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        await _fcm.registerCurrentToken();
      } catch (_) {
        await _api.clearSession();
        await _storage.delete(key: _userKey);
      }
    }
    hydrated = true;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await _authRepo.login(email: email, password: password);
      if (result.accessToken == null && result.user.role == 'ADMIN') {
        error = '관리자 계정은 웹 관리 콘솔을 이용해 주세요.';
        await _api.clearSession();
        return false;
      }
      user = result.user;
      await _storage.write(
        key: _userKey,
        value: jsonEncode(result.user.toJson()),
      );
      await _fcm.registerCurrentToken();
      return true;
    } on ApiException catch (e) {
      error = userFacingError(e, fallback: '로그인에 실패했습니다.');
      return false;
    } catch (e) {
      error = userFacingError(e, fallback: '로그인에 실패했습니다.');
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String nickname,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _authRepo.register(
        email: email,
        password: password,
        nickname: nickname,
      );
      return true;
    } on ApiException catch (e) {
      error = userFacingError(e, fallback: '회원가입에 실패했습니다.');
      return false;
    } catch (e) {
      error = userFacingError(e, fallback: '회원가입에 실패했습니다.');
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
    await _fcm.unregisterCurrentToken();
  } catch (_) {}
  await _authRepo.logout();
  user = null;
  await _storage.delete(key: _userKey);
  notifyListeners();
  }
}
