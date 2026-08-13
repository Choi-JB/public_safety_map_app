/// API / 앱 환경 설정
class Env {
  Env._();

  /// 백엔드 베이스 URL
  /// - Android 에뮬레이터: 10.0.2.2
  /// - iOS 시뮬레이터 / 데스크톱: localhost
  /// - 실기기: PC의 LAN IP
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://43-202-197-59.nip.io',
  );

  /// 카카오 로컬 REST (좌표→행정구역). 웹과 동일 용도.
  /// `--dart-define=KAKAO_REST_API_KEY=...` 로 덮어쓰기 가능.
  static const String kakaoRestApiKey = String.fromEnvironment(
    'KAKAO_REST_API_KEY',
    defaultValue: '0f3ca47f756485555f44f6bbcdcc7a5d',
  );

  /// TMAP 보행자 경로 (SK open API appKey)
  /// `--dart-define=TMAP_APP_KEY=...` 로 주입.
  static const String tmapAppKey = String.fromEnvironment(
    'TMAP_APP_KEY',
    defaultValue: 'bSZjez06059b4paLNRw123cD0U3FgN6a5INajMnR', 
  );


  /// 서울 시청 근처 기본 중심 (웹 맵과 유사)
  static const double defaultLat = 37.5665;
  static const double defaultLng = 126.9780;

  static const double gridCellDeg = 0.01;

  /// (웹용 참고) 행사 등 넓은 반경
  static const double centerEventRadiusKm = 10;

  /// 앱 사고다발 필터 반경 (웹 10km보다 좁게)
  static const double accidentZoneRadiusKm = 4;

  /// 웹 ACCIDENT_REGION_DEBOUNCE_MS
  static const int accidentRegionDebounceMs = 2000;

  /// OSM zoom. 너무 멀 때 다발 숨김 (대략 카카오 level≥7 대응)
  static const double accidentHideMaxZoom = 11.5;
}
