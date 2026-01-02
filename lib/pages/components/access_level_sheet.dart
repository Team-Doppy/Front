import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 상태 관리 헬퍼 클래스
class _AccessLevelStateHelper {
  Set<int> selectedGroupIds = <int>{};
  String currentAccessLevel = 'PUBLIC';
  bool initialized = false;
  bool isLoading = false; // 🎯 로딩 상태
  bool isBatchMode = false; // 🎯 배치 모드 플래그

  void reset() {
    selectedGroupIds = <int>{};
    currentAccessLevel = 'PUBLIC';
    initialized = false;
    isLoading = false;
    isBatchMode = false;
  }
}

class AccessLevelSheet {
  static bool _hasScrolled = false;

  // 상태 관리 헬퍼 인스턴스
  static final _StateHelper = _AccessLevelStateHelper();

  /// 공개범위 변경 바텀시트 표시
  /// isBatchMode가 true이면 API 호출 없이 선택만 (onChanged만 호출)
  static void show(
    BuildContext context, {
    required String postId, // 🎯 필수: 포스트 ID (배치 모드일 때도 전달)
    required String currentAccessLevel,
    required List<int>? currentSharedGroupIds,
    List<String>? currentSharedGroupNames, // 🎯 서버에서 제공하는 그룹 이름 목록 (optional)
    required Function(String accessLevel, List<int>? sharedGroupIds) onChanged,
    int? excludeGroupId, // 🎯 제외할 그룹 ID (현재 그룹 제외용)
    bool isBatchMode = false, // 🎯 배치 모드: true이면 API 호출 없이 onChanged만 호출
  }) async {
    debugPrint(
      '[AccessLevelSheet] show 호출 - postId: $postId, currentAccessLevel: $currentAccessLevel, isBatchMode: $isBatchMode',
    );
    _hasScrolled = false; // 스크롤 플래그 초기화
    _StateHelper.reset(); // 상태 초기화
    final parentContext = context; // 부모 context 저장

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
                // 🎯 선택된 그룹 ID 목록 관리 (다중 선택 가능) - 상태로 관리
                final Set<int> selectedGroupIds =
                    (() {
                      // 초기 상태 설정 (한 번만)
                      if (!_StateHelper.initialized) {
                        _StateHelper.selectedGroupIds =
                            currentSharedGroupIds != null
                                ? currentSharedGroupIds.toSet()
                                : <int>{};
                        _StateHelper.currentAccessLevel = currentAccessLevel;
                        _StateHelper.initialized = true;
                      }
                      return _StateHelper.selectedGroupIds;
                    })();

                // 현재 accessLevel 가져오기
                final String activeAccessLevel =
                    _StateHelper.currentAccessLevel;

                // 🎯 isBatchMode를 StateHelper에 저장 (내부 메서드에서 사용)
                _StateHelper.isBatchMode = isBatchMode;

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
                                            activeAccessLevel,
                                            currentSharedGroupIds,
                                            currentSharedGroupNames, // 🎯 서버에서 제공하는 그룹 이름 목록
                                            onChanged,
                                            setModalState,
                                            scrollController,
                                            postId,
                                            groupProvider,
                                            selectedGroupIds, // 🎯 선택된 그룹 ID 목록 전달
                                            excludeGroupId, // 🎯 제외할 그룹 ID 전달
                                            (accessLevel, sharedGroupIds) {
                                              // 🎯 상태 업데이트
                                              _StateHelper.currentAccessLevel =
                                                  accessLevel;
                                              onChanged(
                                                accessLevel,
                                                sharedGroupIds,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),

                                    // 🎯 완료 버튼
                                    _buildDoneButton(
                                      bottomSheetContext,
                                      parentContext,
                                      activeAccessLevel,
                                      currentAccessLevel,
                                      currentSharedGroupIds,
                                      postId,
                                      onChanged,
                                      setModalState,
                                      groupProvider,
                                      () {
                                        // 성공 콜백 (필요 시 추가 로직 구현)
                                      },
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
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color:
                  isSelected
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.9)
                      : Colors.transparent,
            ),
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
    String currentAccessLevel,
    List<int>? currentSharedGroupIds,
    List<String>? currentSharedGroupNames, // 🎯 서버에서 제공하는 그룹 이름 목록
    Function(String accessLevel, List<int>? sharedGroupIds) onChanged,
    StateSetter setModalState,
    ScrollController scrollController,
    String postId, // 🎯 필수: 포스트 ID
    GroupProvider groupProvider, // 🎯 GroupProvider를 직접 전달
    Set<int> selectedGroupIds, // 🎯 선택된 그룹 ID 목록
    int? excludeGroupId, // 🎯 제외할 그룹 ID (현재 그룹 제외용)
    Function(String accessLevel, List<int>? sharedGroupIds)
    onGroupChanged, // 🎯 그룹 변경 추적 콜백
  ) {
    // 🎯 StatefulBuilder가 리빌드될 때마다 최신 상태 반영
    final activeAccessLevel = _StateHelper.currentAccessLevel;
    final accessLevelUpper = (activeAccessLevel.toString()).toUpperCase();
    final isPublic = accessLevelUpper == 'PUBLIC';
    final isPrivate = accessLevelUpper == 'PRIVATE';
    final isFriends = accessLevelUpper == 'FRIENDS';

    // 🎯 전체 친구 그룹(isSystem == true)인지 확인 (친구 공개 탭 숨김용)
    final isAllFriendsGroup =
        excludeGroupId != null &&
        groupProvider.myGroups.any(
          (group) => group.isSystem == true && group.id == excludeGroupId,
        );

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
        // 전체공개
        _buildAccessLevelItem(
          title: bottomSheetContext.tr('public_access'),
          isSelected: isPublic,
          context: bottomSheetContext,
          onTap: () {
            // 🎯 선택만 하도록 변경 (완료 버튼에서 처리)
            setModalState(() {
              _StateHelper.currentAccessLevel = SystemCategoryKeys.public;
              _StateHelper.selectedGroupIds.clear(); // 그룹 선택 초기화
            });
          },
        ),

        // 모든 친구 (전체 친구 그룹(isSystem == true)일 때는 숨김)
        if (!isAllFriendsGroup)
          _buildAccessLevelItem(
            title: bottomSheetContext.tr('friends_access'),
            isSelected: isFriends,
            context: bottomSheetContext,
            onTap: () {
              // 🎯 선택만 하도록 변경 (완료 버튼에서 처리)
              setModalState(() {
                _StateHelper.currentAccessLevel = SystemCategoryKeys.friends;
                _StateHelper.selectedGroupIds.clear(); // 그룹 선택 초기화
              });
            },
          ),

        // 나만보기
        _buildAccessLevelItem(
          title: bottomSheetContext.tr('private_access'),
          isSelected: isPrivate,
          context: bottomSheetContext,
          onTap: () {
            // 🎯 선택만 하도록 변경 (완료 버튼에서 처리)
            setModalState(() {
              _StateHelper.currentAccessLevel = SystemCategoryKeys.private;
              _StateHelper.selectedGroupIds.clear(); // 그룹 선택 초기화
            });
          },
        ),

        // 실제 그룹들만 표시 (시스템 그룹 및 제외 그룹 제외)
        if (groupProvider.myGroups.isNotEmpty) ...[
          // 실제 그룹 필터링 (시스템 그룹 및 제외 그룹 제외)
          ...groupProvider.myGroups
              .where((group) {
                // 🎯 제외할 그룹 ID가 지정되었으면 제외
                final excludeGroupIdParam = excludeGroupId;
                if (excludeGroupIdParam != null) {
                  // 🎯 전체 친구 그룹(-1)인 경우: 시스템 그룹 제외
                  if (excludeGroupIdParam == -1) {
                    if (group.isSystem == true) return false;
                  } else {
                    // 🎯 일반 그룹인 경우: ID가 일치하는 그룹 제외
                    if (group.id == excludeGroupIdParam) return false;
                  }
                }
                // 🎯 시스템 그룹은 항상 제외 (excludeGroupId가 null이 아닐 때는 위에서 처리됨)
                if (group.isSystem == true) return false;
                return true;
              })
              .map((group) {
                // 매번 최신 상태 확인
                final isGroupSelected = selectedGroupIds.contains(group.id);
                final activeIsGroups = (accessLevelUpper == 'GROUPS');
                // 🎯 시스템 그룹(isSystem == true)인 경우 "모든 친구"로 표시
                final groupDisplayName =
                    group.isSystem == true
                        ? bottomSheetContext.tr('all_friends')
                        : group.name;
                return _buildAccessLevelItem(
                  title: groupDisplayName,
                  isSelected: activeIsGroups && isGroupSelected,
                  context: bottomSheetContext,
                  onTap: () {
                    // 🎯 그룹 선택/해제 토글 (다중 선택 가능) - 선택만 하도록 변경
                    setModalState(() {
                      // 상태 업데이트 - 즉시 반영
                      if (_StateHelper.selectedGroupIds.contains(group.id)) {
                        _StateHelper.selectedGroupIds.remove(group.id);
                      } else {
                        _StateHelper.selectedGroupIds.add(group.id);
                      }

                      // 🎯 선택된 그룹이 있으면 GROUPS로 업데이트, 없으면 PUBLIC로 변경
                      final newAccessLevel =
                          _StateHelper.selectedGroupIds.isEmpty
                              ? SystemCategoryKeys.public
                              : SystemCategoryKeys.groups;

                      // 상태에 즉시 반영
                      _StateHelper.currentAccessLevel = newAccessLevel;
                    });
                  },
                );
              }),
        ] else if (groupProvider.isLoading) ...[
          // 로딩 중
          Padding(
            padding: EdgeInsets.all(20.0),
            child: CircularProgressIndicator(),
          ),
        ],

        // BottomSheet 하단 여백
        const SizedBox(height: 20),
      ],
    );
  }

  /// 완료 버튼 빌드
  static Widget _buildDoneButton(
    BuildContext bottomSheetContext,
    BuildContext parentContext,
    String activeAccessLevel,
    String originalAccessLevel,
    List<int>? originalSharedGroupIds,
    String postId, // 🎯 필수: 포스트 ID
    Function(String accessLevel, List<int>? sharedGroupIds) onChanged,
    StateSetter setModalState,
    GroupProvider groupProvider,
    VoidCallback onSuccess,
  ) {
    // 🎯 변경 여부 확인
    final isBatchMode = _StateHelper.isBatchMode;
    // 🎯 배치 모드에서는 항상 버튼 활성화 (사용자가 명시적으로 변경하기를 눌러야 함)
    final hasChanged =
        isBatchMode ||
        activeAccessLevel != originalAccessLevel ||
        (activeAccessLevel == SystemCategoryKeys.groups &&
            !_areGroupIdsEqual(
              _StateHelper.selectedGroupIds,
              originalSharedGroupIds,
            ));

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🎯 디바이더 - 화면 너비 전체
          Container(
            width: double.infinity,
            height: 0.5,
            color: Theme.of(
              bottomSheetContext,
            ).colorScheme.onSurface.withOpacity(0.1),
          ),
          // 🎯 GestureDetector로 변경 (배경 없음, 전체 영역 클릭 가능)
          GestureDetector(
            behavior: HitTestBehavior.opaque, // 🎯 여백 부분도 클릭 가능하도록
            onTap:
                hasChanged && !_StateHelper.isLoading
                    ? () async {
                      // 🎯 로딩 시작 (즉시 UI 업데이트)
                      setModalState(() {
                        _StateHelper.isLoading = true;
                      });
                      // 🎯 UI 업데이트 완료 대기
                      await Future.delayed(Duration.zero);

                      try {
                        // 🎯 변경할 공개범위 및 그룹 ID 결정
                        final selectedAccessLevel = activeAccessLevel;
                        final selectedSharedGroupIds =
                            activeAccessLevel == SystemCategoryKeys.groups &&
                                    _StateHelper.selectedGroupIds.isNotEmpty
                                ? _StateHelper.selectedGroupIds.toList()
                                : null;

                        // 🎯 GROUPS인데 sharedGroupIds가 비어있으면 PRIVATE으로 자동 변경
                        String finalAccessLevel = selectedAccessLevel;
                        List<int>? finalSharedGroupIds = selectedSharedGroupIds;
                        if (selectedAccessLevel == SystemCategoryKeys.groups) {
                          final sharedGroupIds = selectedSharedGroupIds;
                          if (sharedGroupIds == null ||
                              sharedGroupIds.isEmpty) {
                            finalAccessLevel = SystemCategoryKeys.private;
                            finalSharedGroupIds = null;
                          }
                        }

                        // 🎯 변경 전 공개범위 및 그룹 ID 저장
                        final previousAccessLevel = originalAccessLevel;
                        final previousSharedGroupIds = originalSharedGroupIds;

                        // 🎯 배치 모드 체크 (가장 먼저 확인)
                        final isBatchMode = _StateHelper.isBatchMode;
                        debugPrint(
                          '[AccessLevelSheet] 변경하기 버튼 클릭 - isBatchMode: $isBatchMode',
                        );

                        if (isBatchMode) {
                          // 🎯 배치 모드: onChanged만 호출하고 바텀시트 닫기 (API는 manage_group_screen에서 처리)

                          onChanged(finalAccessLevel, finalSharedGroupIds);
                          Navigator.of(bottomSheetContext).pop();
                          return; // 🎯 배치 모드에서는 여기서 종료
                        }

                        // 🎯 단일 포스트 모드: API 업데이트
                        final success = await _updateAccessLevel(
                          bottomSheetContext,
                          postId,
                          finalAccessLevel,
                          finalSharedGroupIds,
                          onChanged,
                          onError: () {
                            // 🎯 실패 시 바텀시트 닫기
                            Navigator.of(bottomSheetContext).pop();
                            // 🎯 스낵바로 에러 메시지 표시
                            if (parentContext.mounted) {
                              ErrorHandler.showError(
                                parentContext,
                                '공개범위 변경에 실패했습니다',
                              );
                            }
                          },
                        );

                        if (success) {
                          // 🎯 단일 포스트 모드: postCount 업데이트 및 캐시 무효화
                          if (!isBatchMode) {
                            // 🎯 API 성공 시에만 postCount 업데이트 및 캐시 무효화
                            if (previousAccessLevel ==
                                    SystemCategoryKeys.groups &&
                                previousSharedGroupIds != null &&
                                previousSharedGroupIds.isNotEmpty) {
                              // 🎯 원래 GROUPS에 있던 그룹들의 postCount 감소
                              final groupIdToDelta = <int, int>{};
                              for (final groupId in previousSharedGroupIds) {
                                groupIdToDelta[groupId] = -1;
                              }
                              groupProvider.updateMultipleGroupsPostCount(
                                groupIdToDelta,
                              );
                              ManageGroupScreen.invalidateMultipleGroupsPostsCache(
                                previousSharedGroupIds,
                              );
                            }

                            // 🎯 FRIENDS → 다른 공개범위로 변경 시 allFriends 그룹 포스트 캐시 무효화
                            if (previousAccessLevel ==
                                    SystemCategoryKeys.friends &&
                                finalAccessLevel !=
                                    SystemCategoryKeys.friends) {
                              groupProvider.updateGroupPostCount(-1, -1);
                              ManageGroupScreen.invalidateGroupPostsCache(-1);
                            }

                            // 🎯 변경 후 공개범위에 따른 postCount 업데이트
                            if (finalAccessLevel == SystemCategoryKeys.groups &&
                                finalSharedGroupIds != null &&
                                finalSharedGroupIds.isNotEmpty) {
                              final groupIdToDelta = <int, int>{};
                              for (final groupId in finalSharedGroupIds) {
                                groupIdToDelta[groupId] = 1;
                              }
                              groupProvider.updateMultipleGroupsPostCount(
                                groupIdToDelta,
                              );
                              ManageGroupScreen.invalidateMultipleGroupsPostsCache(
                                finalSharedGroupIds,
                              );
                            }

                            if (finalAccessLevel ==
                                SystemCategoryKeys.friends) {
                              groupProvider.updateGroupPostCount(-1, 1);
                              ManageGroupScreen.invalidateGroupPostsCache(-1);
                            }

                            // 🎯 단일 포스트 모드에서만 성공 메시지 표시
                            onSuccess();
                          } else {
                            // 🎯 배치 모드: onSuccess만 호출 (메시지는 manage_group_screen에서 처리)
                            onSuccess();
                          }

                          Navigator.of(bottomSheetContext).pop();

                          // 🎯 배치 모드가 아닌 경우에만 성공 메시지 표시
                          if (!isBatchMode) {
                            // 🎯 바텀시트가 닫힌 후에 메시지 표시
                            await Future.delayed(
                              const Duration(milliseconds: 300),
                            );
                            if (parentContext.mounted) {
                              ErrorHandler.showInfo(
                                parentContext,
                                parentContext.tr('access_level_changed'),
                              );
                            }
                          }
                        } else {
                          // 🎯 실패 시 바텀시트 닫기
                          Navigator.of(bottomSheetContext).pop();
                          // 🎯 스낵바로 에러 메시지 표시
                          if (parentContext.mounted) {
                            ErrorHandler.showError(
                              parentContext,
                              '공개범위 변경에 실패했습니다',
                            );
                          }
                        }
                      } finally {
                        // 🎯 로딩 종료
                        if (bottomSheetContext.mounted) {
                          setModalState(() {
                            _StateHelper.isLoading = false;
                          });
                        }
                      }
                    }
                    : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              alignment: Alignment.center,
              child:
                  _StateHelper.isLoading
                      ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(bottomSheetContext).colorScheme.onSurface,
                          ),
                        ),
                      )
                      : Text(
                        '변경하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color:
                              hasChanged
                                  ? Theme.of(
                                    bottomSheetContext,
                                  ).colorScheme.onSurface
                                  : Theme.of(
                                    bottomSheetContext,
                                  ).colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  /// 그룹 ID 목록이 같은지 확인
  static bool _areGroupIdsEqual(Set<int> set1, List<int>? list2) {
    if (list2 == null) return set1.isEmpty;
    if (set1.length != list2.length) return false;
    return set1.every((id) => list2.contains(id));
  }

  /// 공개범위 업데이트
  /// 성공 시 true, 실패 시 false 반환
  /// 공개범위 업데이트
  /// isBatchMode가 true이면 API 호출 없이 onChanged만 호출 (선택만)
  /// isBatchMode가 false이면 단일 포스트 변경: 배치 엔드포인트를 postIds: [postId]로 호출
  static Future<bool> _updateAccessLevel(
    BuildContext context,
    String postId,
    String accessLevel,
    List<int>? sharedGroupIds,
    Function(String accessLevel, List<int>? sharedGroupIds) onChanged, {
    VoidCallback? onError,
  }) async {
    final isBatchMode = _StateHelper.isBatchMode;
    debugPrint(
      '[AccessLevelSheet] _updateAccessLevel 호출 - postId: $postId, accessLevel: $accessLevel, isBatchMode: $isBatchMode',
    );

    // 🎯 배치 모드 체크 - API 호출 없이 onChanged만 호출
    if (isBatchMode) {
      debugPrint('[AccessLevelSheet] 배치 모드: API 호출 건너뜀, onChanged만 호출');
      onChanged(accessLevel, sharedGroupIds);
      return true;
    }

    // 🎯 단일 포스트 변경: 배치 엔드포인트를 postIds: [postId]로 호출
    try {
      final postIdInt = int.tryParse(postId);
      if (postIdInt == null) {
        throw Exception('유효하지 않은 포스트 ID입니다: $postId');
      }

      debugPrint(
        '[AccessLevelSheet] 단일 포스트 변경: 배치 엔드포인트 호출 - postIds: [$postIdInt]',
      );

      // 🎯 배치 엔드포인트를 단일 포스트로 호출
      final updatedPosts = await BlogService().batchUpdatePostsAccessLevel(
        postIds: [postIdInt],
        accessLevel: accessLevel,
        sharedGroupIds: sharedGroupIds,
      );

      if (updatedPosts.isEmpty) {
        throw Exception('공개범위 변경에 실패했습니다');
      }

      onChanged(accessLevel, sharedGroupIds);

      return true;
    } catch (e, stackTrace) {
      // 🎯 상세한 에러 로그 출력
      debugPrint('[AccessLevelSheet] 공개범위 변경 실패');
      debugPrint('[AccessLevelSheet] PostId: $postId');
      debugPrint('[AccessLevelSheet] AccessLevel: $accessLevel');
      debugPrint('[AccessLevelSheet] SharedGroupIds: $sharedGroupIds');
      debugPrint('[AccessLevelSheet] Error: $e');
      debugPrint('[AccessLevelSheet] StackTrace: $stackTrace');

      // 🎯 DioException인 경우 추가 정보 출력
      if (e is DioException) {
        debugPrint('[AccessLevelSheet] DioException Type: ${e.type}');
        debugPrint('[AccessLevelSheet] Status Code: ${e.response?.statusCode}');
        debugPrint('[AccessLevelSheet] Response Data: ${e.response?.data}');
        debugPrint('[AccessLevelSheet] Request Path: ${e.requestOptions.path}');
        debugPrint('[AccessLevelSheet] Request Data: ${e.requestOptions.data}');
      }

      // 🎯 onError 콜백 호출 (바텀시트 닫기 및 스낵바 표시)
      if (onError != null) {
        onError();
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
