import 'env.dart';

/// BE `img_url`이 상대 경로일 때 API 베이스를 붙입니다 (웹 `API_BASE + url`과 동일).
String? resolveMediaUrl(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final base = Env.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
  final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return '$base$path';
}
