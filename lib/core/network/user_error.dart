import 'api_exception.dart';

/// UI에 표시할 사용자용 오류 문구 (예외 타입·코드 노출 없음).
String userFacingError(Object? e, {String fallback = '요청에 실패했습니다.'}) {
  if (e is ApiException) {
    final msg = e.message.trim();
    if (msg.isNotEmpty) return msg;
    return fallback;
  }
  return fallback;
}
