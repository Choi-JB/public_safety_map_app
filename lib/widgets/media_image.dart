import 'package:flutter/material.dart';

import '../core/config/media_url.dart';
import '../core/theme/app_theme.dart';

/// 패널 카드 커버 이미지 (선택 시 높이 확대)
class MediaCoverImage extends StatelessWidget {
  const MediaCoverImage({
    super.key,
    required this.url,
    this.expanded = false,
    this.borderRadius = 6,
  });

  final String? url;
  final bool expanded;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(url);
    if (resolved == null) return const SizedBox.shrink();

    final height = expanded ? 280.0 : 120.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: double.infinity,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: const Color(0xFFF1F5F9),
      ),
      child: Image.network(
        resolved,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(
          color: const Color(0xFFF1F5F9),
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade500),
          ),
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }
}

class ReportListCard extends StatelessWidget {
  const ReportListCard({
    super.key,
    required this.title,
    this.meta,
    this.selected = false,
    this.onTap,
  });

  /// "[유형] 설명" 한 줄 요약 (마이페이지 내 제보와 동일)
  final String title;
  final String? meta;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? MapUiColors.reportSelectedBg : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? MapUiColors.report : const Color(0xFFE2E8F0),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (meta != null && meta!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EventListCard extends StatelessWidget {
  const EventListCard({
    super.key,
    required this.title,
    required this.description,
    this.imgUrl,
    this.meta,
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String description;
  /// 사진은 지도 말풍선에서만 표시 — 패널 카드에는 쓰지 않음
  final String? imgUrl;
  final String? meta;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: selected ? MapUiColors.eventSelectedBg : Colors.white,
        elevation: selected ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(
            color: selected ? MapUiColors.event : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: selected ? 8 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      height: 1.35,
                    ),
                  ),
                ],
                if (meta != null && meta!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    meta!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
