import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/route_models.dart';
import '../../providers/nav_provider.dart';

/// 추천 / 최단거리 / CCTV 많은 곳 / 제보 최소화 카드 시트 + 안내 모드
class NavSheet extends StatefulWidget {
  const NavSheet({
    super.key,
    this.myPos,
    this.onGuidanceStarted,
  });

  final LatLng? myPos;
  final VoidCallback? onGuidanceStarted;

  @override
  State<NavSheet> createState() => _NavSheetState();
}

class _NavSheetState extends State<NavSheet> {
  final GlobalKey _sizeKey = GlobalKey();
  bool _heightReportScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleReportHeight();
  }

  void _scheduleReportHeight() {
    if (_heightReportScheduled) return;
    _heightReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _heightReportScheduled = false;
      _reportHeight();
    });
  }

  void _reportHeight() {
    if (!mounted) return;
    final box = _sizeKey.currentContext?.findRenderObject() as RenderBox?;
    final h = box?.size.height;
    if (h == null || h <= 0) return;
    context.read<NavProvider>().setSheetHeight(h);
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    if (!nav.active) return const SizedBox.shrink();

    _scheduleReportHeight();

    // 안내 중 UI는 하단 패널과 한 Material로 합침 (map_page)
    if (nav.guiding) {
      return const SizedBox.shrink();
    }

    final maxListH = MediaQuery.sizeOf(context).height * 0.42;

    return Material(
      key: _sizeKey,
      elevation: 8,
      color: Colors.white,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '경로 선택',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.white,
                  elevation: 2,
                  shadowColor: Colors.black26,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.read<NavProvider>().toggleActive(),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (nav.loading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 3),
            ],
            if (nav.error != null) ...[
              const SizedBox(height: 8),
              Text(
                nav.error!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (nav.message != null) ...[
              const SizedBox(height: 6),
              Text(
                nav.message!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (nav.choiceCards.isEmpty && !nav.loading) ...[
              const SizedBox(height: 10),
              const Text(
                '검색창에 도착지를 입력한 뒤 길찾기 버튼을 누르세요.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (nav.choiceCards.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListH),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: nav.choiceCards.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    color: Color(0xFFE2E8F0),
                  ),
                  itemBuilder: (context, index) {
                    final c = nav.choiceCards[index];
                    final selected = nav.selected?.id == c.id;
                    return _RouteOptionTile(
                      candidate: c,
                      selected: selected,
                      onTap: () =>
                          context.read<NavProvider>().selectCandidate(c),
                      onStartGuidance: () {
                        context.read<NavProvider>().startGuidance(
                              c,
                              myPos: widget.myPos,
                            );
                        widget.onGuidanceStarted?.call();
                      },
                    );
                  },
                ),
              ),
            ],
            if (nav.destination != null) ...[
              const SizedBox(height: 10),
              Material(
                elevation: 3,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(10),
                color: nav.loading
                    ? const Color(0xFF94A3B8)
                    : MapUiColors.accent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: nav.loading
                      ? null
                      : () => context.read<NavProvider>().plan(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        '경로 다시 찾기',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 안내 바 본문 (하단 패널과 한 덩어리로 쓸 때 Material 없음)
class NavGuidanceBar extends StatelessWidget {
  const NavGuidanceBar({super.key, required this.nav});

  final NavProvider nav;

  /// FAB·패널 높이 계산용 대략 높이
  static const double preferredHeight = 72;

  @override
  Widget build(BuildContext context) {
    final stepText = nav.arrived
        ? '목적지에 도착했습니다'
        : (nav.currentStep?.description ?? '경로를 따라 이동하세요');
    final toStep = nav.arrived ? null : formatWalkDistance(nav.distanceToStepM);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      '안내 중',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (toStep != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        toStep,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: MapUiColors.accent,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  stepText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    height: 1.2,
                  ),
                ),
                Text(
                  '남은 ${formatWalkDistance(nav.remainingDistanceM)}'
                  ' · ${formatWalkDuration(nav.remainingDurationSec)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(
                color: MapUiColors.accent,
                width: 1.2,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.read<NavProvider>().stopGuidance(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  '안내 종료',
                  style: TextStyle(
                    color: MapUiColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteOptionTile extends StatelessWidget {
  const _RouteOptionTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
    required this.onStartGuidance,
  });

  final RouteCandidate candidate;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onStartGuidance;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEFF6FF) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? MapUiColors.accent
                      : const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  candidate.displayLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : MapUiColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatWalkDuration(candidate.durationSec),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatWalkDistance(candidate.distanceM)}'
                ' · 약 ${candidate.estimatedSteps}걸음',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'CCTV ${candidate.cctvCount} · 제보 ${candidate.reportCount}',
                style: TextStyle(
                  fontSize: 12,
                  color: MapUiColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: MapUiColors.accent, width: 1.2),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onStartGuidance,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                    child: Center(
                      child: Text(
                        '안내 시작',
                        style: TextStyle(
                          color: MapUiColors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
