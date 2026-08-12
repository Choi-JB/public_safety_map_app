import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 지도 롱프레스 액션 메뉴 (출발 / 도착 / 주소)
/// Marker height 128 안에 들어가도록 컴팩트 레이아웃.
class LongPressMapMenu extends StatelessWidget {
  const LongPressMapMenu({
    super.key,
    required this.address,
    required this.loading,
    required this.onOrigin,
    required this.onDestination,
    required this.onCopyAddress,
    required this.onClose,
  });

  final String? address;
  final bool loading;
  final VoidCallback onOrigin;
  final VoidCallback onDestination;
  final VoidCallback onCopyAddress;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final label = loading
        ? '주소 찾는 중…'
        : (address != null && address!.isNotEmpty)
            ? address!
            : '주소를 찾을 수 없음';

    return Material(
      color: MapUiColors.accent,
      elevation: 6,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 0, 2),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: loading ? null : onCopyAddress,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Colors.white24),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _MenuAction(
                      icon: Icons.trip_origin,
                      label: '출발',
                      onTap: onOrigin,
                    ),
                  ),
                  Expanded(
                    child: _MenuAction(
                      icon: Icons.flag,
                      label: '도착',
                      onTap: onDestination,
                    ),
                  ),
                  Expanded(
                    child: _MenuAction(
                      icon: Icons.content_copy,
                      label: '주소',
                      onTap: loading ? null : onCopyAddress,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? Colors.white54 : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
