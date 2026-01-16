import 'dart:io';
import 'package:doppy/pages/screens/profile_image_view_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:flutter/cupertino.dart';

/// Index 2 background (임시 구조)
class Index2Background extends StatefulWidget {
  final bool pauseAnimation; // ✅ 전환(드래그/스냅) 중 반복 애니메이션 일시정지
  const Index2Background({super.key, this.pauseAnimation = false});

  @override
  State<Index2Background> createState() => _Index2BackgroundState();
}

class _Index2BackgroundState extends State<Index2Background>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  File? _croppedProfileFile;
  bool _isUploadingProfileImage = false;
  bool _isUploadComplete = false; // ✅ 업로드 완료 여부
  UploadTask? _profileUploadTask;
  VoidCallback? _profileTaskListener;
  bool _wasAnimating = false; // pause 전 상태 기억

  bool _hasRestoredUploadTask = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // 프로필 들어오고 0.5초 뒤에 안정되면 애니메이션 시작
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !widget.pauseAnimation) {
        _animationController.repeat(reverse: true);
        _wasAnimating = true;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ 업로드 중인 프로필 태스크 복원 (한 번만 실행)
    if (!_hasRestoredUploadTask) {
      _hasRestoredUploadTask = true;
      _restoreUploadTaskIfExists();
    }
  }

  /// ✅ 진행 중이거나 완료된 프로필 업로드 태스크가 있으면 복원
  void _restoreUploadTaskIfExists() {
    final uploadService = context.read<UploadService>();

    // UploadKind.profile인 태스크 찾기 (진행 중 또는 완료된 것)
    UploadTask? activeTask;
    UploadTask? completedTask;

    try {
      // 먼저 진행 중인 태스크 찾기
      activeTask = uploadService.tasks.firstWhere(
        (task) =>
            task.kind == UploadKind.profile &&
            (task.state == UploadState.pending ||
                task.state == UploadState.uploading),
      );
    } catch (e) {
      // 진행 중인 태스크가 없으면 완료된 태스크 찾기
      try {
        completedTask = uploadService.tasks.firstWhere(
          (task) =>
              task.kind == UploadKind.profile &&
              task.state == UploadState.success,
        );
      } catch (e2) {
        // 활성 태스크가 없으면 정상 (처음 진입)
        return;
      }
    }

    final task = activeTask ?? completedTask;
    if (task == null || task.file == null) return;

    // 이미지 파일 복원
    _croppedProfileFile = task.file;

    if (activeTask != null) {
      // 업로드 중인 태스크가 있으면 상태 복원
      _profileUploadTask = activeTask;
      _isUploadingProfileImage = true;
      _isUploadComplete = false;

      // 리스너 다시 연결
      _profileTaskListener = () async {
        if (!mounted) return;

        if (activeTask!.state == UploadState.success) {
          try {
            final imageUrl = activeTask.url ?? '';
            if (imageUrl.isNotEmpty) {
              await context
                  .read<MyProfileFeedProvider>()
                  .updateProfileImageAfterUpload(imageUrl, context);
            } else {
              await context.read<UserProvider>().fetchMyProfile();
            }
          } catch (e) {
            debugPrint('[Index2Background] upload success handler error: $e');
          }

          if (_profileTaskListener != null) {
            activeTask.removeListener(_profileTaskListener!);
            _profileTaskListener = null;
          }
          _profileUploadTask = null;

          if (mounted) {
            setState(() {
              _isUploadingProfileImage = false;
              _isUploadComplete = true; // ✅ 업로드 완료 표시
            });
          }
        } else if (activeTask.state == UploadState.failed ||
            activeTask.state == UploadState.cancelled) {
          if (_profileTaskListener != null) {
            activeTask.removeListener(_profileTaskListener!);
            _profileTaskListener = null;
          }
          _profileUploadTask = null;

          if (mounted) {
            setState(() {
              _isUploadingProfileImage = false;
              _isUploadComplete = false;
            });
          }
        }
      };

      activeTask.addListener(_profileTaskListener!);
    } else if (completedTask != null) {
      // 이미 완료된 태스크
      _isUploadingProfileImage = false;
      _isUploadComplete = true;
    }

    // 바운싱 애니메이션 중지 (이미지가 있으므로)
    _animationController.stop();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant Index2Background oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pauseAnimation == oldWidget.pauseAnimation) return;

    if (widget.pauseAnimation) {
      _wasAnimating = _animationController.isAnimating;
      _animationController.stop();
    } else {
      if (_wasAnimating && !_animationController.isAnimating) {
        _animationController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    if (_profileTaskListener != null && _profileUploadTask != null) {
      _profileUploadTask!.removeListener(_profileTaskListener!);
      _profileTaskListener = null;
    }
    _animationController.dispose();
    super.dispose();
  }

  /// 먼저 이미지 피커를 띄우고, 선택 후 프로필 뷰 스크린으로 이동
  Future<void> _openProfileImageView() async {
    if (_isUploadingProfileImage) return;

    // 1. 먼저 이미지 피커를 띄움 (다크 테마로 강제)
    final pickerResult = await Navigator.push<MediaPickerResult>(
      context,
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => Theme(
              data: AppTheme.darkTheme,
              child: MediaPickerScreen(
                initialMediaType: MediaType.image,
                maxSelectionCount: 1,
                enableToggle: false, // 영상 토글 비활성화
                onMediaSelected: (file) {
                  // 단일 선택이므로 바로 처리
                },
              ),
            ),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 페이드인
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );

    if (!mounted || pickerResult == null || pickerResult.files.isEmpty) {
      return; // 취소하거나 선택하지 않은 경우
    }

    final selectedImageFile = pickerResult.files.first;

    // 2. 선택한 이미지와 함께 프로필 뷰 스크린으로 이동
    File? pickedCroppedFile;

    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => ProfileImageViewScreen(
              profileImageUrl: null,
              username: '',
              mode: ProfileImageMode.onboarding,
              // 선택한 이미지 파일을 초기 파일로 전달
              initialImageFile: selectedImageFile,
              onShareProfile: () {},
              onCopyProfileLink: () {},
              onGallerySelected: (file) {
                // ProfileImageViewScreen에서 "완료" 시 전달되는 원형 크롭 파일
                pickedCroppedFile = file;
              },
              onSetDefaultImage: () {},
              isOwnProfile: true,
            ),
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );

    if (!mounted || pickedCroppedFile == null) return;

    // 저장 완료: 바운싱 중지 + 미리보기 교체
    _animationController.stop();
    setState(() {
      _croppedProfileFile = pickedCroppedFile;
    });

    // 업로드 시작 (백그라운드)
    await _startProfileUpload(pickedCroppedFile!);
  }

  Future<void> _startProfileUpload(File croppedFile) async {
    try {
      setState(() {
        _isUploadingProfileImage = true;
      });

      final upload = context.read<UploadService>();
      final task = upload.enqueueFile(croppedFile, kind: UploadKind.profile);
      _profileUploadTask = task;

      _profileTaskListener = () async {
        if (!mounted) return;

        if (task.state == UploadState.success) {
          try {
            final imageUrl = task.url ?? '';
            if (imageUrl.isNotEmpty) {
              await context
                  .read<MyProfileFeedProvider>()
                  .updateProfileImageAfterUpload(imageUrl, context);
            } else {
              await context.read<UserProvider>().fetchMyProfile();
            }
          } catch (e) {
            debugPrint('[Index2Background] upload success handler error: $e');
          }

          if (_profileTaskListener != null) {
            task.removeListener(_profileTaskListener!);
            _profileTaskListener = null;
          }
          _profileUploadTask = null;

          if (mounted) {
            setState(() {
              _isUploadingProfileImage = false;
              _isUploadComplete = true; // ✅ 업로드 완료 표시
            });
          }
        } else if (task.state == UploadState.failed ||
            task.state == UploadState.cancelled) {
          if (_profileTaskListener != null) {
            task.removeListener(_profileTaskListener!);
            _profileTaskListener = null;
          }
          _profileUploadTask = null;

          if (mounted) {
            setState(() {
              _isUploadingProfileImage = false;
              _isUploadComplete = false;
            });
          }
        }
      };

      task.addListener(_profileTaskListener!);
    } catch (e) {
      debugPrint('[Index2Background] profile upload failed: $e');
      if (mounted) {
        setState(() {
          _isUploadingProfileImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // TODO(user): replace / customize
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RepaintBoundary(
          child: Column(
            children: [
              // 중앙 컨텐츠
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 안내 텍스트 (업로드 완료 시 "멋진데요?" 표시)
                          Text(
                            _isUploadComplete ? '멋진데요?' : '거의 다 됐어요, 프로필만 남았어요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.lightBackground,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 24),

                          AnimatedBuilder(
                            animation: _scaleAnimation,
                            builder: (context, child) {
                              final hasImage = _croppedProfileFile != null;
                              final scale =
                                  hasImage ? 1.0 : _scaleAnimation.value;

                              return GestureDetector(
                                onTap: _openProfileImageView,
                                child: Transform.scale(
                                  scale: scale,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 300,
                                        height: 300,
                                        decoration: BoxDecoration(
                                          color: AppColors.darkSurfaceVariant,
                                          borderRadius: BorderRadius.circular(
                                            300,
                                          ),
                                          border: Border.all(
                                            color: AppColors.lightBackground
                                                .withOpacity(0.7),
                                            width: 2,
                                          ),
                                        ),
                                        child:
                                            hasImage
                                                ? ClipOval(
                                                  child: Image.file(
                                                    _croppedProfileFile!,
                                                    fit: BoxFit.cover,
                                                  ),
                                                )
                                                : Center(
                                                  child: Icon(
                                                    Icons.add,
                                                    color: AppColors
                                                        .lightBackground
                                                        .withOpacity(0.3),
                                                    size: 100,
                                                  ),
                                                ),
                                      ),
                                      if (_isUploadingProfileImage)
                                        const Positioned(
                                          child: SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
