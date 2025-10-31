import 'dart:ui';

import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/blog_service.dart';

// 카테고리 필터 관리
class CategoryFilterManager extends ValueNotifier<String?> {
  static final CategoryFilterManager _instance =
      CategoryFilterManager._internal();
  factory CategoryFilterManager() => _instance;
  CategoryFilterManager._internal() : super(null);

  void setCategory(String? category) {
    value = category;
  }

  void clearFilter() {
    value = null;
  }

  bool get isFiltered => value != null;
}

// 카테고리 아이템 (스와이프 액션 포함)
class _CategoryItemWithActions extends StatefulWidget {
  final Map<String, dynamic> category;
  final bool isOwnProfile;
  final BaseFeedProvider feedProvider;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryItemWithActions({
    required this.category,
    required this.isOwnProfile,
    required this.feedProvider,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_CategoryItemWithActions> createState() =>
      _CategoryItemWithActionsState();
}

class _CategoryItemWithActionsState extends State<_CategoryItemWithActions>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  late AnimationController _animationController;
  late Animation<double> _animation;
  double _startOffset = 0.0;

  void _animationListener() {
    if (!_animationController.isAnimating) return;

    setState(() {
      final targetOffset = -140.0;
      _dragOffset =
          _startOffset + (_animation.value) * (targetOffset - _startOffset);
    });
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          // 왼쪽으로만 밀기 지원 (primaryDelta가 음수)
          _dragOffset += details.primaryDelta!;
          // 오른쪽으로 밀리는 것 방지 및 왼쪽으로 제한
          if (_dragOffset > 0) _dragOffset = 0;
          if (_dragOffset < -200) _dragOffset = -200;
        });
      },
      onHorizontalDragEnd: (details) {
        final currentOffset = _dragOffset;

        // 버튼이 보이도록 충분히 밀렸는지 확인
        final needsToSlide = currentOffset > -100;

        if (needsToSlide) {
          // 리스너 중복 방지를 위해 기존 리스너 제거
          _animationController.removeListener(_animationListener);
          _animationController.addListener(_animationListener);
          _startOffset = currentOffset;
          _animationController.reset();
          _animationController.forward();
        } else {
          // 이미 충분히 밀렸으면 애니메이션만 추가
          _animationController.forward();
        }
      },
      onTap: () {
        // 탭은 항목 선택으로 처리
        if (_dragOffset != 0) {
          // 드래그 상태면 먼저 닫기
          setState(() {
            _dragOffset = 0.0;
          });
          _animationController.reverse();
        } else {
          widget.onTap();
        }
      },
      child: Stack(
        children: [
          // 수정 버튼 (드래그된 부분의 왼쪽, 파란색)
          if (_dragOffset < 0)
            Positioned(
              left: MediaQuery.of(context).size.width + _dragOffset,
              top: 0,
              bottom: 0,
              width: 70,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (_animation.value * 0.1),
                    child: child,
                  );
                },
                child: GestureDetector(
                  onTap: () {
                    widget.onEdit();
                    setState(() {
                      _dragOffset = 0.0;
                      _animationController.reverse();
                    });
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.edit,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),

          // 삭제 버튼 (오른쪽, 빨간색)
          if (_dragOffset < -70)
            Positioned(
              left: MediaQuery.of(context).size.width + _dragOffset + 70,
              top: 0,
              bottom: 0,
              width: 70,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (_animation.value * 0.1),
                    child: child,
                  );
                },
                child: GestureDetector(
                  onTap: () {
                    widget.onDelete();
                    setState(() {
                      _dragOffset = 0.0;
                      _animationController.reverse();
                    });
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.delete,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),

          // 메인 컨텐츠
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Material(
              color:
                  widget.isSelected
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (_dragOffset != 0) {
                    // 드래그 상태면 먼저 닫기
                    setState(() {
                      _dragOffset = 0.0;
                    });
                    _animationController.reverse();
                  } else {
                    widget.onTap();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.category['name'],
                          style: TextStyle(
                            fontWeight:
                                widget.isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${widget.category['postCount'] ?? 0}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
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

class CategoryDropDown {
  VoidCallback? _onCategoryChanged;

  /// 카테고리 변경 콜백 설정
  void setOnCategoryChanged(VoidCallback? callback) {
    _onCategoryChanged = callback;
  }

  /// 카테고리 드롭다운 표시 (BottomSheet)
  void showCategoryDropdown(
    BuildContext context,
    GlobalKey buttonKey,
    BaseFeedProvider feedProvider,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withOpacity(0.95),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.6),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      // 핸들 바
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(height: 12),

                      // 카테고리 리스트
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: _buildCategoryContent(context, feedProvider),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 카테고리 아이템 빌드
  Widget _buildCategoryItem({
    required String title,
    required int count,
    required bool isSelected,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return Material(
      color:
          isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 카테고리 드롭다운 내용 빌드
  Widget _buildCategoryContent(
    BuildContext context,
    BaseFeedProvider feedProvider,
  ) {
    final categories = feedProvider.categories;
    final postsByCategory = feedProvider.postsByCategory;
    final userInfo = feedProvider.userInfo;
    final isOwnProfile = userInfo?['isOwnProfile'] == true;

    print(
      '[CategoryDropDown] _buildCategoryContent - isOwnProfile: $isOwnProfile, categories: ${categories.length}개',
    );

    // 전체 포스트 수 계산
    final totalPosts = postsByCategory.values.fold<int>(
      0,
      (sum, posts) => sum + posts.length,
    );

    // 시스템 카테고리 포스트 수 계산
    final privatePosts = feedProvider.privatePostCount;
    final groupPosts = feedProvider.groupsPostCount;
    final publicPosts = feedProvider.publicPostCount;

    print(
      '[CategoryDropDown] 시스템 카테고리 포스트 수 - 나만보기: $privatePosts, 그룹공개: $groupPosts, 공개: $publicPosts',
    );
    print('[CategoryDropDown] isOwnProfile: $isOwnProfile');
    print(
      '[CategoryDropDown] shouldShowSystemCategories: ${isOwnProfile && (privatePosts > 0 || groupPosts > 0 || publicPosts > 0)}',
    );
    if (feedProvider.systemCategoryMappings != null) {
      print(
        '[CategoryDropDown] systemCategoryMappings 키들: ${feedProvider.systemCategoryMappings!.keys.toList()}',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 카테고리 생성 버튼은 본인 프로필일 때만 표시
        if (isOwnProfile) _buildCreateCategoryButton(context, feedProvider),

        // 전체 탭
        _buildCategoryItem(
          title: '전체',
          count: totalPosts,
          isSelected:
              feedProvider.selectedBase == BaseFilter.all &&
              feedProvider.selectedCategoryId == null,
          context: context,
          onTap: () {
            feedProvider.selectBase(BaseFilter.all);
            Navigator.of(context).pop();
            _onCategoryChanged?.call();
          },
        ),

        // 시스템 카테고리 구분선
        if (isOwnProfile &&
            (privatePosts > 0 || groupPosts > 0 || publicPosts > 0)) ...[
          // 나만보기
          Builder(
            builder: (_) {
              print(
                '[CategoryDropDown] 나만보기 렌더링 - privatePosts: $privatePosts',
              );
              if (privatePosts > 0) {
                return _buildCategoryItem(
                  title: '나만보기',
                  count: privatePosts,
                  isSelected:
                      feedProvider.selectedBase == BaseFilter.private &&
                      feedProvider.selectedCategoryId == null,
                  context: context,
                  onTap: () {
                    feedProvider.selectBase(BaseFilter.private);
                    Navigator.of(context).pop();
                    _onCategoryChanged?.call();
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // 그룹공유
          if (groupPosts > 0)
            _buildCategoryItem(
              title: '그룹공유',
              count: groupPosts,
              isSelected:
                  feedProvider.selectedBase == BaseFilter.groups &&
                  feedProvider.selectedCategoryId == null,
              context: context,
              onTap: () {
                feedProvider.selectBase(BaseFilter.groups);
                Navigator.of(context).pop();
                _onCategoryChanged?.call();
              },
            ),

          // 전체공개
          if (publicPosts > 0)
            _buildCategoryItem(
              title: '전체공개',
              count: publicPosts,
              isSelected:
                  feedProvider.selectedBase == BaseFilter.public &&
                  feedProvider.selectedCategoryId == null,
              context: context,
              onTap: () {
                feedProvider.selectBase(BaseFilter.public);
                Navigator.of(context).pop();
                _onCategoryChanged?.call();
              },
            ),
        ],

        // 사용자가 만든 카테고리
        ...categories
            .where((c) => !(c['isSystem'] == true))
            .map(
              (c) => _CategoryItemWithActions(
                category: c,
                isOwnProfile: isOwnProfile,
                feedProvider: feedProvider,
                isSelected:
                    feedProvider.selectedCategoryId == c['id'].toString(),
                onTap: () {
                  feedProvider.selectCategory(c['id'].toString());
                  Navigator.of(context).pop();
                  _onCategoryChanged?.call();
                },
                onEdit: () async {
                  // 카테고리 수정 로직
                  // TODO: 수정 다이얼로그 구현
                },
                onDelete: () {
                  if (feedProvider is MyProfileFeedProvider) {
                    _deleteCategory(context, feedProvider, c['id']);
                  }
                },
              ),
            ),

        // BottomSheet 하단 여백
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCreateCategoryButton(
    BuildContext context,
    BaseFeedProvider feedProvider,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(context).pop();
          final name = await showDialog<String?>(
            context: context,
            builder: (_) => const CategoryCreateDialog(),
          );

          if (name != null && name.trim().isNotEmpty) {
            await _createCategory(context, feedProvider, name.trim());
            _onCategoryChanged?.call();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '새 카테고리 만들기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 카테고리 생성 (서버 API 호출)
  Future<void> _createCategory(
    BuildContext context,
    BaseFeedProvider feedProvider,
    String name,
  ) async {
    try {
      print('[CategoryDropDown] 카테고리 생성 시작: $name');

      // 0) 입력값 검증: 공백/중복/예약어(system_doppy_uncategorized) 금지
      final trimmed = name.trim();
      final lower = trimmed.toLowerCase();
      if (trimmed.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('카테고리 이름을 입력해 주세요')));
        }
        return;
      }
      const reserved = {'system_doppy_uncategorized'};
      if (reserved.contains(lower)) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('해당 이름은 사용할 수 없습니다')));
        }
        return;
      }
      final existingNames =
          feedProvider.categories
              .map((c) => (c['name']?.toString() ?? '').trim().toLowerCase())
              .toSet();
      if (existingNames.contains(lower)) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('이미 존재하는 카테고리입니다')));
        }
        return;
      }

      // 서버에 카테고리 생성 요청 (한 번만)
      final blogService = BlogService();
      final created = await blogService.createCategory(
        name: trimmed,
        isPrivate: false,
        description: '$trimmed 카테고리',
      );
      print('[CategoryDropDown] 카테고리 생성 성공');
      final newId = (created['data']?['id'] as int?) ?? -1;
      await feedProvider.refresh();
      if (newId != -1) {
        final ids = feedProvider.categories
            .map<int>((c) => (c['id'] as int))
            .toList(growable: true);
        // 0(미분류)이 섞여 있다면 항상 맨 뒤로 보장
        final hasZero = ids.contains(0);
        final withoutZero = ids.where((id) => id != 0).toList(growable: true);
        // 새 카테고리를 맨 앞에
        withoutZero.remove(newId);
        final ordered = <int>[newId, ...withoutZero];
        if (hasZero) ordered.add(0);

        // TODO: 카테고리 재정렬 API 연동 시 구현
      }
      _onCategoryChanged?.call();

      // 성공 메시지 (위젯 생명주기 안전 처리)
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('카테고리 "$trimmed"이 생성되었습니다')));
      }
    } catch (e) {
      print('[CategoryDropDown] 카테고리 생성 에러: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('카테고리 생성 중 오류가 발생했습니다')));
      }
    }
  }

  /// 카테고리 삭제 (서버 API 호출)
  Future<void> _deleteCategory(
    BuildContext context,
    MyProfileFeedProvider myProfileFeedProvider,
    int categoryId,
  ) async {
    try {
      print('[CategoryDropDown] 카테고리 삭제 시작: $categoryId');

      // 서버에 카테고리 삭제 요청
      final blogService = BlogService();
      await blogService.deleteCategory(categoryId);

      print('[CategoryDropDown] 카테고리 삭제 성공');
      // 전체 피드 데이터 강제 재로딩 (카테고리/포스트 등 전부)
      await myProfileFeedProvider.refresh();
      _onCategoryChanged?.call();

      // 성공 메시지
      _showSnackBarSafely(context, '카테고리가 삭제되었습니다');
    } catch (e) {
      print('[CategoryDropDown] 카테고리 삭제 에러: $e');
      _showSnackBarSafely(context, '카테고리 삭제 중 오류가 발생했습니다');
    }
  }

  /// 안전한 SnackBar 표시 (Scaffold가 없을 때 오류 방지)
  void _showSnackBarSafely(BuildContext context, String message) {
    try {
      // context가 유효하고 Scaffold가 있는지 확인
      if (context.mounted) {
        ErrorHandler.showInfo(context, message);
      }
    } catch (e) {
      // 오류 발생 시 콘솔에만 출력
      print('[CategoryDropDown] SnackBar 표시 오류: $e - 메시지: $message');
    }
  }
}

class CategoryCreateDialog extends StatefulWidget {
  const CategoryCreateDialog({super.key});

  @override
  State<CategoryCreateDialog> createState() => _CategoryCreateDialogState();
}

class _CategoryCreateDialogState extends State<CategoryCreateDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: '카테고리 이름',
          hintStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<String?>(null),
          child: Text('취소'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop<String?>(name);
          },
          child: const Text('생성'),
        ),
      ],
    );
  }
}
