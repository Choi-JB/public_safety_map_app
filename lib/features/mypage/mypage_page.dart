import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/config/media_url.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/feedback_repository.dart';
import '../../data/repositories/mypage_repository.dart';
import '../../data/repositories/report_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/media_image.dart';

const _safetyFeelings = ['안전', '보통', '불안'];

int? _toIntId(Object? id) {
  if (id is int) return id;
  if (id == null) return null;
  return int.tryParse('$id');
}

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  MyPageSummary? summary;
  List<MyReport> reports = [];
  List<MyFeedback> feedbacks = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<MyPageRepository>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final s = await repo.fetchSummary();
      final r = await repo.fetchReports();
      final f = await repo.fetchFeedbacks();
      if (!mounted) return;
      setState(() {
        summary = s;
        reports = r;
        feedbacks = f;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _openReportDetail(MyReport r) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _ReportDetailSheet(report: r),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openFeedbackDetail(MyFeedback f) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _FeedbackDetailSheet(feedback: f),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _changePassword() async {
    final email = TextEditingController(
      text: context.read<AuthProvider>().user?.email ?? '',
    );
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: '이메일'),
            ),
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: '현재 비밀번호'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: '새 비밀번호'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthRepository>().changePassword(
            email: email.text.trim(),
            password: current.text,
            newPassword: next.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 변경되었습니다')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('마이페이지'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '내 제보'),
            Tab(text: '내 피드백'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _changePassword,
            icon: const Icon(Icons.lock_reset),
            tooltip: '비밀번호 변경',
          ),
          IconButton(
            onPressed: () async {
              await auth.logout();
              if (!context.mounted) return;
              context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('다시 시도')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    ListTile(
                      title: Text(auth.user?.nickname ?? '사용자'),
                      subtitle: Text(auth.user?.email ?? ''),
                      trailing: Text(
                        '제보 ${summary?.reportCount ?? 0} · '
                        '피드백 ${summary?.feedbackCount ?? 0}',
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _ReportList(
                            reports: reports,
                            onTap: _openReportDetail,
                          ),
                          _FeedbackList(
                            feedbacks: feedbacks,
                            onTap: _openFeedbackDetail,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({required this.reports, required this.onTap});
  final List<MyReport> reports;
  final void Function(MyReport) onTap;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const Center(child: Text('제보가 없습니다'));
    }
    return ListView.separated(
      itemCount: reports.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = reports[i];
        return ListTile(
          title: Text(r.type ?? '제보'),
          subtitle: Text(
            r.description ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            r.createdAt?.split('T').first ?? '',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => onTap(r),
        );
      },
    );
  }
}

class _FeedbackList extends StatelessWidget {
  const _FeedbackList({required this.feedbacks, required this.onTap});
  final List<MyFeedback> feedbacks;
  final void Function(MyFeedback) onTap;

  @override
  Widget build(BuildContext context) {
    if (feedbacks.isEmpty) {
      return const Center(
        child: Text(
          '피드백이 없습니다\n지도에서 격자를 선택해 작성할 수 있습니다',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: feedbacks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final f = feedbacks[i];
        return ListTile(
          title: Text(f.safetyFeeling ?? '피드백'),
          subtitle: Text(
            (f.comment?.isNotEmpty == true)
                ? f.comment!
                : f.tags.join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            f.createdAt?.split('T').first ?? '',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => onTap(f),
        );
      },
    );
  }
}

// ─── 제보 상세 / 수정 / 삭제 ─────────────────────────────────────────

class _ReportDetailSheet extends StatefulWidget {
  const _ReportDetailSheet({required this.report});
  final MyReport report;

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  late final TextEditingController _desc;
  bool _editing = false;
  bool _busy = false;
  String? _localImagePath;
  bool _clearImage = false;
  late String? _currentImgUrl;

  @override
  void initState() {
    super.initState();
    _desc = TextEditingController(text: widget.report.description ?? '');
    _currentImgUrl = widget.report.imgUrl;
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70,
    );
    if (file != null) {
      setState(() {
        _localImagePath = file.path;
        _clearImage = false;
      });
    }
  }

  Future<void> _save() async {
    final id = _toIntId(widget.report.id);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효하지 않은 제보 ID입니다')),
      );
      return;
    }
    final desc = _desc.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설명을 입력해 주세요')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final repo = context.read<ReportRepository>();
      String? imgUrl;
      if (_localImagePath != null) {
        imgUrl = await repo.uploadReportImage(_localImagePath!);
        if (imgUrl.isEmpty) imgUrl = null;
      }
      await repo.updateReport(
        id,
        description: desc,
        imgUrl: imgUrl,
        clearImage: _clearImage && _localImagePath == null,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text('제보가 수정되었습니다')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final id = _toIntId(widget.report.id);
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('제보 삭제'),
        content: const Text('이 제보를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MapUiColors.report,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await context.read<ReportRepository>().deleteReport(id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text('제보가 삭제되었습니다')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final mq = MediaQuery.of(context);
    // 시스템 네비 + 키보드 (피드백/제보 작성과 동일)
    final bottomPad = 24 + mq.viewPadding.bottom + mq.viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            Text(
              r.type ?? '제보',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (r.createdAt != null) r.createdAt!.split('T').first,
                if (r.lat != null && r.lng != null)
                  '${r.lat!.toStringAsFixed(5)}, ${r.lng!.toStringAsFixed(5)}',
              ].join(' · '),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            if (_editing) ...[
              TextField(
                controller: _desc,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '설명',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _ImageEditBlock(
                remoteUrl: _clearImage ? null : _currentImgUrl,
                localPath: _localImagePath,
                onPick: _pickImage,
                onClear: () => setState(() {
                  _localImagePath = null;
                  _clearImage = true;
                  _currentImgUrl = null;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                '유형·위치는 수정할 수 없습니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ] else ...[
              Text(
                (r.description ?? '').isEmpty ? '(설명 없음)' : r.description!,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
              if (resolveMediaUrl(_currentImgUrl) != null) ...[
                const SizedBox(height: 12),
                MediaCoverImage(url: _currentImgUrl, expanded: true),
              ],
            ],
            const SizedBox(height: 20),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_editing)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _editing = false;
                          _desc.text = r.description ?? '';
                          _localImagePath = null;
                          _clearImage = false;
                          _currentImgUrl = r.imgUrl;
                        });
                      },
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('저장'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('수정'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: MapUiColors.report,
                      ),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('삭제'),
                    ),
                  ),
                ],
              ),
          ],
        ),
    );
  }
}

// ─── 피드백 상세 / 수정 / 삭제 ───────────────────────────────────────

class _FeedbackDetailSheet extends StatefulWidget {
  const _FeedbackDetailSheet({required this.feedback});
  final MyFeedback feedback;

  @override
  State<_FeedbackDetailSheet> createState() => _FeedbackDetailSheetState();
}

class _FeedbackDetailSheetState extends State<_FeedbackDetailSheet> {
  late final TextEditingController _comment;
  late String _feeling;
  bool _editing = false;
  bool _busy = false;
  String? _localImagePath;
  bool _clearImage = false;
  late String? _currentImgUrl;

  @override
  void initState() {
    super.initState();
    final f = widget.feedback;
    _comment = TextEditingController(text: f.comment ?? '');
    _feeling = _safetyFeelings.contains(f.safetyFeeling)
        ? f.safetyFeeling!
        : _safetyFeelings[1];
    _currentImgUrl = f.imgUrl;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70,
    );
    if (file != null) {
      setState(() {
        _localImagePath = file.path;
        _clearImage = false;
      });
    }
  }

  Future<void> _save() async {
    final id = widget.feedback.id;
    if (id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효하지 않은 피드백 ID입니다')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final repo = context.read<FeedbackRepository>();
      String? imgUrl;
      if (_localImagePath != null) {
        imgUrl = await repo.uploadFeedbackImage(_localImagePath!);
        if (imgUrl.isEmpty) imgUrl = null;
      }
      await repo.updateFeedback(
        id,
        safetyFeeling: _feeling,
        comment: _comment.text.trim(),
        imgUrl: imgUrl,
        clearImage: _clearImage && _localImagePath == null,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text('피드백이 수정되었습니다')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.feedback.id;
    if (id <= 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('피드백 삭제'),
        content: const Text('이 피드백을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MapUiColors.report,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await context.read<FeedbackRepository>().deleteFeedback(id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text('피드백이 삭제되었습니다')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.feedback;
    final mq = MediaQuery.of(context);
    final bottomPad = 24 + mq.viewPadding.bottom + mq.viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            Text(
              f.safetyFeeling ?? '피드백',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              f.createdAt?.split('T').first ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (f.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: f.tags
                    .map(
                      (t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            if (_editing) ...[
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _feeling,
                items: _safetyFeelings
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _feeling = v);
                },
                decoration: const InputDecoration(
                  labelText: '안전감',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _comment,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '코멘트',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _ImageEditBlock(
                remoteUrl: _clearImage ? null : _currentImgUrl,
                localPath: _localImagePath,
                onPick: _pickImage,
                onClear: () => setState(() {
                  _localImagePath = null;
                  _clearImage = true;
                  _currentImgUrl = null;
                }),
              ),
              if (f.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '태그는 이 화면에서 수정할 수 없습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ] else ...[
              Text(
                (f.comment ?? '').isEmpty ? '(코멘트 없음)' : f.comment!,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
              if (resolveMediaUrl(_currentImgUrl) != null) ...[
                const SizedBox(height: 12),
                MediaCoverImage(url: _currentImgUrl, expanded: true),
              ],
            ],
            const SizedBox(height: 20),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_editing)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _editing = false;
                          _comment.text = f.comment ?? '';
                          _feeling = _safetyFeelings.contains(f.safetyFeeling)
                              ? f.safetyFeeling!
                              : _safetyFeelings[1];
                          _localImagePath = null;
                          _clearImage = false;
                          _currentImgUrl = f.imgUrl;
                        });
                      },
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('저장'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('수정'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: MapUiColors.report,
                      ),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('삭제'),
                    ),
                  ),
                ],
              ),
          ],
        ),
    );
  }
}

class _ImageEditBlock extends StatelessWidget {
  const _ImageEditBlock({
    required this.remoteUrl,
    required this.localPath,
    required this.onPick,
    required this.onClear,
  });

  final String? remoteUrl;
  final String? localPath;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasLocal = localPath != null;
    final hasRemote = resolveMediaUrl(remoteUrl) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasLocal)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(localPath!),
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
        else if (hasRemote)
          MediaCoverImage(url: remoteUrl, expanded: false),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.photo_outlined, size: 18),
                label: Text(hasLocal || hasRemote ? '사진 변경' : '사진 추가'),
              ),
            ),
            if (hasLocal || hasRemote) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close),
                tooltip: '사진 제거',
              ),
            ],
          ],
        ),
      ],
    );
  }
}
