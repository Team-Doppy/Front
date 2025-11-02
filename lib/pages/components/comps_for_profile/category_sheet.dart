import 'dart:ui';

import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
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

class _CategoryItemWithActionsState extends State<_CategoryItemWithActions> {
  double _dragOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
        // 스냅: 일정 이상 밀리면 고정(-140), 아니면 원위치(0)
        const double openThreshold = -30.0;
        setState(() {
          _dragOffset = (_dragOffset <= openThreshold) ? -140.0 : 0.0;
        });
      },
      onTap: () {
        // 탭은 항목 선택으로 처리
        if (_dragOffset != 0) {
          // 드래그 상태면 먼저 닫기
          setState(() {
            _dragOffset = 0.0;
          });
          // no-op
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
              child: GestureDetector(
                onTap: () async {
                  // 먼저 원위치로 복귀
                  setState(() => _dragOffset = 0.0);
                  // 공통 입력 다이얼로그 사용
                  widget.onEdit();
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.2),
                  ),
                  child: Text(
                    '수정',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),

          // 삭제 버튼 (오른쪽, 빨간색)
          if (_dragOffset < -40)
            Positioned(
              left: MediaQuery.of(context).size.width + _dragOffset + 70,
              top: 0,
              bottom: 0,
              width: 70,
              child: GestureDetector(
                onTap: () async {
                  setState(() => _dragOffset = 0.0);
                  widget.onDelete();
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withOpacity(0.12),
                  ),
                  child: Text(
                    '삭제',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),

          // 메인 컨텐츠
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color:
                    widget.isSelected
                        ? Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.8)
                        : Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (_dragOffset != 0) {
                      // 드래그 상태면 먼저 닫기
                      setState(() {
                        _dragOffset = 0.0;
                      });
                      // no-op
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
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                              fontSize: 16,
                              color:
                                  widget.isSelected && isDarkMode
                                      ? AppColors.darkSurface
                                      : widget.isSelected && !isDarkMode
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),

                          child: Text(
                            '${widget.category['postCount'] ?? 0}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color:
                                  widget.isSelected && isDarkMode
                                      ? AppColors.darkSurface
                                      : widget.isSelected && !isDarkMode
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
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
  bool _isCreatingCategory = false;
  final TextEditingController _createCategoryController =
      TextEditingController();
  final FocusNode _createCategoryFocusNode = FocusNode();

  /// 카테고리 변경 콜백 설정
  void setOnCategoryChanged(VoidCallback? callback) {
    _onCategoryChanged = callback;
  }

  /// 리소스 정리
  void dispose() {
    _createCategoryController.dispose();
    _createCategoryFocusNode.dispose();
  }

  /// 카테고리 드롭다운 표시 (BottomSheet)
  void showCategoryDropdown(
    BuildContext context,
    GlobalKey buttonKey,
    BaseFeedProvider feedProvider,
  ) async {
    // 상태 초기화
    _isCreatingCategory = false;
    _createCategoryController.clear();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Stack(
              children: [
                // 배경 영역 (바깥 부분) - 탭하면 닫힘
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // 바텀시트 컨텐츠
                DraggableScrollableSheet(
                  initialChildSize: 0.6,
                  minChildSize: 0.4,
                  maxChildSize: 0.9,
                  builder: (context, scrollController) {
                    return GestureDetector(
                      onTap: () {
                        // 바텀시트 내부를 탭해도 닫히지 않도록 이벤트 소비
                      },
                      child: ClipRRect(
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
                                  margin: const EdgeInsets.only(
                                    top: 12,
                                    bottom: 8,
                                  ),
                                  width: 38,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                SizedBox(height: 12),

                                // 카테고리 리스트
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: scrollController,
                                    child: _buildCategoryContent(
                                      context,
                                      feedProvider,
                                      setModalState,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color:
            isSelected
                ? Theme.of(context).colorScheme.onSurface.withOpacity(0.9)
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
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 16,
                      color:
                          isSelected && isDarkMode
                              ? AppColors.darkSurface
                              : isSelected && !isDarkMode
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),

                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color:
                          isSelected && isDarkMode
                              ? AppColors.darkSurface
                              : isSelected && !isDarkMode
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 카테고리 드롭다운 내용 빌드
  Widget _buildCategoryContent(
    BuildContext context,
    BaseFeedProvider feedProvider,
    StateSetter setModalState,
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
    final friendsPosts = feedProvider.friendsPostCount;
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
        // 카테고리 생성 모드일 때는 텍스트 필드만, 아닐 때는 버튼과 카테고리 목록
        if (isOwnProfile) ...[
          if (_isCreatingCategory)
            _buildCreateCategoryField(context, feedProvider, setModalState)
          else
            _buildCreateCategoryButton(context, feedProvider, setModalState),
        ],

        // 카테고리 목록은 생성 모드가 아닐 때만 표시
        if (!_isCreatingCategory) ...[
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
              (privatePosts > 0 ||
                  friendsPosts > 0 ||
                  groupPosts > 0 ||
                  publicPosts > 0)) ...[
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

            // 친구공유
            if (friendsPosts > 0)
              _buildCategoryItem(
                title: '친구공유',
                count: friendsPosts,
                isSelected:
                    feedProvider.selectedBase == BaseFilter.friends &&
                    feedProvider.selectedCategoryId == null,
                context: context,
                onTap: () {
                  feedProvider.selectBase(BaseFilter.friends);
                  Navigator.of(context).pop();
                  _onCategoryChanged?.call();
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

          // 사용자가 만든 카테고리 (신규 생성 항목이 맨 위로 오도록 정렬)
          ...(() {
            final userCategories = categories
                .where((c) => !(c['isSystem'] == true))
                .toList(growable: false);
            // ID 0(미분류)은 항상 맨 아래, 그 외는 ID 내림차순(최근 생성이 위쪽)
            userCategories.sort((a, b) {
              final int aId = (a['id'] as int?) ?? 0;
              final int bId = (b['id'] as int?) ?? 0;
              final bool aIsZero = aId == 0;
              final bool bIsZero = bId == 0;
              if (aIsZero != bIsZero) return aIsZero ? 1 : -1; // 0을 뒤로
              return bId.compareTo(aId); // 내림차순
            });
            return userCategories.map(
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
                  // 공통 입력 다이얼로그로 이름 변경
                  final newName = await DialogUtils.showTextInputDialog(
                    context,
                    title: '카테고리 이름 수정',
                    hintText: '새 이름 입력',
                    initialText: (c['name'] ?? '').toString(),
                    confirmText: '저장',
                  );
                  if (newName != null && newName.trim().isNotEmpty) {
                    try {
                      await BlogService().updateCategoryName(
                        categoryId: (c['id'] as int?) ?? -1,
                        name: newName.trim(),
                      );
                      await feedProvider.refresh();
                      _onCategoryChanged?.call();
                    } catch (e) {
                      _showSnackBarSafely(context, '카테고리 수정 중 오류가 발생했습니다');
                    }
                  }
                },
                onDelete: () {
                  () async {
                    final bool? confirmed = await DialogUtils.showConfirmDialog(
                      context,
                      title: '카테고리 삭제',
                      message: '정말 삭제하시겠어요? 되돌릴 수 없어요.\n이 카테고리의 포스트는 지워지지 않아요.',
                      confirmText: '삭제',
                      cancelText: '취소',
                      isDestructive: true,
                    );
                    if (confirmed == true &&
                        feedProvider is MyProfileFeedProvider) {
                      _deleteCategory(context, feedProvider, c['id']);
                    }
                  }();
                },
              ),
            );
          })(),
        ],

        // BottomSheet 하단 여백
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCreateCategoryButton(
    BuildContext context,
    BaseFeedProvider feedProvider,
    StateSetter setModalState,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setModalState(() {
            _isCreatingCategory = true;
          });
          // 키보드가 나타날 때까지 잠시 기다린 후 포커스
          Future.delayed(const Duration(milliseconds: 100), () {
            _createCategoryFocusNode.requestFocus();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '새 카테고리 만들기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 카테고리 생성 텍스트 필드 (인라인)
  Widget _buildCreateCategoryField(
    BuildContext context,
    BaseFeedProvider feedProvider,
    StateSetter setModalState,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                cursorColor: Theme.of(context).colorScheme.onSurface,
                controller: _createCategoryController,
                focusNode: _createCategoryFocusNode,
                autofocus: true,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: '새 카테고리 이름',
                  hintStyle: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,

                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.04),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                ),
                onSubmitted:
                    (value) => _handleCreateCategory(
                      context,
                      feedProvider,
                      setModalState,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    setModalState(() {
                      _isCreatingCategory = false;
                      _createCategoryController.clear();
                    });
                    _createCategoryFocusNode.unfocus();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    '취소',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    setModalState(() {
                      _handleCreateCategory(
                        context,
                        feedProvider,
                        setModalState,
                      );
                    });
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    '생성',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 카테고리 생성 처리
  void _handleCreateCategory(
    BuildContext context,
    BaseFeedProvider feedProvider,
    StateSetter setModalState,
  ) async {
    final name = _createCategoryController.text.trim();
    if (name.isEmpty) return;

    try {
      await _createCategory(context, feedProvider, name);
      setModalState(() {
        _isCreatingCategory = false;
        _createCategoryController.clear();
      });
      _createCategoryFocusNode.unfocus();
      _onCategoryChanged?.call();
      // 생성이 성공하면 바텀시트를 닫는다
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // 에러는 _createCategory에서 처리됨
    }
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
        try {
          // 서버에 즉시 순서 반영 (임시로 새 항목을 맨 앞에)
          await BlogService().reorderCategories(ordered);
          await feedProvider.refresh();
        } catch (e) {
          print('[CategoryDropDown] 생성 후 정렬 반영 실패: $e');
        }
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
