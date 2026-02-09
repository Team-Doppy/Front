import 'dart:io';
import 'package:doppy/pages/screens/onbording_mode_profile_view.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/theme/app_theme.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:flutter/cupertino.dart';

/// 프로필 설정 단계
class ProfileSettingStep extends StatefulWidget {
  final bool pauseAnimation; // ✅ 전환(드래그/스냅) 중 반복 애니메이션 일시정지
  final ValueChanged<bool>? onProfileImageUploaded; // ✅ 프로필 사진 업로드 완료 상태 콜백
  final VoidCallback? onConfirm; // ✅ 프로필 업로드 후 확인 버튼 콜백
  final VoidCallback? onBack; // ✅ 뒤로가기 버튼 콜백
  const ProfileSettingStep({
    super.key,
    this.pauseAnimation = false,
    this.onProfileImageUploaded,
    this.onConfirm,
    this.onBack,
  });

  @override
  State<ProfileSettingStep> createState() => _ProfileSettingStepState();
}

class _ProfileSettingStepState extends State<ProfileSettingStep>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late AnimationController _textAnimationController;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleOffset;
  File? _croppedProfileFile;
  bool _isUploadingProfileImage = false;
  bool _isUploadComplete = false; // ✅ 업로드 완료 여부
  UploadTask? _profileUploadTask;
  VoidCallback? _profileTaskListener;
  bool _wasAnimating = false; // pause 전 상태 기억
  bool _hasAutoNavigated = false; // ✅ 자동 네비게이션 여부 (중복 방지)

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

    // 텍스트 애니메이션 초기화
    _textAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textAnimationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _titleOffset = Tween<Offset>(
      begin: const Offset(0, 0.8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _textAnimationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    // 텍스트 애니메이션 시작
    _textAnimationController.forward();

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
            debugPrint('[ProfileSettingStep] upload success handler error: $e');
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
            // ✅ 프로필 사진 업로드 완료 상태 콜백 호출 (빌드 완료 후)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  widget.onProfileImageUploaded?.call(true);
                  // ✅ 업로드 완료 후 0.5초 후 자동으로 넘어가기
                  if (!_hasAutoNavigated && widget.onConfirm != null) {
                    _hasAutoNavigated = true;
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        widget.onConfirm?.call();
                      }
                    });
                  }
                }
              });
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
            // ✅ 프로필 사진 업로드 실패 상태 콜백 호출
            widget.onProfileImageUploaded?.call(_croppedProfileFile != null);
          }
        }
      };

      activeTask.addListener(_profileTaskListener!);
    } else if (completedTask != null) {
      // 이미 완료된 태스크
      _isUploadingProfileImage = false;
      _isUploadComplete = true;

      // ✅ 복원된 완료 태스크도 자동 네비게이션 처리
      if (mounted && !_hasAutoNavigated && widget.onConfirm != null) {
        _hasAutoNavigated = true;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            widget.onConfirm?.call();
          }
        });
      }
    }

    // 바운싱 애니메이션 중지 (이미지가 있으므로)
    _animationController.stop();

    if (mounted) {
      setState(() {});
      // ✅ 프로필 사진 업로드 완료 상태 콜백 호출 (복원 시      // build 중에 setState를 호출하지 않도록 addPostFrameCallback 사용
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onProfileImageUploaded?.call(
            _isUploadComplete || _croppedProfileFile != null,
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ProfileSettingStep oldWidget) {
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
    _textAnimationController.dispose();
    super.dispose();
  }

  /// 먼저 이미지 피커를 띄우고, 선택 후 프로필 뷰 스크린으로 이동
  Future<void> _openProfileImageView() async {
    if (_isUploadingProfileImage) return;

    void handleCroppedProfileFile(File file) {
      if (!mounted) return;
      // 저장 완료: 바운싱 중지 + 미리보기 교체
      _animationController.stop();
      setState(() {
        _croppedProfileFile = file;
      });
      // ✅ 프로필 사진 선택 상태 콜백 호출
      widget.onProfileImageUploaded?.call(true);
      // 업로드 시작 (백그라운드)
      _startProfileUpload(file);
    }

    // 1. 먼저 이미지 피커를 띄움 (다크 테마로 강제)
    await Navigator.push<void>(
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
                // ✅ "추가" 누르면 pop 없이 바로 onboarding ProfileImageView로 전환 (bg2 플래시 방지)
                onSubmitOverride: (pickerContext, result) async {
                  if (result.files.isEmpty) return null;
                  final selectedImageFile = result.files.first;
                  return Theme(
                    data: AppTheme.darkTheme,
                    child: OnbordingModeProfileImageViewScreen(
                      profileImageUrl: null,
                      username: '',
                      onGallerySelected: handleCroppedProfileFile,
                      initialImageFile: selectedImageFile, // ✅ 선택된 이미지 파일 전달
                    ),
                  );
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
            debugPrint('[ProfileSettingStep] upload success handler error: $e');
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
            // ✅ 프로필 사진 업로드 완료 상태 콜백 호출 (빌드 완료 후)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  widget.onProfileImageUploaded?.call(true);
                  // ✅ 업로드 완료 후 0.5초 후 자동으로 넘어가기
                  if (!_hasAutoNavigated && widget.onConfirm != null) {
                    _hasAutoNavigated = true;
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        widget.onConfirm?.call();
                      }
                    });
                  }
                }
              });
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
            // ✅ 프로필 사진 업로드 실패 상태 콜백 호출
            widget.onProfileImageUploaded?.call(_croppedProfileFile != null);
          }
        }
      };

      task.addListener(_profileTaskListener!);
    } catch (e) {
      debugPrint('[ProfileSettingStep] profile upload failed: $e');
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
          child: Stack(
            children: [
              // 뒤로가기 버튼
              if (widget.onBack != null)
                Positioned(
                  top: 8,
                  left: 12,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    onPressed: widget.onBack,
                  ),
                ),

              // 다음/건너뛰기 버튼 (위쪽 오른쪽)
              // 업로드 중이면 버튼 숨기기
              if (widget.onConfirm != null && !_isUploadingProfileImage)
                Positioned(
                  top: 8,
                  right: 8,
                  child: TextButton(
                    onPressed: widget.onConfirm,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      // 프로필이 설정되지 않았으면 "건너뛰기", 설정되었으면 "다음"
                      _croppedProfileFile == null ? '건너뛰기' : '다음',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ),
              // 중앙 컨텐츠
              Column(
                children: [
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
                              // 안내 텍스트 (업로드 완료 시 "멋진데요?" 표시) - 애니메이션
                              SlideTransition(
                                position: _titleOffset,
                                child: FadeTransition(
                                  opacity: _titleOpacity,
                                  child: Text(
                                    _isUploadComplete
                                        ? context.tr('onboarding_looks_great')
                                        : context.tr(
                                          'onboarding_almost_done_profile_left',
                                        ),
                                    textAlign: TextAlign.center,
                                    style: LocaleTypography.setStyle(
                                      context: context,
                                      fontSize: 20,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 52),

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
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.surfaceVariant,
                                              borderRadius:
                                                  BorderRadius.circular(300),
                                              border: Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.2),
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
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.2),
                                                        size: 100,
                                                      ),
                                                    ),
                                          ),
                                          if (_isUploadingProfileImage)
                                            const Positioned(
                                              child: SizedBox(
                                                width: 26,
                                                height: 26,
                                                child:
                                                    CircularProgressIndicator(
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

                              const SizedBox(height: 65),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
