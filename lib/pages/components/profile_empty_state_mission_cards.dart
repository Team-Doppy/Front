import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/pages/components/profile_edit_sheet.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/pages/screens/group_selection_screen.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

/// 프로필에 포스트가 없을 때 표시되는 미션 카드 위젯
class ProfileEmptyStateMissionCards extends StatelessWidget {
  final BaseFeedProvider feedProvider;

  const ProfileEmptyStateMissionCards({super.key, required this.feedProvider});

  @override
  Widget build(BuildContext context) {
    // 내 프로필일 때만 미션 카드 표시
    if (feedProvider is! MyProfileFeedProvider) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 280,
          child: Center(
            child: Text(
              context.tr('no_posts_on_profile'),
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: Selector2<UserProvider, FriendProvider, _MissionState>(
              selector: (context, userProvider, friendProvider) {
                final user = userProvider.currentUser;

                // 각 미션의 완료 여부 체크
                final hasProfileImage =
                    user?.profileImageUrl != null &&
                    (user?.profileImageUrl?.isNotEmpty ?? false);
                // 🎯 프로필 정보 설정하기: alias와 함께 links 또는 bio 중 하나가 있어야 완료
                final hasAlias = (user?.alias?.isNotEmpty ?? false);
                final hasBio = (user?.selfIntroduction?.isNotEmpty ?? false);
                final hasLinks =
                    (user?.links != null && user!.links!.isNotEmpty);
                final hasProfileInfo = hasAlias && (hasBio || hasLinks);
                // 🎯 실제 친구 1명 이상이어야 완료
                final hasFriends = friendProvider.acceptedFriends.length >= 1;

                return _MissionState(
                  hasProfileImage: hasProfileImage,
                  hasProfileInfo: hasProfileInfo,
                  hasFriends: hasFriends,
                );
              },
              shouldRebuild:
                  (prev, next) =>
                      prev.hasProfileImage != next.hasProfileImage ||
                      prev.hasProfileInfo != next.hasProfileInfo ||
                      prev.hasFriends != next.hasFriends,
              builder: (context, missionState, _) {
                final missions = [
                  MissionData(
                    title: '프로필 이미지\n설정하기',
                    icon: Icons.person,
                    isCompleted: missionState.hasProfileImage,
                    onTap: () => _openProfileImagePicker(context),
                  ),
                  MissionData(
                    title: '프로필 정보\n설정하기',
                    icon: Icons.edit,
                    isCompleted: missionState.hasProfileInfo,
                    onTap: () => _openProfileEdit(context),
                  ),
                  MissionData(
                    title: '그룹 만들고\n친구 초대하기',
                    icon: Icons.person_add,
                    isCompleted: missionState.hasFriends,
                    onTap: () => _navigateToGroupSelection(context),
                  ),
                  MissionData(
                    title: '새로운 포스트\n게시하기',
                    icon: Icons.create,
                    isCompleted: false,
                    onTap: () => _navigateToPostWrite(context),
                  ),
                ]..sort((a, b) {
                  // 🎯 완료되지 않은 항목을 앞으로, 완료된 항목을 뒤로 정렬
                  if (a.isCompleted && !b.isCompleted) {
                    return 1; // a가 완료, b가 미완료 → a를 뒤로
                  } else if (!a.isCompleted && b.isCompleted) {
                    return -1; // a가 미완료, b가 완료 → a를 앞으로
                  }
                  return 0; // 같은 상태면 순서 유지
                });

                return ListView.builder(
                  key: const ValueKey('mission_cards_list'),
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: missions.length,
                  itemExtent: 200, // 🎯 아이템 너비(170) + 마진(4) 고정
                  itemBuilder: (context, index) {
                    final mission = missions[index];
                    return RepaintBoundary(
                      key: ValueKey(
                        'mission_card_${mission.title}_${mission.isCompleted}',
                      ),
                      child: _MissionCard(mission: mission),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 300), // 하단 여백 (스크롤 과도 당김 방지)
        ],
      ),
    );
  }

  /// 프로필 이미지 선택 시트 열기 (갤러리에서 선택)
  /// 🎯 미션 카드에서는 프로필 이미지가 없으므로 바로 갤러리 열기
  void _openProfileImagePicker(BuildContext context) async {
    final myProfileProvider = feedProvider as MyProfileFeedProvider;

    try {
      // 🎯 프로필 이미지가 없을 때는 바로 갤러리에서 선택
      final result = await Navigator.push<MediaPickerResult>(
        context,
        CupertinoPageRoute(
          builder:
              (context) => MediaPickerScreen(
                initialMediaType: MediaType.image,
                maxSelectionCount: 1,
                enableToggle: false, // 토글 없음 (이미지만)
                onMediaSelected: (file) {
                  // 단일 선택이므로 바로 처리
                },
              ),
        ),
      );

      if (result != null && result.files.isNotEmpty && context.mounted) {
        final file = result.files.first;
        // 업로드 시작
        _handleProfileImageSelected(context, file, myProfileProvider);
      }
    } catch (e) {
      debugPrint('[ProfileEmptyStateMissionCards] 이미지 선택 실패: $e');
      if (context.mounted) {
        ErrorHandler.showError(context, '이미지를 선택할 수 없습니다.');
      }
    }
  }

  /// 선택된 프로필 이미지 처리 및 업로드
  Future<void> _handleProfileImageSelected(
    BuildContext context,
    File file,
    MyProfileFeedProvider myProfileProvider,
  ) async {
    debugPrint('[ProfileEmptyStateMissionCards] 프로필 이미지 업로드 시작: ${file.path}');

    try {
      final upload = context.read<UploadService>();
      final task = upload.enqueueFile(file, kind: UploadKind.profile);
      debugPrint('[ProfileEmptyStateMissionCards] 업로드 태스크 생성됨: ${task.state}');

      // 업로드 완료 리스너
      void uploadListener() async {
        debugPrint(
          '[ProfileEmptyStateMissionCards] 업로드 리스너 호출됨: ${task.state}',
        );

        if (!context.mounted) {
          debugPrint('[ProfileEmptyStateMissionCards] context가 unmounted 상태');
          return;
        }

        if (task.state == UploadState.success) {
          try {
            final imageUrl = task.url ?? '';
            debugPrint(
              '[ProfileEmptyStateMissionCards] 업로드 성공, URL: $imageUrl',
            );

            if (imageUrl.isNotEmpty) {
              // 프로필 이미지 업데이트 (await로 완료 대기)
              await myProfileProvider.updateProfileImageAfterUpload(
                imageUrl,
                context,
              );
              debugPrint('[ProfileEmptyStateMissionCards] ✅ 프로필 이미지 업데이트 완료');

              // 🎯 UI 업데이트 안정화를 위한 짧은 지연
              await Future.delayed(const Duration(milliseconds: 100));
            } else {
              debugPrint(
                '[ProfileEmptyStateMissionCards] URL이 비어있음, 프로필 다시 가져오기',
              );
              // URL이 없으면 프로필 다시 가져오기
              await context.read<UserProvider>().fetchMyProfile();

              // 🎯 UI 업데이트 안정화를 위한 짧은 지연
              await Future.delayed(const Duration(milliseconds: 100));
            }

            task.removeListener(uploadListener);
          } catch (e) {
            debugPrint('[ProfileEmptyStateMissionCards] ❌ 프로필 이미지 업데이트 실패: $e');
            if (context.mounted) {
              ErrorHandler.showError(
                context,
                context.tr('profile_image_upload_failed'),
              );
            }
            task.removeListener(uploadListener);
          }
        } else if (task.state == UploadState.failed ||
            task.state == UploadState.cancelled) {
          debugPrint(
            '[ProfileEmptyStateMissionCards] 업로드 실패/취소: ${task.state}',
          );
          if (context.mounted) {
            ErrorHandler.showError(
              context,
              context.tr('profile_image_upload_failed'),
            );
          }
          task.removeListener(uploadListener);
        }
      }

      task.addListener(uploadListener);

      // 초기 상태 확인
      if (task.state == UploadState.success) {
        debugPrint('[ProfileEmptyStateMissionCards] 이미 업로드 완료 상태');
        uploadListener();
      } else if (task.state == UploadState.failed ||
          task.state == UploadState.cancelled) {
        debugPrint('[ProfileEmptyStateMissionCards] 이미 업로드 실패/취소 상태');
        uploadListener();
      } else {
        debugPrint('[ProfileEmptyStateMissionCards] 업로드 진행 중, 리스너 대기...');
      }
    } catch (e) {
      debugPrint('[ProfileEmptyStateMissionCards] ❌ 예외 발생: $e');
      if (context.mounted) {
        ErrorHandler.showError(
          context,
          context.tr('profile_image_upload_failed'),
        );
      }
    }
  }

  /// 프로필 편집 시트 열기
  void _openProfileEdit(BuildContext context) {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;

    // 🎯 ProfileInfoEditBottomSheet가 내부에서 controller를 관리하므로
    // 외부에서 생성하지 않고 null로 전달
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return ProfileInfoEditBottomSheet(
          user: user,
          // controller는 내부에서 자동 생성됨
          onSave: ({
            required String alias,
            required String description,
            Map<String, String>? linkThumbnails,
            List<String>? links,
            Map<String, String>? linkTitles,
          }) async {
            final success = await userProvider.updateProfileInfo(
              alias: alias,
              selfIntroduction: description,
              links: links,
              linkTitles: linkTitles,
            );
            if (success && context.mounted) {
              Navigator.of(context).pop();

              // 🎯 UI 업데이트 안정화를 위한 짧은 지연
              await Future.delayed(const Duration(milliseconds: 150));
            }
          },
        );
      },
    );
  }

  /// 포스트 작성 화면으로 이동
  void _navigateToPostWrite(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PostwriteScreen(isEditingMode: false),
      ),
    );
  }

  /// 그룹 선택 화면으로 이동 (친구 초대)
  void _navigateToGroupSelection(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const GroupSelectionScreen()),
    );
  }
}

/// 미션 상태 (Selector 최적화용)
class _MissionState {
  final bool hasProfileImage;
  final bool hasProfileInfo;
  final bool hasFriends;

  _MissionState({
    required this.hasProfileImage,
    required this.hasProfileInfo,
    required this.hasFriends,
  });
}

/// 미션 데이터 모델
class MissionData {
  final String title;
  final IconData icon;
  final bool isCompleted;
  final VoidCallback onTap;

  MissionData({
    required this.title,
    required this.icon,
    required this.isCompleted,
    required this.onTap,
  });
}

/// 개별 미션 카드 위젯
class _MissionCard extends StatelessWidget {
  final MissionData mission;

  const _MissionCard({required this.mission});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 🎯 완료 안했을 때: backgroundColor 배경
    // 완료했을 때: onBackground 배경
    final cardBackgroundColor =
        mission.isCompleted
            ? theme.colorScheme.onBackground
            : theme.scaffoldBackgroundColor;

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: mission.onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: theme.colorScheme.onSurface.withOpacity(0.1),
          highlightColor: theme.colorScheme.onSurface.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              height: 160, // 🎯 고정 높이로 일관된 레이아웃 유지
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 45, // 아이콘(48) + 여백(16)
                    left: 0,
                    right: 0,
                    child: Text(
                      mission.title,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        // 🎯 완료 안했을 때: onBackground 텍스트
                        // 완료했을 때: backgroundColor 텍스트
                        color:
                            mission.isCompleted
                                ? theme.scaffoldBackgroundColor
                                : theme.colorScheme.onBackground,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 완료 상태 표시 (하단 고정)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Text(
                      mission.isCompleted ? '완료됨' : '시작하기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        // 🎯 완료 안했을 때: onBackground (약간 투명)
                        // 완료했을 때: backgroundColor
                        color:
                            mission.isCompleted
                                ? theme.scaffoldBackgroundColor
                                : theme.colorScheme.onBackground.withOpacity(
                                  0.5,
                                ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
