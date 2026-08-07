/// UI 표시용 문자열 포맷
library;

/// 행사 description: 웹과 동일하게 `+` → `, `, `장소:` 이후 제거
String formatEventDescription(String? description) {
  if (description == null || description.isEmpty) return '';
  var text = description;
  final match = RegExp(r'\n?\s*장소\s*:').firstMatch(text);
  if (match != null) {
    text = text.substring(0, match.start);
  }
  return text.replaceAll('+', ', ').trim();
}
