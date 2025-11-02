import 'dart:ui';

import 'package:doppy/editor/publish/post_export_screen.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/editor/overlay/thumbnail_edit_overlay.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/upload_service.dart';

class EditModeAppBar extends StatefulWidget {
  final EditorService editorService;
  final VoidCallback? onSave;
  final String currentVisibility; // 'public', 'private', 'partial'
  final List<int> currentGroupIds;
  final Function(String visibility, List<int> groupIds)? onVisibilityChanged;
  final Function(String title, String summary)?
  onTitleSummaryChanged; // 제목/요약 변경 콜백
  final String? postId; // 서버에서 데이터 가져오기용
  final bool isSaving; // 저장 중 상태

  const EditModeAppBar({
    super.key,
    required this.editorService,
    this.onSave,
    required this.currentVisibility,
    required this.currentGroupIds,
    this.onVisibilityChanged,
    this.onTitleSummaryChanged,
    this.postId,
    this.isSaving = false,
  });

  @override
  State<EditModeAppBar> createState() => _EditModeAppBarState();
}

class _EditModeAppBarState extends State<EditModeAppBar> {
  String _selectedVisibility = 'public';
  List<int> _selectedGroupIds = [];
  String? _thumbnailUrl;
  String? _thumbnailId;
  int? _selectedCategoryId = 0; // 카테고리 ID
  List<Map<String, dynamic>>? _cachedCategories;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedVisibility = widget.currentVisibility;
    _selectedGroupIds = List.from(widget.currentGroupIds);

    // 썸네일 초기화 - NodeComponentService에서 persist된 값 사용 (post_export_screen과 동일)
    final nodeService = NodeComponentService();
    _thumbnailUrl = nodeService.getTempThumbnailUrl('default');
    _thumbnailId = nodeService.getTempThumbnailId('default');

    print('[EditModeAppBar] 썸네일 초기화: $_thumbnailUrl (ID: $_thumbnailId)');

    // 수정 모드 진입 시 모든 데이터 한번에 로드
    if (widget.postId != null) {
      _loadAllEditData();
    }
  }

  /// 수정 모드 진입 시 필요한 모든 데이터를 한번에 로드
  Future<void> _loadAllEditData() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final currentUser =
          Provider.of<UserProvider>(context, listen: false).currentUser;
      final username = currentUser?.username ?? '';

      if (username.isEmpty) {
        throw Exception('사용자 정보를 찾을 수 없습니다.');
      }

      // 병렬로 모든 데이터 로드
      final results = await Future.wait([
        // 1. 포스트 메타데이터 (썸네일, 카테고리, 공개범위)
        BlogService().getPostMetadata(widget.postId!),
        // 2. 내 카테고리 목록
        BlogService().getUserCategories(username),
      ]);

      if (!mounted) return;

      final metadata = results[0] as Map<String, dynamic>;
      final categories = results[1] as List<Map<String, dynamic>>;

      setState(() {
        // 썸네일 정보 업데이트
        _thumbnailUrl = metadata['thumbnailImageUrl'] as String?;
        _thumbnailId = metadata['thumbnailImageId']?.toString();

        // 카테고리 정보 업데이트
        _selectedCategoryId = metadata['categoryId'] as int? ?? 0;
        _cachedCategories = categories;

        // 공개범위 정보는 이미 widget에서 전달받음
        // (필요시 metadata['accessLevel']로 추가 업데이트 가능)

        _isLoading = false;
      });

      // NodeComponentService에도 썸네일 정보 저장
      if (_thumbnailUrl != null && _thumbnailUrl!.isNotEmpty) {
        final nodeService = NodeComponentService();
        nodeService.setTempThumbnail(
          'default',
          url: _thumbnailUrl!,
          id: _thumbnailId,
        );
      }

      print('[EditModeAppBar] 데이터 로드 완료');
      print('  - 썸네일: $_thumbnailUrl (ID: $_thumbnailId)');
      print('  - 카테고리: $_selectedCategoryId');
      print('  - 카테고리 개수: ${categories.length}');
    } catch (e) {
      print('[EditModeAppBar] 데이터 로드 실패: $e');
      if (mounted) {
        setState(() {
          _cachedCategories = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<T?> _showMenuWithBarrier<T>({
    required BuildContext context,
    required RelativeRect position,
    required List<PopupMenuEntry<T>> items,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierDismissible: true,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;

        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              Positioned(
                right: 16,
                top: position.top,
                child: GestureDetector(
                  onTap: () {}, // 메뉴 클릭은 닫히지 않게
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 240,
                      constraints: BoxConstraints(maxWidth: screenWidth - 64),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children:
                              items.map((item) {
                                if (item is PopupMenuItem<T>) {
                                  return InkWell(
                                    onTap: () {
                                      Navigator.of(context).pop(item.value);
                                      item.onTap?.call();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: item.child,
                                    ),
                                  );
                                } else if (item is PopupMenuDivider) {
                                  return Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.08),
                                  );
                                }
                                return const SizedBox.shrink();
                              }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditOptionsMenu(BuildContext context, Offset buttonPosition) {
    _showMenuWithBarrier<String>(
      context: context,
      position: RelativeRect.fromLTRB(16, buttonPosition.dy, 0, 0),
      items: [
        // 썸네일 수정
        PopupMenuItem<String>(
          value: 'thumbnail',
          child: _buildSimpleMenuItem(context: context, title: '썸네일 수정'),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (widget.postId == null) {
                print('[EditModeAppBar] postId가 없습니다');
                return;
              }

              Navigator.of(context).push(
                PageRouteBuilder(
                  opaque: true,
                  barrierDismissible: true,
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  pageBuilder:
                      (_, __, ___) => ThumbnailEditOverlay(
                        postId: widget.postId!,
                        sessionKey: 'default',
                        onThumbnailChanged: (url, id) {
                          setState(() {
                            _thumbnailUrl = url;
                            _thumbnailId = id;
                          });
                        },
                        onMetadataChanged: (title, summary) {
                          // 제목/요약이 변경되었을 때 부모(PostwriteScreen)에게 알림
                          widget.onTitleSummaryChanged?.call(title, summary);
                          print('[EditModeAppBar] 제목/요약 변경 콜백 전달');
                        },
                      ),
                ),
              );
            });
          },
        ),

        // 공개범위 변경
        PopupMenuItem<String>(
          value: 'visibility',
          child: _buildSimpleMenuItem(context: context, title: '공개범위 변경'),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 100), () {
              final RenderBox button = context.findRenderObject() as RenderBox;
              final Offset position = button.localToGlobal(Offset.zero);
              _showVisibilityMenu(context, position);
            });
          },
        ),

        // 카테고리 변경
        PopupMenuItem<String>(
          value: 'category',
          child: _buildSimpleMenuItem(context: context, title: '카테고리 변경'),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 100), () {
              final RenderBox button = context.findRenderObject() as RenderBox;
              final Offset position = button.localToGlobal(Offset.zero);
              _showCategoryMenu(context, position);
            });
          },
        ),
      ],
    );
  }

  Widget _buildSimpleMenuItem({
    required BuildContext context,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  void _showCategoryMenu(BuildContext context, Offset buttonPosition) {
    // 카테고리가 아직 로드되지 않았거나 비어있으면 표시하지 않음
    if (_cachedCategories == null || _cachedCategories!.isEmpty) {
      print('[EditModeAppBar] 카테고리가 아직 로드되지 않았거나 비어있습니다');
      ErrorHandler.showWarning(context, '카테고리를 불러오는 중입니다');
      return;
    }

    _showMenuWithBarrier<String>(
      context: context,
      position: RelativeRect.fromLTRB(16, buttonPosition.dy, 0, 0),
      items:
          _cachedCategories!.map((category) {
            final id = category['id'] as int?;
            var name = category['name'] as String? ?? '이름 없음';

            if (name == 'system_doppy_uncategorized') {
              name = '지정 안 함';
            }

            final isSelected = _selectedCategoryId == id;

            return PopupMenuItem<String>(
              value: 'category_$id',
              child: _buildDropdownItemWithDivider(
                context: context,
                title: name,
                isSelected: isSelected,
              ),
              onTap: () {
                Future.delayed(Duration.zero, () async {
                  if (widget.postId == null || id == null) {
                    print('[EditModeAppBar] postId 또는 categoryId가 없습니다');
                    return;
                  }

                  try {
                    // 서버에 카테고리 변경 요청
                    await BlogService().movePostToCategory(
                      postId: int.parse(widget.postId!),
                      targetCategoryId: id,
                    );

                    if (mounted) {
                      setState(() {
                        _selectedCategoryId = id;
                      });
                      ErrorHandler.showInfo(context, '카테고리가 변경되었습니다');
                      print('[EditModeAppBar] 카테고리 변경 성공: $name (ID: $id)');
                    }
                  } catch (e) {
                    print('[EditModeAppBar] 카테고리 변경 실패: $e');
                    if (mounted) {
                      ErrorHandler.handleError(context, e);
                    }
                  }
                });
              },
            );
          }).toList(),
    );
  }

  void _showVisibilityMenu(BuildContext context, Offset buttonPosition) {
    final groupProvider = Provider.of<GroupProvider>(context, listen: false);

    _showMenuWithBarrier<String>(
      context: context,
      position: RelativeRect.fromLTRB(16, buttonPosition.dy, 0, 0),
      items: [
        // 나만보기
        PopupMenuItem<String>(
          value: 'private',
          child: _buildDropdownItemWithDivider(
            context: context,
            title: '나만보기',
            isSelected: _selectedVisibility == 'private',
          ),
          onTap: () {
            Future.delayed(Duration.zero, () async {
              if (widget.postId == null) {
                print('[EditModeAppBar] postId가 없습니다');
                return;
              }

              try {
                // 서버에 공개범위 변경 요청
                await BlogService().updatePostAccessLevel(
                  postId: int.parse(widget.postId!),
                  accessLevel: 'PRIVATE',
                );

                if (mounted) {
                  setState(() {
                    _selectedVisibility = 'private';
                    _selectedGroupIds.clear();
                  });
                  widget.onVisibilityChanged?.call(
                    _selectedVisibility,
                    _selectedGroupIds,
                  );
                  ErrorHandler.showInfo(context, '공개범위가 나만보기로 변경되었습니다');
                  print('[EditModeAppBar] 공개범위 변경 성공: PRIVATE');
                }
              } catch (e) {
                print('[EditModeAppBar] 공개범위 변경 실패: $e');
                if (mounted) {
                  ErrorHandler.handleError(context, e);
                }
              }
            });
          },
        ),

        // 전체공개
        PopupMenuItem<String>(
          value: 'public',
          child: _buildDropdownItemWithDivider(
            context: context,
            title: '전체공개',
            isSelected: _selectedVisibility == 'public',
          ),
          onTap: () {
            Future.delayed(Duration.zero, () async {
              if (widget.postId == null) {
                print('[EditModeAppBar] postId가 없습니다');
                return;
              }

              try {
                // 서버에 공개범위 변경 요청
                await BlogService().updatePostAccessLevel(
                  postId: int.parse(widget.postId!),
                  accessLevel: 'PUBLIC',
                );

                if (mounted) {
                  setState(() {
                    _selectedVisibility = 'public';
                    _selectedGroupIds.clear();
                  });
                  widget.onVisibilityChanged?.call(
                    _selectedVisibility,
                    _selectedGroupIds,
                  );
                  ErrorHandler.showInfo(context, '공개범위가 전체공개로 변경되었습니다');
                  print('[EditModeAppBar] 공개범위 변경 성공: PUBLIC');
                }
              } catch (e) {
                print('[EditModeAppBar] 공개범위 변경 실패: $e');
                if (mounted) {
                  ErrorHandler.handleError(context, e);
                }
              }
            });
          },
        ),

        // 그룹공개
        PopupMenuItem<String>(
          value: 'partial',
          child: _buildDropdownItemWithDivider(
            context: context,
            title: '그룹공개',
            isSelected: _selectedVisibility == 'partial',
            hasExpansion: true,
            isExpanded: false,
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              setState(() {
                _selectedVisibility = 'partial';
                if (_selectedGroupIds.isEmpty &&
                    groupProvider.myGroups.isNotEmpty) {
                  _selectedGroupIds.add(groupProvider.myGroups.first.id);
                }
              });
            });
            // 그룹 선택 드롭다운 열기
            Future.delayed(const Duration(milliseconds: 100), () {
              final RenderBox button = context.findRenderObject() as RenderBox;
              final Offset position = button.localToGlobal(Offset.zero);
              _showGroupSelectionMenu(context, position);
            });
          },
        ),
      ],
    );
  }

  void _showGroupSelectionMenu(BuildContext context, Offset buttonPosition) {
    final groupProvider = Provider.of<GroupProvider>(context, listen: false);

    _showMenuWithBarrier<String>(
      context: context,
      position: RelativeRect.fromLTRB(16, buttonPosition.dy + 40, 0, 0),
      items: [
        // 뒤로가기 헤더
        PopupMenuItem<String>(
          height: 36,
          enabled: false,
          child: Row(
            children: [
              Spacer(),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    final RenderBox button =
                        context.findRenderObject() as RenderBox;
                    final Offset position = button.localToGlobal(Offset.zero);
                    _showVisibilityMenu(context, position);
                  });
                },
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),

        // 그룹 리스트
        ...groupProvider.myGroups.asMap().entries.map((entry) {
          final index = entry.key;
          final group = entry.value;
          final isSelected = _selectedGroupIds.contains(group.id);
          final isLast = index == groupProvider.myGroups.length - 1;

          return PopupMenuItem<String>(
            value: 'group_${group.id}',
            child: _buildGroupDropdownItemWithDivider(
              context: context,
              groupName: group.name,
              isSelected: isSelected,
              showDivider: !isLast,
            ),
            onTap: () {
              Future.delayed(Duration.zero, () async {
                // 그룹 선택/해제 로직
                List<int> newGroupIds = List.from(_selectedGroupIds);
                if (isSelected) {
                  newGroupIds.remove(group.id);
                } else {
                  newGroupIds.add(group.id);
                }

                // 그룹이 하나도 없으면 변경하지 않음
                if (newGroupIds.isEmpty) {
                  ErrorHandler.showWarning(context, '최소 1개 이상의 그룹을 선택해야 합니다');
                  // 드롭다운을 다시 열기
                  Future.delayed(const Duration(milliseconds: 100), () {
                    final RenderBox button =
                        context.findRenderObject() as RenderBox;
                    final Offset position = button.localToGlobal(Offset.zero);
                    _showGroupSelectionMenu(context, position);
                  });
                  return;
                }

                if (widget.postId == null) {
                  print('[EditModeAppBar] postId가 없습니다');
                  return;
                }

                try {
                  // 서버에 공개범위 변경 요청
                  await BlogService().updatePostAccessLevel(
                    postId: int.parse(widget.postId!),
                    accessLevel: 'GROUPS',
                    sharedGroupIds: newGroupIds,
                  );

                  if (mounted) {
                    setState(() {
                      _selectedVisibility = 'partial';
                      _selectedGroupIds = newGroupIds;
                    });
                    widget.onVisibilityChanged?.call(
                      _selectedVisibility,
                      _selectedGroupIds,
                    );
                    ErrorHandler.showInfo(context, '공개 그룹이 변경되었습니다');
                    print('[EditModeAppBar] 그룹 변경 성공: $newGroupIds');
                  }
                } catch (e) {
                  print('[EditModeAppBar] 그룹 변경 실패: $e');
                  if (mounted) {
                    ErrorHandler.handleError(context, e);
                  }
                }

                // 드롭다운을 다시 열기
                Future.delayed(const Duration(milliseconds: 100), () {
                  final RenderBox button =
                      context.findRenderObject() as RenderBox;
                  final Offset position = button.localToGlobal(Offset.zero);
                  _showGroupSelectionMenu(context, position);
                });
              });
            },
          );
        }).toList(),
      ],
    );
  }

  Widget _buildDropdownItemWithDivider({
    required BuildContext context,
    required String title,
    required bool isSelected,
    bool hasExpansion = false,
    bool isExpanded = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              // 체크 아이콘
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color:
                    isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.3),
                size: 20,
              ),
              const SizedBox(width: 12),
              // 타이틀
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              // 확장 아이콘 (그룹공개인 경우)
              if (hasExpansion)
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
                  size: 20,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupDropdownItemWithDivider({
    required BuildContext context,
    required String groupName,
    required bool isSelected,
    bool showDivider = true,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 체크 아이콘 (원형)
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color:
                  isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.3),
              size: 20,
            ),
            const SizedBox(width: 12),
            // 그룹명
            Expanded(
              child: Text(
                groupName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        if (showDivider)
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(top: 8),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background.withOpacity(1),
            ),
            height: 55,
            width: MediaQuery.of(context).size.width,
            child: Stack(
              children: [
                // 뒤로가기 버튼 (왼쪽)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.of(context).maybePop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.8),
                        size: 20,
                      ),
                    ),
                  ),
                ),

                // 수정 완료 버튼 (오른쪽)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 더보기 메뉴 버튼
                      Builder(
                        builder:
                            (btnContext) => IconButton(
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.6),
                                size: 24,
                              ),
                              onPressed: () {
                                final RenderBox button =
                                    btnContext.findRenderObject() as RenderBox;
                                final Offset position = button.localToGlobal(
                                  Offset.zero,
                                );
                                _showEditOptionsMenu(btnContext, position);
                              },
                            ),
                      ),

                      // 수정 완료 버튼 / 로딩 표시
                      GestureDetector(
                        onTap: widget.isSaving ? null : widget.onSave,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child:
                                widget.isSaving
                                    ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 2,
                                      ),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      ),
                                    )
                                    : Row(
                                      children: [
                                        const SizedBox(width: 4),
                                        Text(
                                          '수정 완료  ',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditorAppBar extends StatelessWidget {
  final EditorService editorService;
  final StickerService stickerService;
  final VoidCallback? onSaveDraft;
  final VoidCallback? onLoadDraft;

  const EditorAppBar({
    super.key,
    required this.editorService,
    required this.stickerService,
    this.onSaveDraft,
    this.onLoadDraft,
  });

  Future<void> _onNextButtonTapped(BuildContext context) async {
    // 업로드 작업 이중 가드: 업로드 중이면 진행 차단
    final upload = context.read<UploadService>();
    if (upload.hasActiveUploads()) {
      await DialogUtils.showInfoDialog(
        context,
        title: '업로드 중',
        message: '아직 업로드 중인 미디어가 있어요. 잠시만 기다려주세요.',
      );
      return;
    }

    // 제목과 본문 검증
    final hasTitle = editorService.hasNonEmptyTitle();
    final hasBody = editorService.hasNonEmptyBody();

    if (!hasTitle || !hasBody) {
      // 제목 또는 본문이 비어있으면 다이얼로그 표시
      String message;
      if (!hasTitle && !hasBody) {
        message = '제목과 본문을 입력해주세요.';
      } else if (!hasTitle) {
        message = '제목을 입력해주세요.';
      } else {
        message = '본문을 입력해주세요.';
      }

      await DialogUtils.showInfoDialog(
        context,
        title: '내용을 작성해주세요',
        message: message,
      );
      return;
    }

    // 검증 통과 시 다음 화면으로 이동
    cleanupAllVideoPlayers();
    NodeComponentService().selectNode(null);
    final json = exportToJsonString(context);

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => PostExportScreen(exported: json),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background.withOpacity(1),
            ),
            height: 55,
            width: MediaQuery.of(context).size.width,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 뒤로가기 버튼
                GestureDetector(
                  onTap: () async {
                    Navigator.of(context).maybePop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.8),
                      size: 20,
                    ),
                  ),
                ),

                // 오른쪽 버튼들
                Row(
                  children: [
                    // 더보기 메뉴 버튼
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                        size: 20,
                      ),
                      offset: const Offset(45, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.1),
                        ),
                      ),
                      color: Theme.of(
                        context,
                      ).colorScheme.background.withOpacity(1),

                      onSelected: (value) {
                        if (value == 'load') {
                          onLoadDraft?.call();
                        } else if (value == 'save') {
                          onSaveDraft?.call();
                        }
                      },
                      itemBuilder:
                          (context) => [
                            PopupMenuItem(
                              value: 'load',
                              child: Row(
                                children: [
                                  Text(
                                    '임시저장 불러오기',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'save',
                              child: Row(
                                children: [
                                  Text(
                                    '임시저장',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                    ),

                    // 다음 버튼 (항상 표시, 클릭 시 검증)
                    GestureDetector(
                      onTap: () => _onNextButtonTapped(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          '다음',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(1),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(width: 10),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String exportToJsonString(BuildContext context) {
    return PostExporter.exportToJsonString(
      editorService: editorService,
      stickerService: stickerService,
      viewportSize: MediaQuery.of(context).size,
      pretty: true,
    );
  }
}

class TopPadding extends StatelessWidget {
  const TopPadding({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.background.withOpacity(1),
          ),
        ),
      ),
    );
  }
}
