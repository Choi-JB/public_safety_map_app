import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/user_error.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/feedback_repository.dart';
import '../../providers/map_provider.dart';

const _safetyFeelings = ['안전', '보통', '불안'];

/// POST /grids/:id/feedbacks — 격자 기준 피드백 작성
class CreateFeedbackPage extends StatefulWidget {
  const CreateFeedbackPage({super.key, required this.gridId});

  final int gridId;

  @override
  State<CreateFeedbackPage> createState() => _CreateFeedbackPageState();
}

class _CreateFeedbackPageState extends State<CreateFeedbackPage> {
  final _comment = TextEditingController();
  String _feeling = _safetyFeelings[1];
  final Set<int> _selectedTagIds = {};
  List<FeedbackTag> _tags = [];
  bool _tagsLoading = true;
  String? _imagePath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final list = await context.read<FeedbackRepository>().fetchTags();
      if (!mounted) return;
      setState(() {
        _tags = list.where((t) => t.id > 0 && t.name.isNotEmpty).toList();
        _tagsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tags = [];
        _tagsLoading = false;
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
    if (widget.gridId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효하지 않은 격자입니다')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = context.read<FeedbackRepository>();
      String? imgUrl;
      if (_imagePath != null) {
        imgUrl = await repo.uploadFeedbackImage(_imagePath!);
        if (imgUrl.isEmpty) imgUrl = null;
      }
      await repo.createFeedback(
        gridId: widget.gridId,
        safetyFeeling: _feeling,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        tagIds: _selectedTagIds.toList()..sort(),
        imgUrl: imgUrl,
      );
      if (!mounted) return;

      // 격자 상세 갱신
      try {
        await context.read<MapProvider>().selectGrid(widget.gridId);
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('피드백이 등록되었습니다')),
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.statusCode == 409
          ? '이 격자에 이미 피드백을 작성했습니다'
          : userFacingError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // 시스템 네비(viewPadding) + 키보드(viewInsets). resize는 끄고 padding으로만 확보.
    final bottomPad =
        20 + mq.viewPadding.bottom + mq.viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('피드백 작성')),
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
                Text(
                  '격자 #${widget.gridId}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '선택한 격지에 대한 안전 체감과 의견을 남겨 주세요. '
                  '격자당 활성 피드백은 1건입니다.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '안전감',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: _safetyFeelings
                .map((e) => ButtonSegment(value: e, label: Text(e)))
                .toList(),
            selected: {_feeling},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) setState(() => _feeling = s.first);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comment,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '의견 (선택)',
              alignLabelWithHint: true,
              hintText: '이 지역에 대해 느낀 점을 적어 주세요',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '태그',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (_tagsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_tags.isEmpty)
            Text(
              '등록된 태그가 없습니다',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _tags.map((t) {
                final selected = _selectedTagIds.contains(t.id);
                return FilterChip(
                  label: Text(
                    t.name,
                    style: TextStyle(
                      color: selected
                          ? MapUiColors.accent
                          : const Color(0xFF0F172A),
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  selected: selected,
                  backgroundColor: Colors.white,
                  selectedColor: MapUiColors.accentSoft,
                  checkmarkColor: MapUiColors.accent,
                  side: BorderSide(
                    color: selected
                        ? MapUiColors.accent
                        : const Color(0xFFCBD5E1),
                  ),
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedTagIds.add(t.id);
                      } else {
                        _selectedTagIds.remove(t.id);
                      }
                    });
                  },
                );
              }).toList(),
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
            onPressed: _loading ? null : _submit,
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
