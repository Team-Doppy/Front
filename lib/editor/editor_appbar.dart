import 'dart:ui';

import 'package:doppy/editor/publish/post_export_screen.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/editor/overlay/thumbnail_edit_overlay.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/utils/access_level_parser.dart';
import 'package:super_editor/super_editor.dart';

class EditModeAppBar extends StatefulWidget {
  final EditorService editorService;
  final VoidCallback? onSave;
  final String currentVisibility; // 'public', 'private', 'partial'
  final List<int> currentGroupIds;
  final Function(String visibility, List<int> groupIds)? onVisibilityChanged;
  final Function(String title, String summary)?
  onTitleSummaryChanged; // 제목/요약 변경 콜백
  final VoidCallback? onCategoryChanged; // 카테고리 변경 콜백
  final Function(String url, String? id)?
  onThumbnailChanged; // 썸네일 변경 콜백 (URL과 ID 전달)
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
    this.onCategoryChanged,
    this.onThumbnailChanged,
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

    print('[EditModeAppBar] 썸네일 초기화: $_thumbnailUrl (ID: $_thumbnailId)');

    // 수정 모드 진입 시 모든 데이터 한번에 로드
    if (widget.postId != null) {
      _loadAllEditData();
    }

    // 번역 테스트
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final testTranslation = context.tr('visibility_public');
          print(
            '[EditModeAppBar] 번역 테스트: visibility_public = "$testTranslation"',
          );
        } catch (e) {
          print('[EditModeAppBar] 번역 에러: $e');
        }
      }
    });
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

      // FeedProvider에서 현재 포스트의 카테고리 우선 탐색
      int? categoryIdFromFeed;
      try {
        final feed = MyProfileFeedProvider();
        final pid = widget.postId != null ? int.tryParse(widget.postId!) : null;
        if (pid != null) {
          for (final entry in feed.postsByCategory.entries) {
            final String key = entry.key.toString();
            final int? catId = int.tryParse(key);
            final list = entry.value;
            final found = list.any(
              (p) =>
                  (p['id'] is int ? p['id'] : int.tryParse('${p['id']}')) ==
                  pid,
            );
            if (found) {
              categoryIdFromFeed = catId ?? 0;
              break;
            }
          }
        }
      } catch (e) {
        print('[EditModeAppBar] FeedProvider에서 카테고리 파싱 실패: $e');
      }

      setState(() {
        // 썸네일 정보 업데이트
        _thumbnailUrl = metadata['thumbnailImageUrl'] as String?;
        _thumbnailId = metadata['thumbnailImageId']?.toString();

        // 카테고리 정보 업데이트: FeedProvider 우선, 실패 시 메타데이터 fallback
        if (categoryIdFromFeed != null) {
          _selectedCategoryId = categoryIdFromFeed;
        } else {
          _selectedCategoryId = metadata['categoryId'] as int? ?? 0;
        }
        _cachedCategories = categories;

        // 🎯 공개범위 메타데이터 반영 (메타데이터에는 accessLevel만 있음)
        // sharedGroupIds/Names는 content.accessLevelInfo에만 있으므로 여기서는 기본값으로 설정
        try {
          final level = AccessLevelParser.parseAccessLevelString(
            metadata['accessLevel'],
          );

          if (level != null) {
            if (level == 'PRIVATE') {
              _selectedVisibility = 'private';
              _selectedGroupIds.clear();
            } else if (level == 'PUBLIC') {
              _selectedVisibility = 'public';
              _selectedGroupIds.clear();
            } else if (level == 'FRIENDS') {
              _selectedVisibility = 'friends';
              _selectedGroupIds.clear();
            } else if (level == 'GROUPS') {
              // 🎯 GROUPS인 경우 메타데이터에는 그룹 정보가 없으므로
              // widget.currentGroupIds를 유지 (이미 로드된 데이터 활용)
              _selectedVisibility = 'partial';
              // _selectedGroupIds는 widget.currentGroupIds로 이미 초기화됨
            }
          }
        } catch (_) {}

        _isLoading = false;
      });

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
                        // 🎯 이미 로드한 썸네일 데이터 전달 (메타데이터 재조회 불필요)
                        initialThumbnailUrl: _thumbnailUrl,
                        initialThumbnailId: _thumbnailId,
                        onThumbnailChanged: (url, id) {
                          setState(() {
                            _thumbnailUrl = url;
                            _thumbnailId = id;
                          });
                          print('[EditModeAppBar] 썸네일 변경됨: $url');
                          // 부모에 통지: 썸네일 변경됨 (URL과 ID 전달)
                          widget.onThumbnailChanged?.call(url, id);
                          print(
                            '[EditModeAppBar] 부모 콜백 호출 완료: url=$url, id=$id',
                          );
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

                  // 변경 없음 가드
                  if (_selectedCategoryId == id) {
                    print('[EditModeAppBar] 카테고리 변경 없음 - API 호출 생략');
                    ErrorHandler.showInfo(
                      context,
                      context.tr('already_selected_category'),
                    );
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
                      ErrorHandler.showInfo(
                        context,
                        context.tr('category_changed'),
                      );
                      print('[EditModeAppBar] 카테고리 변경 성공: $name (ID: $id)');
                      widget.onCategoryChanged?.call();
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

    final items = <PopupMenuItem<String>>[
      // 나만보기
      PopupMenuItem<String>(
        value: 'private',
        child: _buildDropdownItemWithDivider(
          context: context,
          title: context.tr('visibility_private'),
          isSelected: _selectedVisibility == 'private',
        ),
        onTap: () {
          Future.delayed(Duration.zero, () async {
            if (widget.postId == null) {
              print('[EditModeAppBar] postId가 없습니다');
              return;
            }

            // 변경 없음 가드
            if (_selectedVisibility == 'private') {
              print('[EditModeAppBar] 공개범위 변경 없음(private) - API 호출 생략');
              ErrorHandler.showInfo(context, context.tr('already_private'));
              return;
            }

            try {
              // 서버에 공개범위 변경 요청
              await BlogService().updatePostAccessLevel(
                postId: int.parse(widget.postId!),
                accessLevel: 'PRIVATE',
              );

              // 🎯 낙관적 업데이트 (서버 호출 성공 시)
              if (mounted) {
                setState(() {
                  _selectedVisibility = 'private';
                  _selectedGroupIds.clear();
                });
              }

              if (mounted) {
                widget.onVisibilityChanged?.call(
                  _selectedVisibility,
                  _selectedGroupIds,
                );
                ErrorHandler.showInfo(
                  context,
                  context.tr('visibility_changed_private'),
                );
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
          title: context.tr('visibility_public'),
          isSelected: _selectedVisibility == 'public',
        ),
        onTap: () {
          Future.delayed(Duration.zero, () async {
            if (widget.postId == null) {
              print('[EditModeAppBar] postId가 없습니다');
              return;
            }

            // 변경 없음 가드
            if (_selectedVisibility == 'public') {
              print('[EditModeAppBar] 공개범위 변경 없음(public) - API 호출 생략');
              ErrorHandler.showInfo(context, context.tr('already_public'));
              return;
            }

            try {
              // 서버에 공개범위 변경 요청
              await BlogService().updatePostAccessLevel(
                postId: int.parse(widget.postId!),
                accessLevel: 'PUBLIC',
              );

              // 🎯 낙관적 업데이트 (서버 호출 성공 시)
              if (mounted) {
                setState(() {
                  _selectedVisibility = 'public';
                  _selectedGroupIds.clear();
                });
              }

              if (mounted) {
                widget.onVisibilityChanged?.call(
                  _selectedVisibility,
                  _selectedGroupIds,
                );
                ErrorHandler.showInfo(
                  context,
                  context.tr('visibility_changed_public'),
                );
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

      // 친구공개
      PopupMenuItem<String>(
        value: 'friends',
        child: _buildDropdownItemWithDivider(
          context: context,
          title: context.tr('visibility_friends'),
          isSelected: _selectedVisibility == 'friends',
        ),
        onTap: () {
          Future.delayed(Duration.zero, () async {
            if (widget.postId == null) {
              print('[EditModeAppBar] postId가 없습니다');
              return;
            }

            // 변경 없음 가드
            if (_selectedVisibility == 'friends') {
              print('[EditModeAppBar] 공개범위 변경 없음(friends) - API 호출 생략');
              ErrorHandler.showInfo(context, context.tr('already_friends'));
              return;
            }

            try {
              await BlogService().updatePostAccessLevel(
                postId: int.parse(widget.postId!),
                accessLevel: 'FRIENDS',
              );

              // 🎯 낙관적 업데이트 (서버 호출 성공 시)
              if (mounted) {
                setState(() {
                  _selectedVisibility = 'friends';
                  _selectedGroupIds.clear();
                });
              }

              if (mounted) {
                widget.onVisibilityChanged?.call(
                  _selectedVisibility,
                  _selectedGroupIds,
                );
                ErrorHandler.showInfo(
                  context,
                  context.tr('visibility_changed_friends'),
                );
                print('[EditModeAppBar] 공개범위 변경 성공: FRIENDS');
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
    ];

    // 그룹이 있을 때만 그룹공개 옵션 추가
    if (groupProvider.myGroups.isNotEmpty) {
      items.add(
        PopupMenuItem<String>(
          value: 'partial',
          child: _buildDropdownItemWithDivider(
            context: context,
            title: context.tr('visibility_group'),
            isSelected: _selectedVisibility == 'partial',
            hasExpansion: true,
            isExpanded: false,
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              setState(() {
                _selectedVisibility = 'partial';
                if (_selectedGroupIds.isEmpty) {
                  _selectedGroupIds.add(groupProvider.myGroups.first.id);
                }
              });
            });
            // 그룹 선택 드롭다운 열기
            Future.delayed(const Duration(milliseconds: 100), () {
              final RenderBox button = context.findRenderObject() as RenderBox;
              final Offset position = button.localToGlobal(Offset.zero);
              groupProvider.myGroups.length > 1
                  ? _showGroupSelectionMenu(context, position)
                  : null;
            });
          },
        ),
      );
    }

    _showMenuWithBarrier<String>(
      context: context,
      position: RelativeRect.fromLTRB(16, buttonPosition.dy, 0, 0),
      items: items,
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
          final group = entry.value;
          final isSelected = _selectedGroupIds.contains(group.id);

          return PopupMenuItem<String>(
            value: 'group_${group.id}',
            child: _buildGroupDropdownItem(
              context: context,
              groupName: group.name,
              isSelected: isSelected,
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

                // 변경 없음 가드 (선택된 그룹 집합 동일 + 이미 partial)
                final Set<int> beforeSet = Set<int>.from(_selectedGroupIds);
                final Set<int> afterSet = Set<int>.from(newGroupIds);
                if (_selectedVisibility == 'partial' &&
                    beforeSet.length == afterSet.length &&
                    beforeSet.containsAll(afterSet)) {
                  print('[EditModeAppBar] 공개 그룹 변경 없음 - API 호출 생략');
                  ErrorHandler.showInfo(
                    context,
                    context.tr('already_selected_group'),
                  );
                  // 드롭다운을 다시 열기
                  Future.delayed(const Duration(milliseconds: 100), () {
                    final RenderBox button =
                        context.findRenderObject() as RenderBox;
                    final Offset position = button.localToGlobal(Offset.zero);
                    _showGroupSelectionMenu(context, position);
                  });
                  return;
                }

                try {
                  // 서버에 공개범위 변경 요청
                  await BlogService().updatePostAccessLevel(
                    postId: int.parse(widget.postId!),
                    accessLevel: 'GROUPS',
                    sharedGroupIds: newGroupIds,
                  );

                  // 🎯 낙관적 업데이트 (서버 호출 성공 시)
                  if (mounted) {
                    setState(() {
                      _selectedVisibility = 'partial';
                      _selectedGroupIds = newGroupIds;
                    });
                  }

                  if (mounted) {
                    widget.onVisibilityChanged?.call(
                      _selectedVisibility,
                      _selectedGroupIds,
                    );
                    ErrorHandler.showInfo(context, context.tr('group_changed'));
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
              // 체크 아이콘 (원형 없이 단순 흰색 체크)
              if (isSelected)
                Icon(Icons.check, color: Colors.white, size: 20)
              else
                const SizedBox(width: 20), // 체크 아이콘 공간 확보
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

  Widget _buildGroupDropdownItem({
    required BuildContext context,
    required String groupName,
    required bool isSelected,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 체크 아이콘 (원형 없이 단순 흰색 체크)
            if (isSelected)
              Icon(Icons.check, color: Colors.white, size: 20)
            else
              const SizedBox(width: 20), // 체크 아이콘 공간 확보
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
            height: 50,
            width: MediaQuery.of(context).size.width,
            child: Stack(
              children: [
                // 왼쪽 버튼들 (뒤로가기 + 언두/리두)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 0,
                  child: Row(
                    children: [
                      // 뒤로가기 버튼
                      GestureDetector(
                        onTap: () async {
                          Navigator.of(context).maybePop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 24,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.75),
                          ),
                        ),
                      ),

                      // 언두 버튼
                      AnimatedBuilder(
                        animation: widget.editorService,
                        builder:
                            (context, _) => GestureDetector(
                              onTap: () {
                                widget.editorService.undo();
                              },
                              child: Container(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 8,
                                  left: 8,
                                  right: 8,
                                ),
                                child: SvgPicture.asset(
                                  'assets/icons/editor_undo.svg',
                                  width: 26,
                                  height: 26,
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(
                                      widget.editorService.canUndo ? 0.6 : 0.15,
                                    ),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                      ),

                      // 리두 버튼
                      AnimatedBuilder(
                        animation: widget.editorService,
                        builder:
                            (context, _) => GestureDetector(
                              onTap: () {
                                widget.editorService.redo();
                              },
                              child: Container(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 8,
                                  left: 8,
                                  right: 8,
                                ),
                                child: SvgPicture.asset(
                                  'assets/icons/editor_redo.svg',
                                  width: 26,
                                  height: 26,
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(
                                      widget.editorService.canRedo ? 0.6 : 0.15,
                                    ),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ],
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
                          decoration: BoxDecoration(),
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
                                          context.tr('modify_complete'),
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
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
  final Future<bool> Function()? onSaveDraft;
  final VoidCallback? onLoadDraft;
  final String? currentDraftId; // 현재 임시저장 ID

  const EditorAppBar({
    super.key,
    required this.editorService,
    required this.stickerService,
    this.onSaveDraft,
    this.onLoadDraft,
    this.currentDraftId,
  });

  Future<void> _onNextButtonTapped(BuildContext context) async {
    // 플레이스홀더 기반 가드: 문서에 이미지/영상 플레이스홀더가 있으면 진행 차단
    if (editorService.hasAnyPlaceholders()) {
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('wait_for_media_upload'),
        message: context.tr('media_still_uploading'),
      );
      return;
    }

    // 제목과 본문(또는 스티커) 검증
    final hasTitle = editorService.hasNonEmptyTitle();
    final hasBody = editorService.hasNonEmptyBody(context: context);

    if (!hasTitle || !hasBody) {
      // 제목 또는 본문이 비어있으면 다이얼로그 표시
      String message;
      if (!hasTitle && !hasBody) {
        message = context.tr('title_and_body_required');
      } else if (!hasTitle) {
        message = context.tr('title_required');
      } else {
        message = context.tr('body_required');
      }

      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('enter_content_first'),
        message: message,
      );
      return;
    }

    // 🎯 sessionKey 계산 (_saveDraft와 동일한 방식)
    final title = PostExporter.getTitleFromDocument(editorService.document);
    final titleHash = title.hashCode.abs();
    final draftIdByTitle = 'draft_$titleHash';
    final sessionKey = currentDraftId ?? draftIdByTitle;

    // 검증 통과 시 다음 화면으로 이동
    cleanupAllVideoPlayers();
    NodeComponentService().selectNode(null);
    final json = exportToJsonString(context);

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder:
            (_, __, ___) => PostExportScreen(
              exported: json,
              sessionKey: sessionKey, // draft ID를 sessionKey로 사용
            ),
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
            height: 50,
            width: MediaQuery.of(context).size.width,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 왼쪽 버튼들 (뒤로가기 + 언두/리두)
                Row(
                  children: [
                    // 뒤로가기 버튼
                    GestureDetector(
                      onTap: () async {
                        Navigator.of(context).maybePop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 24,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.75),
                        ),
                      ),
                    ),

                    // 언두 버튼
                    AnimatedBuilder(
                      animation: editorService,
                      builder:
                          (context, _) => GestureDetector(
                            onTap: () {
                              editorService.undo();
                            },
                            child: Container(
                              padding: const EdgeInsets.only(
                                top: 12,
                                bottom: 8,
                                left: 8,
                                right: 8,
                              ),
                              child: SvgPicture.asset(
                                'assets/icons/editor_undo.svg',
                                width: 26,
                                height: 26,
                                colorFilter: ColorFilter.mode(
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(
                                    editorService.canUndo ? 0.6 : 0.15,
                                  ),
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                    ),

                    // 리두 버튼
                    AnimatedBuilder(
                      animation: editorService,
                      builder:
                          (context, _) => GestureDetector(
                            onTap: () {
                              editorService.redo();
                            },
                            child: Container(
                              padding: const EdgeInsets.only(
                                top: 12,
                                bottom: 8,
                                left: 8,
                                right: 8,
                              ),
                              child: SvgPicture.asset(
                                'assets/icons/editor_redo.svg',
                                width: 26,
                                height: 26,
                                colorFilter: ColorFilter.mode(
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(
                                    editorService.canRedo ? 0.6 : 0.15,
                                  ),
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                    ),
                  ],
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

                      onSelected: (value) async {
                        if (value == 'load') {
                          onLoadDraft?.call();
                        } else if (value == 'save') {
                          final success = await onSaveDraft?.call();
                          // 명시적 임시저장 시 성공했을 때만 사용자 알림
                          if (success == true) {
                            ErrorHandler.showInfo(
                              context,
                              context.tr('draft_saved'),
                            );
                          }
                        }
                      },
                      itemBuilder:
                          (context) => [
                            PopupMenuItem(
                              value: 'load',
                              child: Row(
                                children: [
                                  Text(
                                    context.tr('load_draft'),
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
                                    context.tr('save_draft'),
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
                          context.tr('next'),
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
