import 'dart:ui';

import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccessLevelSheet {
  static bool _hasScrolled = false;

  /// 공개범위 변경 바텀시트 표시
  static void show(
    BuildContext context, {
    required String postId,
    required String currentAccessLevel,
    required List<int>? currentSharedGroupIds,
    List<String>? currentSharedGroupNames, // 🎯 서버에서 제공하는 그룹 이름 목록 (optional)
    required Function(String accessLevel, List<int>? sharedGroupIds) onChanged,
  }) async {
    _hasScrolled = false; // 스크롤 플래그 초기화
    final parentContext = context; // 부모 context 저장

    // 🎯 그룹 변경 여부 추적 (시트가 닫힐 때 스낵바 표시용)
    bool hasGroupChanged = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext bottomSheetContext) {
        return Consumer<GroupProvider>(
          builder: (context, groupProvider, _) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                // 🎯 선택된 그룹 ID 목록 관리 (다중 선택 가능)
                final Set<int> selectedGroupIds =
                    currentSharedGroupIds != null
                        ? currentSharedGroupIds.toSet()
                        : <int>{};

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
                                    const SizedBox(height: 16),

                                    // 공개범위 리스트
                                    Expanded(
                                      child: RawScrollbar(
                                        controller: scrollController,
                                        thumbColor: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.3),
                                        radius: const Radius.circular(20),
                                        thickness: 4,
                                        thumbVisibility: false,
                                        child: SingleChildScrollView(
                                          controller: scrollController,
                                          child: _buildAccessLevelContent(
                                            bottomSheetContext,
                                            parentContext,
                                            postId,
                                            currentAccessLevel,
                                            currentSharedGroupIds,
                                            currentSharedGroupNames, // 🎯 서버에서 제공하는 그룹 이름 목록
                                            onChanged,
                                            setModalState,
                                            scrollController,
                                            groupProvider.myGroups,
                                            selectedGroupIds, // 🎯 선택된 그룹 ID 목록 전달
                                            (accessLevel, sharedGroupIds) {
                                              // 🎯 그룹 변경 추적
                                              hasGroupChanged = true;
                                              onChanged(
                                                accessLevel,
                                                sharedGroupIds,
                                              );
                                            },
                                          ),
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
      },
    ).then((_) {
      // 🎯 시트가 닫힌 후 그룹이 변경되었으면 스낵바 표시
      if (hasGroupChanged && parentContext.mounted) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (parentContext.mounted) {
            ErrorHandler.showInfo(
              parentContext,
              parentContext.tr('access_level_changed'),
            );
          }
        });
      }
    });
  }

  /// 공개범위 아이템 빌드
  static Widget _buildAccessLevelItem({
    required String title,
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
                if (isSelected)
                  Icon(
                    Icons.check,
                    color:
                        isSelected && isDarkMode
                            ? AppColors.darkSurface
                            : isSelected && !isDarkMode
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 공개범위 바텀시트 내용 빌드
  static Widget _buildAccessLevelContent(
    BuildContext bottomSheetContext,
    BuildContext parentContext,
    String postId,
    String currentAccessLevel,
    List<int>? currentSharedGroupIds,
    List<String>? currentSharedGroupNames, // 🎯 서버에서 제공하는 그룹 이름 목록
    Function(String accessLevel, List<int>? sharedGroupIds) onChanged,
    StateSetter setModalState,
    ScrollController scrollController,
    List<dynamic> groups,
    Set<int> selectedGroupIds, // 🎯 선택된 그룹 ID 목록
    Function(String accessLevel, List<int>? sharedGroupIds)
    onGroupChanged, // 🎯 그룹 변경 추적 콜백
  ) {
    final accessLevelUpper = (currentAccessLevel.toString()).toUpperCase();
    final isPublic = accessLevelUpper == 'PUBLIC';
    final isPrivate = accessLevelUpper == 'PRIVATE';
    final isFriends = accessLevelUpper == 'FRIENDS';
    final isGroups = accessLevelUpper == 'GROUPS';

    return Consumer<GroupProvider>(
      builder: (context, groupProvider, child) {
        // 그룹 목록 로드 및 스크롤
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (groupProvider.myGroups.isEmpty &&
              !groupProvider.isLoading &&
              !groupProvider.isGroupsCached) {
            groupProvider.fetchMyGroups();
          }

          // 그룹 목록이 준비되면 스크롤 (스크롤바가 뜰 정도로 길 때만, 한 번만)
          if (!_hasScrolled) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (scrollController.hasClients && !_hasScrolled) {
                // 스크롤이 가능한지 확인 (maxScrollExtent > 0)
                if (scrollController.position.maxScrollExtent > 0) {
                  _hasScrolled = true;
                  final selectedIndex = _getSelectedIndex(
                    currentAccessLevel,
                    currentSharedGroupIds,
                    groupProvider.myGroups,
                  );
                  if (selectedIndex >= 0) {
                    // 각 항목의 높이는 padding 16*2 + 텍스트 높이 = 약 48
                    const double itemHeight = 48.0;
                    final scrollOffset = selectedIndex * itemHeight;
                    scrollController.animateTo(
                      scrollOffset,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                } else {
                  // 스크롤이 필요 없으면 플래그만 설정
                  _hasScrolled = true;
                }
              }
            });
          }
        });

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 전체 공개
            _buildAccessLevelItem(
              title: bottomSheetContext.tr('public_access'),
              isSelected: isPublic,
              context: bottomSheetContext,
              onTap: () async {
                final success = await _updateAccessLevel(
                  bottomSheetContext,
                  postId,
                  'PUBLIC',
                  null,
                  onChanged,
                );
                if (success) {
                  Navigator.of(bottomSheetContext).pop();
                  // 바텀시트가 닫힌 후에 메시지 표시
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (parentContext.mounted) {
                    ErrorHandler.showInfo(
                      parentContext,
                      parentContext.tr('access_level_changed'),
                    );
                  }
                }
              },
            ),

            // 친구 공개
            _buildAccessLevelItem(
              title: bottomSheetContext.tr('friends_access'),
              isSelected: isFriends,
              context: bottomSheetContext,
              onTap: () async {
                final success = await _updateAccessLevel(
                  bottomSheetContext,
                  postId,
                  'FRIENDS',
                  null,
                  onChanged,
                );
                if (success) {
                  Navigator.of(bottomSheetContext).pop();
                  // 바텀시트가 닫힌 후에 메시지 표시
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (parentContext.mounted) {
                    ErrorHandler.showInfo(
                      parentContext,
                      parentContext.tr('access_level_changed'),
                    );
                  }
                }
              },
            ),

            // 나만보기
            _buildAccessLevelItem(
              title: bottomSheetContext.tr('private_access'),
              isSelected: isPrivate,
              context: bottomSheetContext,
              onTap: () async {
                final success = await _updateAccessLevel(
                  bottomSheetContext,
                  postId,
                  'PRIVATE',
                  null,
                  onChanged,
                );
                if (success) {
                  Navigator.of(bottomSheetContext).pop();
                  // 바텀시트가 닫힌 후에 메시지 표시
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (parentContext.mounted) {
                    ErrorHandler.showInfo(
                      parentContext,
                      parentContext.tr('access_level_changed'),
                    );
                  }
                }
              },
            ),

            // 실제 그룹들만 표시 (시스템 그룹 제외)
            if (groupProvider.myGroups.isNotEmpty) ...[
              // 실제 그룹 필터링 (시스템 그룹 제외)
              ...groupProvider.myGroups
                  .where((group) {
                    // 시스템 그룹이 아닌 그룹만
                    return group.isSystem != true;
                  })
                  .map((group) {
                    final isGroupSelected = selectedGroupIds.contains(group.id);
                    return _buildAccessLevelItem(
                      title: group.name,
                      isSelected: isGroups && isGroupSelected,
                      context: bottomSheetContext,
                      onTap: () {
                        // 🎯 그룹 선택/해제 토글 (다중 선택 가능)
                        setModalState(() {
                          if (isGroupSelected) {
                            selectedGroupIds.remove(group.id);
                          } else {
                            selectedGroupIds.add(group.id);
                          }

                          // 🎯 선택된 그룹이 있으면 GROUPS로 업데이트, 없으면 PUBLIC로 변경
                          final newSharedGroupIds =
                              selectedGroupIds.isEmpty
                                  ? null
                                  : selectedGroupIds.toList();
                          final newAccessLevel =
                              selectedGroupIds.isEmpty ? 'PUBLIC' : 'GROUPS';

                          // 🎯 즉시 API 업데이트 (시트는 열어둠 - 다중 선택 가능)
                          _updateAccessLevel(
                            bottomSheetContext,
                            postId,
                            newAccessLevel,
                            newSharedGroupIds,
                            onChanged,
                          ).then((success) {
                            // 🎯 성공 시 그룹 변경 추적 (스낵바는 시트가 닫힐 때 표시)
                            if (success) {
                              onGroupChanged(newAccessLevel, newSharedGroupIds);
                            }
                          });
                        });
                      },
                    );
                  }),
            ] else if (groupProvider.isLoading) ...[
              // 로딩 중
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ),
            ],

            // BottomSheet 하단 여백
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  /// 공개범위 업데이트
  /// 성공 시 true, 실패 시 false 반환
  static Future<bool> _updateAccessLevel(
    BuildContext context,
    String postId,
    String accessLevel,
    List<int>? sharedGroupIds,
    Function(String accessLevel, List<int>? sharedGroupIds) onChanged,
  ) async {
    try {
      final postIdInt = int.tryParse(postId);
      if (postIdInt == null) {
        throw Exception(context.tr('invalid_post_id'));
      }

      await BlogService().updatePostAccessLevel(
        postId: postIdInt,
        accessLevel: accessLevel,
        sharedGroupIds: sharedGroupIds,
      );

      onChanged(accessLevel, sharedGroupIds);

      return true;
    } catch (e) {
      if (context.mounted) {
        final errorMessage = context
            .tr('access_level_change_failed')
            .replaceAll('{error}', e.toString());
        ErrorHandler.showError(context, errorMessage);
      }
      return false;
    }
  }

  /// 선택된 항목의 인덱스 계산
  static int _getSelectedIndex(
    String currentAccessLevel,
    List<int>? currentSharedGroupIds,
    List<dynamic> groups,
  ) {
    final accessLevelUpper = currentAccessLevel.toUpperCase();

    if (accessLevelUpper == 'PUBLIC') {
      return 0;
    } else if (accessLevelUpper == 'FRIENDS') {
      return 1;
    } else if (accessLevelUpper == 'PRIVATE') {
      return 2;
    } else if (accessLevelUpper == 'GROUPS') {
      // 특정 그룹 선택 (그룹 공개 일반 옵션 제거됨)
      if (groups.isNotEmpty &&
          currentSharedGroupIds != null &&
          currentSharedGroupIds.isNotEmpty) {
        // 실제 그룹만 필터링 (시스템 그룹 제외)
        final actualGroups =
            groups.where((g) {
              return g.isSystem != true;
            }).toList();

        final selectedGroupId = currentSharedGroupIds.first;
        final groupIndex = actualGroups.indexWhere(
          (g) => g.id == selectedGroupId,
        );
        if (groupIndex >= 0) {
          return 3 + groupIndex; // 3 (Public, Friends, Private) + groupIndex
        }
      }
    }

    return -1; // 선택된 항목 없음
  }
}
