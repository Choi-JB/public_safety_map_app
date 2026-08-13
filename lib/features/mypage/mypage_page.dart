import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/config/media_url.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/user_error.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/feedback_repository.dart';
import '../../data/repositories/mypage_repository.dart';
import '../../data/repositories/report_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/map_provider.dart';
import '../../widgets/media_image.dart';
import '../../core/geo/geo_utils.dart';

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

enum _MyPageSection { menu, reports, feedbacks }

class _MyPageState extends State<MyPage> {
  static const _pageSize = 10;

  _MyPageSection _section = _MyPageSection.menu;
  MyPageSummary? summary;
  List<MyReport> reports = [];
  List<MyFeedback> feedbacks = [];
  bool loading = true;
  String? error;

  int _reportPage = 1;
  int _feedbackPage = 1;
  bool _reportsHasMore = true;
  bool _feedbacksHasMore = true;
  bool _reportsLoadingMore = false;
  bool _feedbacksLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool tryReopen = true}) async {
    final repo = context.read<MyPageRepository>();
    setState(() {
      loading = true;
      error = null;
      _reportPage = 1;
      _feedbackPage = 1;
      _reportsHasMore = true;
      _feedbacksHasMore = true;
      _reportsLoadingMore = false;
      _feedbacksLoadingMore = false;
    });
    try {
      final s = await repo.fetchSummary();
      final r = await repo.fetchReports(page: 1, limit: _pageSize);
      final f = await repo.fetchFeedbacks(page: 1, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        summary = s;
        reports = r;
        feedbacks = f;
        _reportsHasMore = r.length >= _pageSize;
        _feedbacksHasMore = f.length >= _pageSize;
        loading = false;
      });
      if (tryReopen) await _maybeReopenPendingDetail();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = userFacingError(e);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = userFacingError(e);
        loading = false;
      });
    }
  }

  Future<void> _loadMoreReports() async {
    if (_reportsLoadingMore || !_reportsHasMore || loading) return;
    final repo = context.read<MyPageRepository>();
    setState(() => _reportsLoadingMore = true);
    try {
      final next = _reportPage + 1;
      final chunk = await repo.fetchReports(page: next, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        reports = [...reports, ...chunk];
        _reportPage = next;
        _reportsHasMore = chunk.length >= _pageSize;
        _reportsLoadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _reportsLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _reportsLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _loadMoreFeedbacks() async {
    if (_feedbacksLoadingMore || !_feedbacksHasMore || loading) return;
    final repo = context.read<MyPageRepository>();
    setState(() => _feedbacksLoadingMore = true);
    try {
      final next = _feedbackPage + 1;
      final chunk = await repo.fetchFeedbacks(page: next, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        feedbacks = [...feedbacks, ...chunk];
        _feedbackPage = next;
        _feedbacksHasMore = chunk.length >= _pageSize;
        _feedbacksLoadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _feedbacksLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _feedbacksLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  /// 지도에서 위치 확인 후 마이페이지로 다시 들어오면 보던 상세 복원
  Future<void> _maybeReopenPendingDetail() async {
    if (!mounted) return;
    final pending = context.read<MapProvider>().takePendingMypageReopen();
    if (pending == null) return;

    final reportId = pending.reportId;
    if (reportId != null) {
      MyReport? found;
      for (final r in reports) {
        if (_toIntId(r.id) == reportId) {
          found = r;
          break;
        }
      }
      if (found == null) return;
      setState(() => _section = _MyPageSection.reports);
      await _openReportDetail(found);
      return;
    }

    final feedbackId = pending.feedbackId;
    if (feedbackId != null) {
      MyFeedback? found;
      for (final f in feedbacks) {
        if (f.id == feedbackId) {
          found = f;
          break;
        }
      }
      if (found == null) return;
      setState(() => _section = _MyPageSection.feedbacks);
      await _openFeedbackDetail(found);
    }
  }

  Future<void> _openReportDetail(MyReport r) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _ReportDetailSheet(report: r),
    );
    if (!mounted) return;
    if (result == true) {
      await _load(tryReopen: false);
      return;
    }
    if (result is MapFocusTarget) {
      final map = context.read<MapProvider>();
      map.setPendingMypageReopen(reportId: _toIntId(r.id));
      map.requestMapFocus(result);
      context.go('/map');
    }
  }

  Future<void> _openFeedbackDetail(MyFeedback f) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _FeedbackDetailSheet(feedback: f),
    );
    if (!mounted) return;
    if (result == true) {
      await _load(tryReopen: false);
      return;
    }
    if (result is MapFocusTarget) {
      final map = context.read<MapProvider>();
      map.setPendingMypageReopen(feedbackId: f.id > 0 ? f.id : null);
      map.requestMapFocus(result);
      context.go('/map');
    }
  }

  InputDecoration _passwordFieldDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MapUiColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MapUiColors.report),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MapUiColors.report, width: 1.5),
      ),
      suffixIcon: suffixIcon,
    );
  }

  Widget _visibilityToggle({
    required bool obscure,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: const Color(0xFF94A3B8),
      ),
    );
  }

  Future<void> _changePassword() async {
    final email = context.read<AuthProvider>().user?.email ?? '';
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscureCurrent = true;
    var obscureNext = true;
    var obscureConfirm = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            '비밀번호 변경',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: current,
                  obscureText: obscureCurrent,
                  textInputAction: TextInputAction.next,
                  decoration: _passwordFieldDecoration(
                    hint: '현재 비밀번호',
                    suffixIcon: _visibilityToggle(
                      obscure: obscureCurrent,
                      onPressed: () => setDialogState(
                        () => obscureCurrent = !obscureCurrent,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? '현재 비밀번호를 입력하세요' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: next,
                  obscureText: obscureNext,
                  textInputAction: TextInputAction.next,
                  decoration: _passwordFieldDecoration(
                    hint: '새 비밀번호',
                    suffixIcon: _visibilityToggle(
                      obscure: obscureNext,
                      onPressed: () =>
                          setDialogState(() => obscureNext = !obscureNext),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '새 비밀번호를 입력하세요';
                    if (v.length < 6) return '6자 이상 입력하세요';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: confirm,
                  obscureText: obscureConfirm,
                  textInputAction: TextInputAction.done,
                  decoration: _passwordFieldDecoration(
                    hint: '새 비밀번호 확인',
                    suffixIcon: _visibilityToggle(
                      obscure: obscureConfirm,
                      onPressed: () => setDialogState(
                        () => obscureConfirm = !obscureConfirm,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return '새 비밀번호를 다시 입력하세요';
                    }
                    if (v != next.text) return '비밀번호가 일치하지 않습니다';
                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(ctx, true);
                    }
                  },
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: MapUiColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('변경'),
            ),
          ],
        ),
      ),
    );

    final currentPw = current.text;
    final nextPw = next.text;
    current.dispose();
    next.dispose();
    confirm.dispose();

    if (ok != true || !mounted) return;
    try {
      await context.read<AuthRepository>().changePassword(
        email: email,
        password: currentPw,
        newPassword: nextPw,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('비밀번호가 변경되었습니다')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    }
  }

  String get _title => switch (_section) {
        _MyPageSection.menu => '마이페이지',
        _MyPageSection.reports => '내 제보',
        _MyPageSection.feedbacks => '내 피드백',
      };

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃', textAlign: TextAlign.center),
        content: const Text('로그아웃 하시겠습니까?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await auth.logout();
    if (!mounted) return;
    context.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final onMenu = _section == _MyPageSection.menu;

    return PopScope(
      canPop: onMenu,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || onMenu) return;
        setState(() => _section = _MyPageSection.menu);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          leading: onMenu
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () =>
                      setState(() => _section = _MyPageSection.menu),
                ),
          actions: [
            if (onMenu)
              IconButton(
                tooltip: '로그아웃',
                onPressed: _logout,
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
                        FilledButton(
                          onPressed: _load,
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  )
                : switch (_section) {
                    _MyPageSection.menu => _MenuBody(
                        nickname: auth.user?.nickname ?? '사용자',
                        email: auth.user?.email ?? '',
                        reportCount: summary?.reportCount ?? 0,
                        feedbackCount: summary?.feedbackCount ?? 0,
                        onReports: () =>
                            setState(() => _section = _MyPageSection.reports),
                        onFeedbacks: () => setState(
                          () => _section = _MyPageSection.feedbacks,
                        ),
                        onChangePassword: _changePassword,
                      ),
                    _MyPageSection.reports => _ReportList(
                        reports: reports,
                        loadingMore: _reportsLoadingMore,
                        hasMore: _reportsHasMore,
                        onLoadMore: _loadMoreReports,
                        onTap: _openReportDetail,
                      ),
                    _MyPageSection.feedbacks => _FeedbackList(
                        feedbacks: feedbacks,
                        loadingMore: _feedbacksLoadingMore,
                        hasMore: _feedbacksHasMore,
                        onLoadMore: _loadMoreFeedbacks,
                        onTap: _openFeedbackDetail,
                      ),
                  },
      ),
    );
  }
}

class _MenuBody extends StatelessWidget {
  const _MenuBody({
    required this.nickname,
    required this.email,
    required this.reportCount,
    required this.feedbackCount,
    required this.onReports,
    required this.onFeedbacks,
    required this.onChangePassword,
  });

  final String nickname;
  final String email;
  final int reportCount;
  final int feedbackCount;
  final VoidCallback onReports;
  final VoidCallback onFeedbacks;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: MapUiColors.accentSoft,
                child: Text(
                  nickname.isNotEmpty ? nickname.characters.first : '?',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: MapUiColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email.isEmpty ? '이메일 없음' : email,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _MenuCard(
          children: [
            _MenuTile(
              label: '내 제보',
              subtitle: '$reportCount건',
              onTap: onReports,
            ),
            _MenuTile(
              label: '내 피드백',
              subtitle: '$feedbackCount건',
              onTap: onFeedbacks,
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MenuCard(
          title: '인증 및 보안',
          children: [
            _MenuTile(
              label: '비밀번호 변경',
              onTap: onChangePassword,
              showDivider: false,
            ),
          ],
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                title!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.label,
    required this.onTap,
    this.subtitle,
    this.showDivider = true,
  });

  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: MapUiColors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _ReportList extends StatefulWidget {
  const _ReportList({
    required this.reports,
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
    required this.onTap,
  });

  final List<MyReport> reports;
  final bool loadingMore;
  final bool hasMore;
  final Future<void> Function() onLoadMore;
  final void Function(MyReport) onTap;

  @override
  State<_ReportList> createState() => _ReportListState();
}

class _ReportListState extends State<_ReportList> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMoreIfShort());
  }

  @override
  void didUpdateWidget(covariant _ReportList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reports.length != oldWidget.reports.length ||
        widget.loadingMore != oldWidget.loadingMore ||
        widget.hasMore != oldWidget.hasMore) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeLoadMoreIfShort());
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.pixels <
        _controller.position.maxScrollExtent - 200) {
      return;
    }
    if (!widget.hasMore || widget.loadingMore) return;
    widget.onLoadMore();
  }

  /// 화면을 다 채우지 못해 스크롤이 안 되면 다음 페이지를 이어서 로드
  void _maybeLoadMoreIfShort() {
    if (!mounted || !_controller.hasClients) return;
    if (!widget.hasMore || widget.loadingMore) return;
    if (_controller.position.maxScrollExtent <= 0) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reports.isEmpty && !widget.loadingMore) {
      return const Center(child: Text('제보가 없습니다'));
    }
    final showFooter = widget.loadingMore;
    return ListView.separated(
      controller: _controller,
      itemCount: widget.reports.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i >= widget.reports.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final r = widget.reports[i];
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
          onTap: () => widget.onTap(r),
        );
      },
    );
  }
}

class _FeedbackList extends StatefulWidget {
  const _FeedbackList({
    required this.feedbacks,
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
    required this.onTap,
  });

  final List<MyFeedback> feedbacks;
  final bool loadingMore;
  final bool hasMore;
  final Future<void> Function() onLoadMore;
  final void Function(MyFeedback) onTap;

  @override
  State<_FeedbackList> createState() => _FeedbackListState();
}

class _FeedbackListState extends State<_FeedbackList> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMoreIfShort());
  }

  @override
  void didUpdateWidget(covariant _FeedbackList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.feedbacks.length != oldWidget.feedbacks.length ||
        widget.loadingMore != oldWidget.loadingMore ||
        widget.hasMore != oldWidget.hasMore) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeLoadMoreIfShort());
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.pixels <
        _controller.position.maxScrollExtent - 200) {
      return;
    }
    if (!widget.hasMore || widget.loadingMore) return;
    widget.onLoadMore();
  }

  void _maybeLoadMoreIfShort() {
    if (!mounted || !_controller.hasClients) return;
    if (!widget.hasMore || widget.loadingMore) return;
    if (_controller.position.maxScrollExtent <= 0) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.feedbacks.isEmpty && !widget.loadingMore) {
      return const Center(
        child: Text(
          '피드백이 없습니다\n지도에서 격자를 선택해 작성할 수 있습니다',
          textAlign: TextAlign.center,
        ),
      );
    }
    final showFooter = widget.loadingMore;
    return ListView.separated(
      controller: _controller,
      itemCount: widget.feedbacks.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i >= widget.feedbacks.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final f = widget.feedbacks[i];
        return ListTile(
          title: Text(f.safetyFeeling ?? '피드백'),
          subtitle: Text(
            (f.comment?.isNotEmpty == true) ? f.comment! : f.tags.join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            f.createdAt?.split('T').first ?? '',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => widget.onTap(f),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('유효하지 않은 제보 ID입니다')));
      return;
    }
    final desc = _desc.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('설명을 입력해 주세요')));
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
      messenger.showSnackBar(const SnackBar(content: Text('제보가 수정되었습니다')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
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
            style: FilledButton.styleFrom(backgroundColor: MapUiColors.report),
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
      messenger.showSnackBar(const SnackBar(content: Text('제보가 삭제되었습니다')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (r.createdAt != null) r.createdAt!.split('T').first,
              if (r.lat != null && r.lng != null)
                '${r.lat!.toStringAsFixed(5)}, ${r.lng!.toStringAsFixed(5)}',
            ].join(' · '),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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

          /// 제보 위치로 이동 버튼
          if (!_editing && !_busy) ...[
            OutlinedButton.icon(
              onPressed: () {
                final p = tryLatLng(r.lat, r.lng);
                if (p == null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('위치 정보가 없습니다')));
                  return;
                }
                // 부모에서 push 후, 지도 뒤로가기 시 상세를 다시 연다
                Navigator.pop(
                  context,
                  MapFocusTarget(
                    lat: p.latitude,
                    lng: p.longitude,
                    reportId: _toIntId(r.id),
                  ),
                );
              },
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('제보 위치로 이동'),
            ),
            const SizedBox(height: 12),
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
  List<FeedbackTag> _allTags = [];
  final Set<int> _selectedTagIds = {};
  bool _tagsLoading = true;

  @override
  void initState() {
    super.initState();
    final f = widget.feedback;
    _comment = TextEditingController(text: f.comment ?? '');
    _feeling = _safetyFeelings.contains(f.safetyFeeling)
        ? f.safetyFeeling!
        : _safetyFeelings[1];
    _currentImgUrl = f.imgUrl;
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
    final names = widget.feedback.tags.map((e) => e.trim()).toSet();
    setState(() {
      _allTags = list.where((t) => t.id > 0 && t.name.isNotEmpty).toList();
      _selectedTagIds
        ..clear()
        ..addAll(
          _allTags.where((t) => names.contains(t.name)).map((t) => t.id),
        );
      _tagsLoading = false;
    });
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _allTags = [];
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
        tagIds: _selectedTagIds.toList()..sort(),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(const SnackBar(content: Text('피드백이 수정되었습니다')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
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
            style: FilledButton.styleFrom(backgroundColor: MapUiColors.report),
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
      messenger.showSnackBar(const SnackBar(content: Text('피드백이 삭제되었습니다')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                      label: Text(t, style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A))),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
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
            else if (_allTags.isEmpty)
              Text(
                '등록된 태그가 없습니다',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _allTags.map((t) {
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

          /// 피드백 위치로 이동 버튼
          if (!_editing && !_busy) ...[
            OutlinedButton.icon(
              onPressed: () {
                final gridId = _toIntId(f.gridId);
                if (gridId == null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('격자 정보가 없습니다')));
                  return;
                }
                Navigator.pop(context, MapFocusTarget(gridId: gridId));
              },
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('피드백 위치로 이동'),
            ),
            const SizedBox(height: 12),
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
