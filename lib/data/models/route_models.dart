import 'package:latlong2/latlong.dart';

enum NavMode { walk, car }

enum RouteOption {
  shortest,
  maxCctv,
  minReports,
  avoidAccident,
}

extension NavModeX on NavMode {
  String get label => switch (this) {
        NavMode.walk => '보행',
        NavMode.car => '차량',
      };

  List<RouteOption> get options => const [
        RouteOption.shortest,
        RouteOption.maxCctv,
        RouteOption.minReports,
      ];
}

extension RouteOptionX on RouteOption {
  String get label => switch (this) {
        RouteOption.shortest => '최단거리',
        RouteOption.maxCctv => 'CCTV 많은 곳',
        RouteOption.minReports => '제보 최소화',
        RouteOption.avoidAccident => '위험 회피',
      };

  String get hint => switch (this) {
        RouteOption.shortest => '소요·거리가 가장 짧은 경로',
        RouteOption.maxCctv => '우회 한도 내에서 CCTV가 많은 경로',
        RouteOption.minReports => '우회 한도 내에서 제보가 적은 경로',
        RouteOption.avoidAccident => '위험구간을 최대한 줄인 경로',
      };
}

/// TMAP Point 안내 한 구간
class RouteStep {
  const RouteStep({
    required this.point,
    required this.description,
    this.turnType,
    this.alongRouteM = 0,
  });

  final LatLng point;
  final String description;
  final int? turnType;
  /// 경로 시작점부터 이 안내 지점까지 거리(m)
  final double alongRouteM;
}

class RouteCandidate {
  const RouteCandidate({
    required this.id,
    required this.points,
    required this.distanceM,
    this.durationSec,
    this.displayLabel = '경로',
    this.steps = const [],
    this.cctvCount = 0,
    this.reportCount = 0,
    this.accidentCost = 0,
    this.cctvPerKm,
    this.reportPerKm,
  });

  final String id;
  final List<LatLng> points;
  final double distanceM;
  final double? durationSec;
  /// UI 카드 라벨 (추천 / 최단거리 / CCTV 많은 곳 / 제보 최소화)
  final String displayLabel;
  final List<RouteStep> steps;
  final int cctvCount;
  final int reportCount;
  final double accidentCost;
  final double? cctvPerKm;
  final double? reportPerKm;

  double get lengthKm => distanceM / 1000.0;

  /// 대략 보폭 0.7m
  int get estimatedSteps => (distanceM / 0.7).round();

  RouteCandidate copyWithScores({
    int? cctvCount,
    int? reportCount,
    double? accidentCost,
    double? cctvPerKm,
    double? reportPerKm,
  }) {
    return RouteCandidate(
      id: id,
      points: points,
      distanceM: distanceM,
      durationSec: durationSec,
      displayLabel: displayLabel,
      steps: steps,
      cctvCount: cctvCount ?? this.cctvCount,
      reportCount: reportCount ?? this.reportCount,
      accidentCost: accidentCost ?? this.accidentCost,
      cctvPerKm: cctvPerKm ?? this.cctvPerKm,
      reportPerKm: reportPerKm ?? this.reportPerKm,
    );
  }

  /// 경로 수정(trim) 후 geometry·안내 단계만 갱신
  RouteCandidate copyWithGeometry({
    required List<LatLng> points,
    required double distanceM,
    double? durationSec,
    required List<RouteStep> steps,
  }) {
    return RouteCandidate(
      id: id,
      points: points,
      distanceM: distanceM,
      durationSec: durationSec,
      displayLabel: displayLabel,
      steps: steps,
      cctvCount: cctvCount,
      reportCount: reportCount,
      accidentCost: accidentCost,
      cctvPerKm: cctvPerKm,
      reportPerKm: reportPerKm,
    );
  }

  /// 선택 카드용: UI id·라벨만 바꾸고 점수·경로·안내는 유지
  RouteCandidate asChoiceCard({
    required String choiceId,
    required String label,
  }) {
    return RouteCandidate(
      id: choiceId,
      points: points,
      distanceM: distanceM,
      durationSec: durationSec,
      displayLabel: label,
      steps: steps,
      cctvCount: cctvCount,
      reportCount: reportCount,
      accidentCost: accidentCost,
      cctvPerKm: cctvPerKm,
      reportPerKm: reportPerKm,
    );
  }
}

class RouteCompareMeta {
  const RouteCompareMeta({
    required this.extraMinutes,
    required this.extraKm,
  });

  final double extraMinutes;
  final double extraKm;
}

String formatWalkDuration(double? durationSec) {
  if (durationSec == null || durationSec <= 0) return '-';
  final totalMin = (durationSec / 60).round();
  if (totalMin < 60) return '$totalMin분';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (m == 0) return '$h시간';
  return '$h시간 $m분';
}

String formatWalkDistance(double distanceM) {
  if (distanceM >= 1000) {
    return '${(distanceM / 1000).toStringAsFixed(1)}km';
  }
  return '${distanceM.round()}m';
}
