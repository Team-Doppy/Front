import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';

// 상태 관리 헬퍼 클래스
class _AccessLevelStateHelper {
  String currentAccessLevel = SystemCategoryKeys.public;
  bool initialized = false;
  bool isLoading = false; // 🎯 로딩 상태
  bool isBatchMode = false; // 🎯 배치 모드 플래그

  void reset() {
    currentAccessLevel = SystemCategoryKeys.public;
    initialized = false;
    isLoading = false;
    isBatchMode = false;
  }
}

class AccessLevelSheet {
  // 상태 관리 헬퍼 인스턴스
  static final _StateHelper = _AccessLevelStateHelper();

  /// 공개범위 변경 바텀시트 표시
  /// isBatchMode가 true이면 API 호출 없이 선택만 (onChanged만 호출)
  static void show(
    BuildContext context, {
    required String postId, // 🎯 필수: 포스트 ID (배치 모드일 때도 전달)
    required String currentAccessLevel,
    required Function(String accessLevel) onChanged,
    bool isBatchMode = false, // 🎯 배치 모드: true이면 API 호출 없이 onChanged만 호출
  }) async {
    debugPrint(
      '[AccessLevelSheet] show 호출 - postId: $postId, currentAccessLevel: $currentAccessLevel, isBatchMode: $isBatchMode',
    );
    // 스크롤 플래그 제거 (그룹 기능 제거로 인해 불필요)
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
        return StatefulBuilder(
          builder: (context, setModalState) {
            // 초기 상태 설정 (한 번만)
            if (!_StateHelper.initialized) {
              _StateHelper.currentAccessLevel = currentAccessLevel;
              _StateHelper.initialized = true;
            }

            // 현재 accessLevel 가져오기
            final String activeAccessLevel = _StateHelper.currentAccessLevel;

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
                                    thumbColor: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.3),
                                    radius: const Radius.circular(20),
                                    thickness: 4,
                                    thumbVisibility: false,
                                    child: SingleChildScrollView(
                                      controller: scrollController,
                                      child: _buildAccessLevelContent(
                                        bottomSheetContext,
                                        parentContext,
                                        activeAccessLevel,
                                        onChanged,
                                        setModalState,
                                        scrollController,
                                        postId,
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
                                  postId,
                                  onChanged,
                                  setModalState,
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
    Function(String accessLevel) onChanged,
    StateSetter setModalState,
    ScrollController scrollController,
    String postId, // 🎯 필수: 포스트 ID
    // 그룹 기능 제거로 인해 onGroupChanged 제거
  ) {
    // 🎯 StatefulBuilder가 리빌드될 때마다 최신 상태 반영
    final activeAccessLevel = _StateHelper.currentAccessLevel;
    final accessLevelUpper = (activeAccessLevel.toString()).toUpperCase();
    final isPublic = accessLevelUpper == SystemCategoryKeys.public;
    final isPrivate = accessLevelUpper == SystemCategoryKeys.private;
    final isFriends = accessLevelUpper == SystemCategoryKeys.friends;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 전체공개
        _buildAccessLevelItem(
          title: bottomSheetContext.tr('public_access'),
          isSelected: isPublic,
          context: bottomSheetContext,
          onTap: () {
            setModalState(() {
              _StateHelper.currentAccessLevel = SystemCategoryKeys.public;
            });
          },
        ),

        // 모든 친구
        _buildAccessLevelItem(
          title: bottomSheetContext.tr('friends_access'),
          isSelected: isFriends,
          context: bottomSheetContext,
          onTap: () {
            setModalState(() {
              _StateHelper.currentAccessLevel = SystemCategoryKeys.friends;
            });
          },
        ),

        // 나만보기
        _buildAccessLevelItem(
          title: bottomSheetContext.tr('private_access'),
          isSelected: isPrivate,
          context: bottomSheetContext,
          onTap: () {
            setModalState(() {
              _StateHelper.currentAccessLevel = SystemCategoryKeys.private;
            });
          },
        ),

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
    String postId, // 🎯 필수: 포스트 ID
    Function(String accessLevel) onChanged,
    StateSetter setModalState,
    VoidCallback onSuccess,
  ) {
    // 🎯 변경 여부 확인
    final isBatchMode = _StateHelper.isBatchMode;
    // 🎯 배치 모드에서는 항상 버튼 활성화 (사용자가 명시적으로 변경하기를 눌러야 함)
    final hasChanged = isBatchMode || activeAccessLevel != originalAccessLevel;

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
                        // 🎯 변경할 공개범위 결정 (그룹 기능 제거로 인해 GROUPS 제거)
                        final finalAccessLevel = activeAccessLevel;

                        // 🎯 배치 모드 체크 (가장 먼저 확인)
                        final isBatchMode = _StateHelper.isBatchMode;
                        debugPrint(
                          '[AccessLevelSheet] 변경하기 버튼 클릭 - isBatchMode: $isBatchMode',
                        );

                        if (isBatchMode) {
                          // 🎯 배치 모드: onChanged만 호출하고 바텀시트 닫기
                          onChanged(finalAccessLevel);
                          Navigator.of(bottomSheetContext).pop();
                          return; // 🎯 배치 모드에서는 여기서 종료
                        }

                        // 🎯 단일 포스트 모드: API 업데이트
                        final success = await _updateAccessLevel(
                          bottomSheetContext,
                          postId,
                          finalAccessLevel,
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
                          // 그룹 기능 제거로 인해 그룹 관련 postCount 업데이트 제거
                          onSuccess();

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

  /// 공개범위 업데이트
  /// 성공 시 true, 실패 시 false 반환
  /// 공개범위 업데이트
  /// isBatchMode가 true이면 API 호출 없이 onChanged만 호출 (선택만)
  /// isBatchMode가 false이면 단일 포스트 변경: 배치 엔드포인트를 postIds: [postId]로 호출
  static Future<bool> _updateAccessLevel(
    BuildContext context,
    String postId,
    String accessLevel,
    Function(String accessLevel) onChanged, {
    VoidCallback? onError,
  }) async {
    final isBatchMode = _StateHelper.isBatchMode;
    debugPrint(
      '[AccessLevelSheet] _updateAccessLevel 호출 - postId: $postId, accessLevel: $accessLevel, isBatchMode: $isBatchMode',
    );

    // 🎯 배치 모드 체크 - API 호출 없이 onChanged만 호출
    if (isBatchMode) {
      debugPrint('[AccessLevelSheet] 배치 모드: API 호출 건너뜀, onChanged만 호출');
      onChanged(accessLevel);
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
      );

      if (updatedPosts.isEmpty) {
        throw Exception('공개범위 변경에 실패했습니다');
      }

      onChanged(accessLevel);

      return true;
    } catch (e, stackTrace) {
      // 🎯 상세한 에러 로그 출력
      debugPrint('[AccessLevelSheet] 공개범위 변경 실패');
      debugPrint('[AccessLevelSheet] PostId: $postId');
      debugPrint('[AccessLevelSheet] AccessLevel: $accessLevel');
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
}
