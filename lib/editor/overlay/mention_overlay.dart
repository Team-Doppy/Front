import 'dart:ui';

import 'package:doppy/data/models/mention_user.dart';
import 'package:doppy/data/services/mention_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/data/services/search_service.dart';

class MentionOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final void Function(String username)? onSelect; // 단건 선택 (호환)
  final void Function(List<String> usernames)? onSubmit; // 누적 제출
  final List<String>? initialUsernames; // 초기 선택된 사용자들 (편집 시 사용)

  const MentionOverlay({
    super.key,
    this.onClose,
    this.onSelect,
    this.onSubmit,
    this.initialUsernames,
  });

  @override
  State<MentionOverlay> createState() => _MentionOverlayState();
}

class _MentionOverlayState extends State<MentionOverlay>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController(text: '');
  final FocusNode _focusNode = FocusNode();

  // 서비스 참조
  late final MentionService _mentionService;
  late final SearchService _searchService;

  List<_UserChip> _results = const [];
  final List<_UserChip> _selected = <_UserChip>[];
  bool _loading = false;
  DateTime? _lastQueryAt;
  bool _showRecentList = true; // 기록 리스트 토글 상태 (처음엔 열림, 선택 추가 후부터 닫힘)
  bool _hasAnimatedRecentList = false; // 기록 리스트 애니메이션 적용 여부
  bool _isQuickClose = false; // 빠른 닫기 플래그 (사용자 추가 시)

  // 드래그 관련 상태
  double _dragStartY = 0.0;
  double _dragStartX = 0.0;
  bool _isDragging = false;

  // 페이드 애니메이션
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  // 기록 리스트 슬라이드 다운 애니메이션
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // 페이드 애니메이션 초기화
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    // 슬라이드 다운 애니메이션 초기화
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3), // 위에서 시작
      end: Offset.zero, // 원래 위치
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    // 기록 리스트가 있고 토글이 켜져 있으면 처음 한 번만 애니메이션 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_results.isNotEmpty &&
          _showRecentList &&
          mounted &&
          !_hasAnimatedRecentList) {
        _slideController.forward();
        _hasAnimatedRecentList = true;
      }
    });

    // 서비스 초기화
    _mentionService = MentionService();
    _searchService = SearchService();

    // 언급 서비스 초기화 및 최근 언급 대상 로드
    _initializeServices();

    // 기본으로 최근 언급 대상 로드 (아래에 표시될 수 있도록)
    _loadRecentMentions();

    // 초기 선택된 사용자들 추가 (편집 시)
    if (widget.initialUsernames != null &&
        widget.initialUsernames!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialSelectedUsers(widget.initialUsernames!);
      });
    }

    // 키보드 자동 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _initializeServices() async {
    await _mentionService.initialize();
    _loadRecentMentions();
  }

  void _loadInitialSelectedUsers(List<String> usernames) async {
    final selectedChips = <_UserChip>[];

    // 먼저 히스토리에서 찾기
    final historyUsers = _mentionService.mentionHistoryAsUsers;
    final historyMap = <String, MentionUser>{};
    for (final user in historyUsers) {
      historyMap[user.username] = user;
    }

    // 각 username에 대해 정보 찾기
    for (final username in usernames) {
      if (historyMap.containsKey(username)) {
        final user = historyMap[username]!;
        selectedChips.add(
          _UserChip(
            username: user.username,
            imageUrl: user.profileImageUrl,
            alias: user.alias,
          ),
        );
      } else {
        // 히스토리에 없으면 기본 정보로 추가
        selectedChips.add(
          _UserChip(username: username, imageUrl: null, alias: username),
        );
      }
    }

    if (mounted) {
      setState(() {
        _selected.addAll(selectedChips);
      });
    }
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
      // 기록 리스트가 있고 토글이 켜져 있고, 아직 애니메이션을 하지 않았으면 슬라이드 애니메이션 시작
      if (_results.isNotEmpty &&
          _showRecentList &&
          _controller.text.trim().isEmpty &&
          !_hasAnimatedRecentList) {
        _slideController.forward();
        _hasAnimatedRecentList = true;
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = _controller.text.trim().isNotEmpty;
    // 토글로 기록 리스트 표시 여부 결정 (검색어가 없고 기록이 있고, 토글이 켜져 있을 때)
    final bool showRecentList =
        _showRecentList && !hasQuery && _results.isNotEmpty;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: AppBar(
            backgroundColor: const Color(0xFF2D2D2D).withOpacity(0.9),
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,

            title: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: TextField(
                cursorColor: AppColors.darkTextPrimary,
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                keyboardAppearance: Brightness.light,
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 18,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  hintText: context.tr('who_to_mention'),
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  suffixIcon:
                      _controller.text.isEmpty && _results.isNotEmpty
                          ? IconButton(
                            tooltip:
                                _showRecentList
                                    ? context.tr('hide_recent_list')
                                    : context.tr('show_recent_list'),
                            onPressed: () {
                              final wasShowing = _showRecentList;
                              setState(() {
                                _showRecentList = !_showRecentList;
                                // 토글 버튼으로 열고 닫을 때는 부드럽게 (빠른 닫기 플래그 해제)
                                _isQuickClose = false;
                              });
                              // 펼쳐질 때 애니메이션
                              if (_showRecentList && !wasShowing) {
                                _slideController.reset();
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    _slideController.forward();
                                  }
                                });
                              }
                              // 닫힐 때도 부드러운 애니메이션
                              else if (!_showRecentList && wasShowing) {
                                _slideController.reverse();
                              }
                            },
                            icon: AnimatedRotation(
                              turns:
                                  _showRecentList
                                      ? 0
                                      : 0.5, // 열려있을 때 아래(0), 닫혀있을 때 위(0.5)
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.white.withOpacity(0.8),
                                size: 24,
                              ),
                            ),
                          )
                          : _controller.text.isNotEmpty
                          ? IconButton(
                            tooltip: context.tr('search'),
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                            },
                            icon: Icon(
                              Icons.search,
                              color: Colors.white.withOpacity(0.8),
                              size: 22,
                            ),
                          )
                          : null,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  isDense: true,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            actions: [
              GestureDetector(
                onTap: _closeWithAnimation,
                child: Icon(
                  Icons.close,
                  color: Colors.white.withOpacity(0.7),
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),

      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onPanStart: (details) {
          _dragStartY = details.globalPosition.dy;
          _dragStartX = details.globalPosition.dx;
          _isDragging = true;
        },
        onPanUpdate: (details) {
          if (!_isDragging) return;

          final currentY = details.globalPosition.dy;
          final currentX = details.globalPosition.dx;
          final deltaY = currentY - _dragStartY;
          final deltaX = (currentX - _dragStartX).abs();

          // 아래로 50px 이상 드래그하면 바로 닫기
          if (deltaY > 50) {
            _isDragging = false;
            _closeWithAnimation();
            return;
          }

          // 좌우로 50px 이상 드래그하면 바로 닫기
          if (deltaX > 50) {
            _isDragging = false;
            _closeWithAnimation();
            return;
          }
        },
        onPanEnd: (details) {
          if (!_isDragging) return;

          // 드래그 속도에 따라 오버레이 닫기
          final velocity = details.velocity.pixelsPerSecond;
          if (velocity.dy.abs() > velocity.dx.abs()) {
            // 세로 드래그 (아래로)
            if (velocity.dy > 200) {
              _closeWithAnimation();
            }
          } else {
            // 가로 드래그 (좌우)
            if (velocity.dx.abs() > 200) {
              _closeWithAnimation();
            }
          }
          _isDragging = false;
        },
        child: Stack(
          children: [
            // 배경 블러 + 반투명
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeWithAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Container(
                      color: const Color(0xFF2D2D2D).withOpacity(0.9),
                    ),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // 검색창 바로 밑에 기록 리스트 또는 검색 결과 표시
                  AnimatedSize(
                    duration:
                        _isQuickClose
                            ? const Duration(milliseconds: 100)
                            : const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: SizedBox(
                      key: ValueKey(
                        'history_list_${showRecentList}_${hasQuery}',
                      ),
                      height: hasQuery ? 140 : (showRecentList ? 140 : 0),
                      child:
                          hasQuery
                              ? (_loading
                                  ? ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    itemBuilder:
                                        (_, i) => const _LoadingCircleUser(),
                                    separatorBuilder:
                                        (_, __) => const SizedBox(width: 8),
                                    itemCount: 6,
                                  )
                                  : (_results.isNotEmpty
                                      ? ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        itemBuilder: (_, i) {
                                          final item = _results[i];
                                          final bool selected = _selected.any(
                                            (s) => s.username == item.username,
                                          );
                                          return _CircleUser(
                                            user: item,
                                            selected: selected,
                                            isRecentMention: showRecentList,
                                            onTap: () => _toggleSelect(item),
                                            onRemove:
                                                showRecentList
                                                    ? () {
                                                      if (selected) {
                                                        _toggleSelect(item);
                                                      }
                                                    }
                                                    : null,
                                          );
                                        },
                                        separatorBuilder:
                                            (_, __) => const SizedBox(width: 8),
                                        itemCount: _results.length,
                                      )
                                      : Center(
                                        child: Text(
                                          context.tr('no_search_results'),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      )))
                              : (!hasQuery && _results.isNotEmpty
                                  ? SlideTransition(
                                    position: _slideAnimation,
                                    child:
                                        showRecentList
                                            ? (_loading
                                                ? ListView.separated(
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                      ),
                                                  itemBuilder:
                                                      (_, i) =>
                                                          const _LoadingCircleUser(),
                                                  separatorBuilder:
                                                      (_, __) => const SizedBox(
                                                        width: 8,
                                                      ),
                                                  itemCount: 6,
                                                )
                                                : (_results.isNotEmpty
                                                    ? ListView.separated(
                                                      scrollDirection:
                                                          Axis.horizontal,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                          ),
                                                      itemBuilder: (_, i) {
                                                        final item =
                                                            _results[i];
                                                        final bool selected =
                                                            _selected.any(
                                                              (s) =>
                                                                  s.username ==
                                                                  item.username,
                                                            );
                                                        return _CircleUser(
                                                          user: item,
                                                          selected: selected,
                                                          isRecentMention:
                                                              showRecentList,
                                                          onTap:
                                                              () =>
                                                                  _toggleSelect(
                                                                    item,
                                                                  ),
                                                          onRemove:
                                                              showRecentList
                                                                  ? () {
                                                                    if (selected) {
                                                                      _toggleSelect(
                                                                        item,
                                                                      );
                                                                    }
                                                                  }
                                                                  : null,
                                                        );
                                                      },
                                                      separatorBuilder:
                                                          (_, __) =>
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                      itemCount:
                                                          _results.length,
                                                    )
                                                    : Center(
                                                      child: Text(
                                                        context.tr(
                                                          'no_search_results',
                                                        ),
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                    )))
                                            : const SizedBox.shrink(),
                                  )
                                  : const SizedBox.shrink()),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      child:
                          _selected.isNotEmpty
                              ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        itemBuilder:
                                            (_, i) => _AnimatedSelectedRowChip(
                                              index: i,
                                              child: _SelectedRowChip(
                                                label: _selected[i].username,
                                                onRemove:
                                                    () => _toggleSelect(
                                                      _selected[i],
                                                    ),
                                              ),
                                            ),
                                        separatorBuilder:
                                            (_, __) =>
                                                const SizedBox(height: 8),
                                        itemCount: _selected.length,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                              : Container(),
                    ),
                  ),
                  // 선택된 사람이 있을 때만 버튼 표시
                  if (_selected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          minimumSize: Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: _submit,
                        child: Text(
                          context.tr('mention'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  SizedBox(height: 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closeWithAnimation() {
    _fadeController.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _onQueryChanged(String q) {
    setState(() => _loading = true);
    final now = DateTime.now();
    _lastQueryAt = now;

    final String qq = q.trim().toLowerCase();

    Future.delayed(const Duration(milliseconds: 220), () async {
      if (_lastQueryAt != now) return; // 최신 쿼리만 반영

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

        // 기록 리스트가 나타나고 토글이 켜져 있고, 아직 애니메이션을 하지 않았으면 슬라이드 애니메이션 시작
        if (next.isNotEmpty &&
            qq.isEmpty &&
            _showRecentList &&
            !_hasAnimatedRecentList) {
          _slideController.forward();
          _hasAnimatedRecentList = true;
        }
        // 검색 결과는 슬라이드 애니메이션 적용하지 않음 (shimmer에서 바로 전환)
      }
    });
  }

  void _toggleSelect(_UserChip user) {
    final idx = _selected.indexWhere((s) => s.username == user.username);
    final bool wasSelected = idx >= 0;
    final bool wasShowingRecentList = _showRecentList;

    setState(() {
      if (wasSelected) {
        _selected.removeAt(idx);
      } else {
        _selected.add(user);
        // 한 명이라도 추가되면 기록 리스트 숨기기
        _showRecentList = false;
        // 사용자 추가 시 빠른 닫기 플래그 설정
        if (wasShowingRecentList) {
          _isQuickClose = true;
        }
      }
    });

    // 새로 추가된 경우: 검색을 종료하고 기록 리스트로 전환
    if (!wasSelected) {
      // 빠른 닫기: 슬라이드 컨트롤러를 빠르게 닫기
      if (wasShowingRecentList) {
        _slideController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
        // 빠른 닫기 후 플래그 리셋
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _isQuickClose = false;
            });
          }
        });
      }
      _controller.clear();
      _onQueryChanged('');
      // 포커스 유지로 추가를 연속할 수 있게 함
      _focusNode.requestFocus();
    }

    // 선택된 사용자가 모두 제거되면 기록 리스트 다시 표시
    if (_selected.isEmpty) {
      setState(() {
        _showRecentList = true;
        // 애니메이션 플래그 리셋하여 다시 열릴 수 있게 함
        _hasAnimatedRecentList = false;
        _isQuickClose = false; // 빠른 닫기 플래그 리셋
      });
      // 기록 리스트 슬라이드 애니메이션 시작
      _slideController.reset();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _results.isNotEmpty && _controller.text.trim().isEmpty) {
          _slideController.forward();
          _hasAnimatedRecentList = true;
        }
      });
    }
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

    // 기록 업데이트
    _loadRecentMentions();

    widget.onSubmit?.call(_selected.map((e) => e.username).toList());
    for (final u in _selected) {
      widget.onSelect?.call(u.username);
    }

    // 언급 제출 후 선택 초기화
    setState(() {
      _selected.clear();
      _controller.clear();
    });

    // 노드가 추가되고 렌더링이 완료된 후 부드럽게 닫기
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 추가 프레임 대기로 노드 렌더링 완료 보장
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          _closeWithAnimation();
        }
      });
    });
  }
}

// (old _MentionChip removed in favor of _CircleUser)

class _UserChip {
  final String username;
  final String? imageUrl;
  final String? alias;
  const _UserChip({required this.username, this.imageUrl, this.alias});
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
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: selected ? AppColors.primary : Colors.transparent,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: CommonProfileAvatar(
                    username: user.username,
                    size: 80,
                    borderWidth: 1,
                    borderColor:
                        selected ? AppColors.primary : Colors.transparent,
                    imageUrl: user.imageUrl,
                  ),
                ),
              ),
              // 최근 언급 대상일 때만 X 버튼 표시
              if (isRecentMention && onRemove != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: Icon(
                        Icons.close,
                        color: Colors.white.withOpacity(0.7),
                        size: 17,
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

class _AnimatedSelectedRowChip extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedSelectedRowChip({required this.index, required this.child});

  @override
  State<_AnimatedSelectedRowChip> createState() =>
      _AnimatedSelectedRowChipState();
}

class _AnimatedSelectedRowChipState extends State<_AnimatedSelectedRowChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // 인덱스 기반 지연 (각 아이템이 순차적으로 나타남)
    final delay = widget.index * 30; // 30ms씩 지연 (더 빠르게)
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(delay / 300, 1.0, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-0.2, 0.0), // 왼쪽에서 슬라이드
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(delay / 300, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // 애니메이션 시작
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

class _SelectedRowChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _SelectedRowChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),

      child: Row(
        children: [
          Icon(Icons.alternate_email, color: Colors.white, size: 20),

          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
              child: Text(
                context.tr('cancel'),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
      begin: 0.4,
      end: 0.8,
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
                color: Colors.white.withOpacity(
                  0.15 + (_animation.value * 0.15), // 0.15 ~ 0.3 범위로 더 밝게
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(
                  0.15 + (_animation.value * 0.15), // 0.15 ~ 0.3 범위로 더 밝게
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
