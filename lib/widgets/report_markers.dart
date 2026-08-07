import 'package:flutter/material.dart';

import '../core/config/media_url.dart';
import '../core/theme/app_theme.dart';

/// 제보 유형 → 아이콘
IconData reportTypeIcon(String? type) {
  switch (type) {
    case '교통사고':
      return Icons.car_crash;
    case '싱크홀':
      return Icons.landslide_outlined;
    case '공사':
      return Icons.construction;
    case '통제':
      return Icons.block;
    case '자연재해':
      return Icons.flood_outlined;
    default:
      return Icons.report;
  }
}

/// 제보 유형 → 마커 색
Color reportTypeColor(String? type) {
  switch (type) {
    case '교통사고':
      return const Color(0xFFDC2626);
    case '싱크홀':
      return const Color(0xFFB45309);
    case '공사':
      return const Color(0xFFEA580C);
    case '통제':
      return const Color(0xFF7C3AED);
    case '자연재해':
      return const Color(0xFF0369A1);
    default:
      return MapUiColors.report;
  }
}

/// 행사 유형 → 아이콘
IconData eventTypeIcon(String? type) {
  switch (type) {
    case '축제':
    case '행사':
      return Icons.celebration;
    case '공연':
    case '콘서트':
      return Icons.music_note;
    case '전시':
    case '박람회':
      return Icons.museum_outlined;
    case '스포츠':
    case '경기':
      return Icons.sports_soccer;
    case '마켓':
    case '장터':
      return Icons.storefront;
    default:
      return Icons.event;
  }
}

/// 핀만 있을 때 마커 크기
const double kFeaturePinMarkerSize = 44;

/// 말풍선+핀 합친 마커 (bottomCenter 정렬용)
const double kFeatureBubbleMarkerWidth = 176;
const double kFeatureBubbleMarkerHeight = 200;

// 하위 호환 별칭
const double kReportPinMarkerSize = kFeaturePinMarkerSize;
const double kReportBubbleMarkerWidth = kFeatureBubbleMarkerWidth;
const double kReportBubbleMarkerHeight = kFeatureBubbleMarkerHeight;

/// 원형 색상 핀
class FeatureTypePin extends StatelessWidget {
  const FeatureTypePin({
    super.key,
    required this.color,
    required this.icon,
    this.selected = false,
  });

  final Color color;
  final IconData icon;
  final bool selected;

  double get size => selected ? 40.0 : 34.0;

  @override
  Widget build(BuildContext context) {
    final s = size;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: selected ? 22 : 18,
      ),
    );
  }
}

/// 지도 상 제보/행사 마커: 핀 + 선택 시 사진 말풍선 (좌표 = 핀 하단 중심)
class FeatureMapMarker extends StatelessWidget {
  const FeatureMapMarker({
    super.key,
    required this.color,
    required this.icon,
    this.label,
    this.imgUrl,
    this.selected = false,
    this.onTap,
    this.onCloseBubble,
  });

  final Color color;
  final IconData icon;
  final String? label;
  final String? imgUrl;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onCloseBubble;

  bool get _showBubble => selected && resolveMediaUrl(imgUrl) != null;

  @override
  Widget build(BuildContext context) {
    final pin = FeatureTypePin(
      color: color,
      icon: icon,
      selected: selected,
    );

    final body = !_showBubble
        ? pin
        : Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MapPhotoBubble(
                imgUrl: imgUrl!,
                typeLabel: label,
                onClose: onCloseBubble,
              ),
              const SizedBox(height: 2),
              pin,
            ],
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: body,
      ),
    );
  }
}

/// 제보용 단축 마커
class ReportMapMarker extends StatelessWidget {
  const ReportMapMarker({
    super.key,
    required this.type,
    this.imgUrl,
    this.selected = false,
    this.onTap,
    this.onCloseBubble,
  });

  final String? type;
  final String? imgUrl;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onCloseBubble;

  @override
  Widget build(BuildContext context) {
    return FeatureMapMarker(
      color: reportTypeColor(type),
      icon: reportTypeIcon(type),
      label: type,
      imgUrl: imgUrl,
      selected: selected,
      onTap: onTap,
      onCloseBubble: onCloseBubble,
    );
  }
}

/// 행사용 단축 마커
class EventMapMarker extends StatelessWidget {
  const EventMapMarker({
    super.key,
    this.type,
    this.title,
    this.imgUrl,
    this.selected = false,
    this.onTap,
    this.onCloseBubble,
  });

  final String? type;
  final String? title;
  final String? imgUrl;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onCloseBubble;

  @override
  Widget build(BuildContext context) {
    final label = (title != null && title!.trim().isNotEmpty)
        ? title
        : (type ?? '행사');
    return FeatureMapMarker(
      color: MapUiColors.event,
      icon: eventTypeIcon(type),
      label: label,
      imgUrl: imgUrl,
      selected: selected,
      onTap: onTap,
      onCloseBubble: onCloseBubble,
    );
  }
}

/// 마커 위 사진 말풍선 (꼬리가 아래 핀을 가리킴)
class MapPhotoBubble extends StatelessWidget {
  const MapPhotoBubble({
    super.key,
    required this.imgUrl,
    this.typeLabel,
    this.onClose,
  });

  final String imgUrl;
  final String? typeLabel;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final url = resolveMediaUrl(imgUrl);
    if (url == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          child: SizedBox(
            width: 168,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(12),
                    bottom: (typeLabel != null && typeLabel!.isNotEmpty)
                        ? Radius.zero
                        : const Radius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      Image.network(
                        url,
                        height: 110,
                        width: 168,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 110,
                          color: const Color(0xFFF1F5F9),
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            height: 110,
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        },
                      ),
                      if (onClose != null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Material(
                            color: Colors.black45,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onClose,
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (typeLabel != null && typeLabel!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Text(
                      typeLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        CustomPaint(
          size: const Size(16, 8),
          painter: _BubbleTailPainter(),
        ),
      ],
    );
  }
}

/// 예전 이름 호환
typedef ReportPhotoBubble = MapPhotoBubble;
typedef ReportTypePin = FeatureTypePin;

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawShadow(path.shift(const Offset(0, 1)), Colors.black26, 2, true);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
