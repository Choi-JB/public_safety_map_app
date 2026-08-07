import '../../core/network/api_client.dart';
import '../models/models.dart';

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<({AuthUser user, String? accessToken})> login({
    required String email,
    required String password,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    final token = data['access_token'] as String?;
    if (token != null) {
      await _api.setAccessToken(token);
    }
    return (user: user, accessToken: token);
  }

  Future<void> register({
    required String email,
    required String password,
    required String nickname,
  }) async {
    await _api.post<dynamic>(
      '/auth/register',
      body: {
        'email': email,
        'password': password,
        'nickname': nickname,
      },
    );
  }

  Future<void> logout() async {
    try {
      await _api.post<dynamic>('/auth/logout');
    } finally {
      await _api.clearSession();
    }
  }

  Future<void> changePassword({
    required String email,
    required String password,
    required String newPassword,
  }) async {
    await _api.post<dynamic>(
      '/auth/change-pw',
      body: {
        'email': email,
        'password': password,
        'newPassword': newPassword,
      },
    );
  }
}
