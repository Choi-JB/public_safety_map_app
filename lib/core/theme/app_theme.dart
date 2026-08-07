import 'package:flutter/material.dart';

/// 웹 맵(`public_safety_map_web`)과 맞춘 색 토큰
class MapUiColors {
  MapUiColors._();

  static const accent = Color(0xFF2563EB);
  static const accentSoft = Color(0xFFEFF6FF);

  static const report = Color(0xFFDC2626);
  static const reportSelectedBg = Color(0xFFFEF2F2);

  static const event = Color(0xFFEC4899);
  static const eventSelectedBg = Color(0xFFFDF2F8);

  static const me = Color(0xFF2563EB);

  static const gradeSafe = Color(0xFF22C55E);
  static const gradeNormal = Color(0xFFEAB308);
  static const gradeUnsafe = Color(0xFFEF4444);
  static const gradeDefault = Color(0xFF94A3B8);

  static const cctv = Color(0xFF0F766E);
  static const police = Color(0xFF1D4ED8);
  static const fire = Color(0xFFEA580C);
  static const store = Color(0xFF65A30D);

  /// 사고다발 타입 색 (웹 accidentColor)
  static const accidentPedestrian = Color(0xFFDC2626);
  static const accidentBicycle = Color(0xFF2563EB);
  static const accidentMotorcycle = Color(0xFF7C3AED);
  static const accidentSchoolzone = Color(0xFFEA580C);
}

/// 웹 accidentColor
Color accidentZoneColor(String? type) {
  switch (type) {
    case 'pedestrian':
      return MapUiColors.accidentPedestrian;
    case 'bicycle':
      return MapUiColors.accidentBicycle;
    case 'motorcycle':
      return MapUiColors.accidentMotorcycle;
    case 'schoolzone':
      return MapUiColors.accidentSchoolzone;
    default:
      return MapUiColors.report;
  }
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MapUiColors.accent,
      brightness: Brightness.light,
      primary: MapUiColors.accent,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF0F172A),
      surfaceTintColor: Colors.transparent,
    ),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MapUiColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
      selectedColor: MapUiColors.accentSoft,
      checkmarkColor: MapUiColors.accent,
      labelStyle: const TextStyle(fontSize: 13),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// 격자 fill (웹 fill opacity ~0.25 대응)
Color gradeColor(String? grade) {
  switch (grade) {
    case '안전':
      return MapUiColors.gradeSafe.withValues(alpha: 0.28);
    case '보통':
      return MapUiColors.gradeNormal.withValues(alpha: 0.28);
    case '불안':
      return MapUiColors.gradeUnsafe.withValues(alpha: 0.28);
    default:
      return MapUiColors.gradeDefault.withValues(alpha: 0.22);
  }
}

Color gradeBorderColor(String? grade) {
  switch (grade) {
    case '안전':
      return MapUiColors.gradeSafe.withValues(alpha: 0.85);
    case '보통':
      return MapUiColors.gradeNormal.withValues(alpha: 0.85);
    case '불안':
      return MapUiColors.gradeUnsafe.withValues(alpha: 0.85);
    default:
      return MapUiColors.gradeDefault.withValues(alpha: 0.7);
  }
}

Color infraMarkerColor(String? type) {
  switch (type) {
    case 'CCTV':
      return MapUiColors.cctv;
    case '경찰서':
      return MapUiColors.police;
    case '소방서':
      return MapUiColors.fire;
    case '편의점':
      return MapUiColors.store;
    default:
      return MapUiColors.accent;
  }
}
