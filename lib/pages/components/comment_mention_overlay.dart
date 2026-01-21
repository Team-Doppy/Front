import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/models/mention_user.dart';
import 'package:doppy/data/services/mention_service.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:flutter/material.dart';

/// 🎯 댓글 멘션 오버레이 (입력란 위에 표시)
class CommentMentionOverlay extends StatefulWidget {
  final String searchQuery;
  final void Function(String username) onSelect;
  final VoidCallback? onClose;
  final CommentService? commentService; // 🎯 채팅 참여자 목록 가져오기용

  const CommentMentionOverlay({
    Key? key,
    required this.searchQuery,
    required this.onSelect,
    this.onClose,
    this.commentService, // 🎯 채팅 참여자 목록 가져오기용
  }) : super(key: key);

  @override
  State<CommentMentionOverlay> createState() => _CommentMentionOverlayState();
}

class _CommentMentionOverlayState extends State<CommentMentionOverlay>
    with SingleTickerProviderStateMixin {
  final SearchService _searchService = SearchService();
  List<MentionUser> _users = [];
  DateTime? _lastQueryAt;
  bool _isInitialized = false;
  String _currentSearchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // ✅ 애니메이션 컨트롤러 초기화
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // ✅ SearchService 리스너 등록 (결과 업데이트 시 즉시 반영)
    _searchService.addListener(_onSearchServiceChanged);

    // ✅ @가 포함되어 있으면 즉시 애니메이션 시작 (@만 입력해도 표시)
    if (widget.searchQuery.contains('@')) {
      _animationController.forward();
    }

    _initializeAndSearch();
  }

  @override
  void dispose() {
    // ✅ 리스너 제거
    _searchService.removeListener(_onSearchServiceChanged);
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CommentMentionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      // ✅ @를 제거한 후 검색어가 비어있으면 사라지는 애니메이션, 있으면 나타나는 애니메이션
      final queryWithoutAt = widget.searchQuery.replaceAll('@', '').trim();
      if (queryWithoutAt.isEmpty && widget.searchQuery.isEmpty) {
        // 완전히 비어있을 때만 사라지는 애니메이션
        _animationController.reverse();
      } else {
        // @만 입력했거나 검색어가 있으면 나타나는 애니메이션
        _animationController.forward();
      }
      _searchUsers(widget.searchQuery);
    }
  }

  /// ✅ SearchService 결과 변경 시 즉시 반영
  void _onSearchServiceChanged() {
    if (_currentSearchQuery.isEmpty) return;

    final searchResults = _searchService.searchingAccounts;
    if (!mounted) return;

    setState(() {
      _users =
          searchResults
              .map(
                (item) => MentionUser(
                  username: item.username ?? '',
                  alias: item.alias ?? item.username ?? '',
                  profileImageUrl: item.profileImageUrl ?? '',
                ),
              )
              .toList();
    });
  }

  Future<void> _initializeAndSearch() async {
    if (_isInitialized) {
      _searchUsers(widget.searchQuery);
      return;
    }

    final mentionService = MentionService();
    await mentionService.initialize();
    _isInitialized = true;

    _searchUsers(widget.searchQuery);
  }

  Future<void> _searchUsers(String query) async {
    final now = DateTime.now();
    _lastQueryAt = now;

    // ✅ @ 기호를 제거한 후 검색어 확인
    final q = query.replaceAll('@', '').trim().toLowerCase();

    // ✅ 검색어가 비어있으면 (예: @만 입력한 경우) 디바운싱 없이 즉시 표시
    if (q.isEmpty) {
      try {
        // 🎯 검색어가 비어있으면 채팅 참여자 목록 표시
        List<MentionUser> suggestedUsers = [];

        // 채팅 참여자 목록 가져오기 (댓글 작성자들)
        if (widget.commentService != null) {
          final comments = widget.commentService!.getAllComments();
          final authorMap =
              <
                String,
                Map<String, String>
              >{}; // username -> {author, profileImageUrl}

          // 모든 댓글과 대댓글에서 작성자 추출
          for (final comment in comments) {
            if (comment.author.isNotEmpty) {
              authorMap[comment.author] = {
                'author': comment.author,
                'profileImageUrl': comment.authorProfileImageUrl,
              };
            }
            // 대댓글도 포함
            for (final reply in comment.replies) {
              if (reply.author.isNotEmpty) {
                authorMap[reply.author] = {
                  'author': reply.author,
                  'profileImageUrl': reply.authorProfileImageUrl,
                };
              }
            }
          }

          // MentionUser 리스트로 변환
          suggestedUsers =
              authorMap.values.map((authorData) {
                return MentionUser(
                  username: authorData['author'] ?? '',
                  alias: authorData['author'] ?? '',
                  profileImageUrl: authorData['profileImageUrl'] ?? '',
                );
              }).toList();
        }

        // 채팅 참여자가 없으면 최근 언급 대상 표시 (폴백)
        if (suggestedUsers.isEmpty) {
          final mentionService = MentionService();
          if (!_isInitialized) {
            await mentionService.initialize();
            _isInitialized = true;
          }
          suggestedUsers = mentionService.mentionHistoryAsUsers;
        }

        if (mounted && _lastQueryAt == now) {
          setState(() {
            _users = suggestedUsers;
          });
        }
      } catch (e) {
        // 에러 발생 시 빈 리스트로 설정
        if (mounted && _lastQueryAt == now) {
          setState(() {
            _users = [];
          });
        }
      }
      return;
    }

    // ✅ 검색어가 있을 때: SearchService의 debounce만 사용 (추가 디바운싱 제거)
    _currentSearchQuery = q;

    try {
      // ✅ SearchService를 직접 사용 (내부적으로 300ms debounce 적용)
      // 리스너를 통해 결과가 업데이트되면 자동으로 _onSearchServiceChanged 호출
      _searchService.onSearchChanged(q);
    } catch (e) {
      // 에러 발생 시 빈 리스트로 설정
      if (mounted && _lastQueryAt == now) {
        setState(() {
          _users = [];
        });
      }
    }
  }

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Material(
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          color: Theme.of(context).colorScheme.surface,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: Container(
              width: double.infinity, // 화면 전체 너비
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(context).size.height * 0.3, // 검색 중일 때는 더 높게
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 헤더 (닫기 버튼만)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 8,
                      right: 8,
                      top: 8,
                      bottom: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 닫기 버튼
                        if (widget.onClose != null)
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 22,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                            ),
                            onPressed: _handleClose,
                          ),
                      ],
                    ),
                  ),

                  // 리스트
                  Flexible(
                    child:
                        _users.isEmpty
                            ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  '결과가 없어요',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.6),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            )
                            : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 4,
                              ),
                              itemCount: _users.length,
                              separatorBuilder:
                                  (context, index) => Divider(
                                    height: 1,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.1),
                                  ),
                              itemBuilder: (context, index) {
                                final user = _users[index];
                                return _UserTile(
                                  user: user,
                                  onTap: () async {
                                    // 멘션 기록에 추가
                                    final mentionService = MentionService();
                                    if (!_isInitialized) {
                                      await mentionService.initialize();
                                      _isInitialized = true;
                                    }
                                    mentionService.addToHistory(user);
                                    widget.onSelect(user.username);
                                  },
                                );
                              },
                            ),
                  ),

                  const SizedBox(height: 15),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 🎯 사용자 타일 위젯
class _UserTile extends StatelessWidget {
  final MentionUser user;
  final VoidCallback onTap;

  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          child: Row(
            children: [
              // 프로필 아바타
              CommonProfileAvatar(
                imageUrl: user.profileImageUrl,
                username: user.username,
                size: 40,
                borderWidth: 0,
              ),
              const SizedBox(width: 12),

              // 사용자 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.alias.isNotEmpty ? user.alias : user.username,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (user.alias.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
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
