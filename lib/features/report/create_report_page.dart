import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/geo/geo_utils.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/report_repository.dart';
import '../../providers/map_provider.dart';

/// BE 기능명세서 제보 유형
const reportTypes = ['교통사고', '싱크홀', '자연재해', '공사', '기타'];

class CreateReportPage extends StatefulWidget {
  const CreateReportPage({super.key, this.initialPos});

  /// 지도에서 넘긴 현재 위치(있으면 우선)
  final LatLng? initialPos;

  @override
  State<CreateReportPage> createState() => _CreateReportPageState();
}

class _CreateReportPageState extends State<CreateReportPage> {
  final _desc = TextEditingController();
  String _type = reportTypes.first;
  String? _imagePath;
  bool _loading = false;
  bool _locLoading = true;
  LatLng? _pos;
  String? _locError;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _resolveLocation() async {
    setState(() {
      _locLoading = true;
      _locError = null;
    });

    if (widget.initialPos != null) {
      setState(() {
        _pos = widget.initialPos;
        _locLoading = false;
      });
      return;
    }

    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (!mounted) return;
        setState(() {
          _locError = '위치 서비스를 켜 주세요';
          _locLoading = false;
        });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locError = '위치 권한이 필요합니다';
          _locLoading = false;
        });
        return;
      }

      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final ll = tryLatLng(p.latitude, p.longitude);
      if (!mounted) return;
      if (ll == null) {
        setState(() {
          _locError = '유효한 위치를 얻지 못했습니다';
          _locLoading = false;
        });
        return;
      }
      setState(() {
        _pos = ll;
        _locLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 폴백: 지도 중심
      final c = context.read<MapProvider>().center;
      final fallback = tryLatLng(c.latitude, c.longitude);
      setState(() {
        _pos = fallback;
        _locError = fallback == null
            ? '위치를 가져오지 못했습니다'
            : 'GPS 실패 · 지도 중심으로 대체';
        _locLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70,
    );
    if (file != null) setState(() => _imagePath = file.path);
  }

  void _clearImage() => setState(() => _imagePath = null);

  Future<void> _submit() async {
    final map = context.read<MapProvider>();
    final repo = context.read<ReportRepository>();
    final desc = _desc.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설명을 입력해 주세요')),
      );
      return;
    }
    final pos = _pos;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치를 확인할 수 없습니다')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      String? imgUrl;
      if (_imagePath != null) {
        imgUrl = await repo.uploadReportImage(_imagePath!);
      }
      await repo.createReport(
        type: _type,
        lat: pos.latitude,
        lng: pos.longitude,
        description: desc,
        imgUrl: imgUrl?.isEmpty == true ? null : imgUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제보가 등록되었습니다')),
      );
      await map.refreshFromViewport(
        swLat: pos.latitude - 0.04,
        swLng: pos.longitude - 0.04,
        neLat: pos.latitude + 0.04,
        neLng: pos.longitude + 0.04,
        newCenter: pos,
      );
      if (!mounted) return;
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = 20 + mq.viewPadding.bottom + mq.viewInsets.bottom;
    final pos = _pos;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('제보 작성')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MapUiColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: MapUiColors.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_locLoading)
                  const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        '현재 위치 확인 중…',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ],
                  )
                else if (pos != null)
                  Text(
                    '내 위치 ${pos.latitude.toStringAsFixed(5)}, '
                    '${pos.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3A8A),
                    ),
                  )
                else
                  const Text(
                    '위치를 확인할 수 없습니다',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _locError ??
                      '현재 GPS 위치 기준으로 등록됩니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _locError != null
                        ? const Color(0xFFB45309)
                        : const Color(0xFF64748B),
                  ),
                ),
                if (!_locLoading && pos == null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _resolveLocation,
                    child: const Text('다시 시도'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _type,
            items: reportTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
            decoration: const InputDecoration(labelText: '유형'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '설명',
              alignLabelWithHint: true,
              hintText: '현장 상황을 적어 주세요',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '사진 (선택)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (_imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Image.file(
                    File(_imagePath!),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _clearImage,
                        tooltip: '사진 제거',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo),
            label: Text(_imagePath == null ? '사진 첨부' : '사진 변경'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_loading || _locLoading || pos == null) ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('등록'),
          ),
        ],
      ),
    );
  }
}
