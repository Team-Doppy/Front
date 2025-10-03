import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/data/services/mention_service.dart';
import 'package:doppy/data/services/search_service.dart';

class MentionOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final void Function(String username)? onSelect; // 단건 선택 (호환)
  final void Function(List<String> usernames)? onSubmit; // 누적 제출

  const MentionOverlay({super.key, this.onClose, this.onSelect, this.onSubmit});

  @override
  State<MentionOverlay> createState() => _MentionOverlayState();
}

class _MentionOverlayState extends State<MentionOverlay> {
  final TextEditingController _controller = TextEditingController(text: '');
  final FocusNode _focusNode = FocusNode();

  // 서비스 참조
  late final MentionService _mentionService;
  late final SearchService _searchService;

  List<_UserChip> _results = const [];
  final List<_UserChip> _selected = <_UserChip>[];
  bool _loading = false;
  DateTime? _lastQueryAt;

  @override
  void initState() {
    super.initState();

    // 서비스 초기화
    _mentionService = MentionService();
    _searchService = SearchService();

    // 언급 서비스 초기화 및 최근 언급 대상 로드
    _initializeServices();

    // 키보드 자동 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _initializeServices() async {
    await _mentionService.initialize();
    _loadRecentMentions();
  }

  void _loadRecentMentions() {
    final recentUsers = _mentionService.mentionHistoryAsUsers;
    _results =
        recentUsers
            .map(
              (user) => _UserChip(
                username: user.username,
                imageUrl: user.profileImageUrl,
                alias: user.alias,
              ),
            )
            .toList();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // 배경 블러 + 반투명
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                onVerticalDragEnd: (d) {
                  if (d.primaryVelocity != null && d.primaryVelocity! > 400) {
                    Navigator.of(context).pop();
                  }
                },
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    color: const Color.fromARGB(182, 144, 144, 144),
                  ),
                ),
              ),
            ),

            // 상단 닫기(X) 버튼
            Positioned(
              top: 12,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),

            // 상단 입력 영역 (링크 오버레이 유사)
            Positioned(
              top: 25,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            cursorColor: AppColors.darkTextPrimary,
                            style: TextStyle(
                              color: AppColors.darkTextPrimary,
                              fontSize: 18,
                            ),

                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                Icons.alternate_email,
                                color: AppColors.darkTextPrimary,
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: AppColors.darkSurface.withOpacity(
                                0.35,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 0,
                              ),
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              hintText: '사용자 검색',
                              hintStyle: TextStyle(
                                color: AppColors.darkTextPrimary.withOpacity(
                                  0.5,
                                ),
                              ),
                            ),
                            onChanged: _onQueryChanged,
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      InkWell(
                        onTap: _addCurrent,
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurface.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 중간: 실시간 검색 결과 (원형 미리보기, 가로 스크롤)
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              height: 140,
              child:
                  _loading
                      ? ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemBuilder: (_, i) => _LoadingCircleUser(),
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemCount: 6, // 로딩 중일 때 6개 표시
                      )
                      : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemBuilder: (_, i) {
                          final item = _results[i];
                          final bool selected = _selected.any(
                            (s) => s.username == item.username,
                          );
                          final bool isRecentMention = _controller.text.isEmpty;
                          return _CircleUser(
                            user: item,
                            selected: selected,
                            isRecentMention: isRecentMention,
                            onTap: () => _toggleSelect(item),
                            onRemove:
                                isRecentMention
                                    ? () => _removeFromRecent(item)
                                    : null,
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemCount: _results.length,
                      ),
            ),

            // 하단: 선택 누적 + 언급하기 버튼
            Positioned(
              top: 260,
              left: 0,
              right: 0,
              bottom: 70,
              child: Column(
                children: [
                  if (_selected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemBuilder:
                            (_, i) => _SelectedRowChip(
                              label: _selected[i].username,
                              onRemove: () => _toggleSelect(_selected[i]),
                            ),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: _selected.length,
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _selected.isEmpty ? null : _submit,
                    child: const Text(
                      '언급하기',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onQueryChanged(String q) {
    setState(() => _loading = true);
    final now = DateTime.now();
    _lastQueryAt = now;

    Future.delayed(const Duration(milliseconds: 220), () async {
      if (_lastQueryAt != now) return; // 최신 쿼리만 반영

      final String qq = q.trim().toLowerCase();
      List<_UserChip> next;

      if (qq.isEmpty) {
        // 검색어가 비어있으면 최근 언급 대상 표시
        next =
            _mentionService.mentionHistoryAsUsers
                .map(
                  (user) => _UserChip(
                    username: user.username,
                    imageUrl: user.profileImageUrl,
                    alias: user.alias,
                  ),
                )
                .toList();
      } else {
        // 실제 검색 수행
        _searchService.onSearchChanged(qq);
        await Future.delayed(const Duration(milliseconds: 300)); // 검색 완료 대기
        final searchResults = _searchService.searchingAccounts;

        // 검색 결과를 _UserChip 형태로 변환
        next =
            searchResults
                .map(
                  (item) => _UserChip(
                    username: item.username ?? '',
                    imageUrl: item.profileImageUrl ?? '',
                    alias: item.alias ?? item.username ?? '',
                  ),
                )
                .toList();
      }

      if (mounted) {
        setState(() {
          _results = next;
          _loading = false;
        });
      }
    });
  }

  void _toggleSelect(_UserChip user) {
    final idx = _selected.indexWhere((s) => s.username == user.username);
    setState(() {
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(user);
      }
    });
  }

  void _submit() {
    if (_selected.isEmpty) return;

    // 선택된 사용자들을 언급 기록에 추가
    for (final user in _selected) {
      _mentionService.addToHistory(
        MentionUser(
          username: user.username,
          alias: user.alias ?? user.username,
          profileImageUrl: user.imageUrl ?? '',
        ),
      );
    }

    widget.onSubmit?.call(_selected.map((e) => e.username).toList());
    for (final u in _selected) {
      widget.onSelect?.call(u.username);
    }
    Navigator.of(context).maybePop();
  }

  void _addCurrent() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    // 결과 중 일치하는 항목을 선택, 없으면 새 사용자명으로 추가
    final match = _results.firstWhere(
      (u) => u.username.toLowerCase() == q.toLowerCase(),
      orElse: () => _UserChip(username: q, imageUrl: null, alias: q),
    );
    _toggleSelect(match);
    _controller.clear();
    _onQueryChanged('');
  }

  void _removeFromRecent(_UserChip user) {
    _mentionService.removeFromHistory(user.username);
    _loadRecentMentions();
  }
}

// (old _MentionChip removed in favor of _CircleUser)

class _UserChip {
  final String username;
  final String? imageUrl;
  final String? alias;
  const _UserChip({required this.username, this.imageUrl, this.alias});
}

class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  const _Glass({required this.child, this.padding, this.borderRadius = 12});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white24),
          ),
          child: child,
        ),
      ),
    );
  }
}

// (old horizontal chip no longer used; replaced by _SelectedRowChip)

class _CircleUser extends StatelessWidget {
  final _UserChip user;
  final bool selected;
  final bool isRecentMention;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _CircleUser({
    required this.user,
    required this.selected,
    required this.isRecentMention,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.darkSurfaceVariant,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.darkBorder,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: const Icon(
                  Icons.person,
                  color: AppColors.darkTextSecondary,
                ),
              ),
              // 최근 언급 대상일 때만 X 버튼 표시
              if (isRecentMention && onRemove != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 80,
            child: Text(
              user.alias ?? user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.darkTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedRowChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _SelectedRowChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      borderRadius: 10,
      child: Row(
        children: [
          const Icon(Icons.alternate_email, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: Colors.white70, size: 16),
          ),
        ],
      ),
    );
  }
}

class _LoadingCircleUser extends StatefulWidget {
  const _LoadingCircleUser();

  @override
  State<_LoadingCircleUser> createState() => _LoadingCircleUserState();
}

class _LoadingCircleUserState extends State<_LoadingCircleUser>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.darkSurfaceVariant.withOpacity(
                  _animation.value,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceVariant.withOpacity(
                  _animation.value,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        );
      },
    );
  }
}
