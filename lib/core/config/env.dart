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

  /// 제보·행사(API 실비용) 재조회 캐시 반경. 격자 렌더링용 bbox(줌별 ~2~4.5km)와 별개로
  /// 훨씬 넓게 한 번에 받아둬서, 이 반경 안에서 지도를 움직이는 동안은 재요청하지 않는다.
  /// (제보/행사는 서울 전역 30km 기준 105건·29KB 수준이라 넓혀도 비용 부담이 거의 없음 — 실측)
  static const double liveDataFetchRadiusKm = 15;

  /// 웹 ACCIDENT_REGION_DEBOUNCE_MS
  static const int accidentRegionDebounceMs = 2000;

  /// OSM zoom. 너무 멀 때 다발 숨김 (대략 카카오 level≥7 대응)
  static const double accidentHideMaxZoom = 11.5;

  /// 격자·인프라 정적 데이터 로컬 동기화 (device/check-data-version 백엔드 구현)
  static const String checkDataVersionPath = '/sync/version';
  static const String staticDataGridsPath = '/sync/grids';
  static const String staticDataInfraPath = '/sync/infrastructures';

  /// 로컬화 대상 data_type (accident_zone 등 나머지는 계속 기존 API 사용)
  static const List<String> staticDataTypes = ['grid', 'infra'];
}
