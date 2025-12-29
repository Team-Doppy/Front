import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:doppy/image/crop_editor.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:provider/provider.dart';

/// 프로필 사진 전체 화면
class ProfileImageViewScreen extends StatefulWidget {
  final String? profileImageUrl;
  final String username;
  final VoidCallback onShareProfile;
  final VoidCallback onCopyProfileLink;
  final Function(File) onGallerySelected;
  final VoidCallback onSetDefaultImage;
  final bool isOwnProfile;
  final VoidCallback? onFollowStatusChanged; // 팔로우 상태 변경 시 콜백

  const ProfileImageViewScreen({
    Key? key,
    required this.profileImageUrl,
    required this.username,
    required this.onShareProfile,
    required this.onCopyProfileLink,
    required this.onGallerySelected,
    required this.onSetDefaultImage,
    required this.isOwnProfile,
    this.onFollowStatusChanged,
  }) : super(key: key);

  @override
  State<ProfileImageViewScreen> createState() => _ProfileImageViewScreenState();
}

class _ProfileImageViewScreenState extends State<ProfileImageViewScreen>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;

  // 이미지 선택 관련
  File? _selectedImage;
  ui.Image? _uiImage;
  bool _isDefaultImageMode = false; // 기본이미지 모드

  // 스와이프 제스처 관련
  double _dragStartY = 0.0;
  double _dragStartX = 0.0;
  double _currentDragY = 0.0;
  double _currentDragX = 0.0;
  Offset _dragOffset = Offset.zero;
  late final AnimationController _dragResetController;
  late final Animation<double> _dragResetCurve;
  Offset _dragResetBegin = Offset.zero;

  // 인라인 보정 모드
  bool _isAdjustMode = false;
  _AdjustTool _activeAdjustTool = _AdjustTool.brightness;
  double _brightness = 0.0; // -100 ~ 100
  double _contrast = 0.0; // -100 ~ 100
  double _saturation = 0.0; // -100 ~ 100
  double _warmth = 0.0; // -100 ~ 100
  _AdjustSnapshot? _adjustSnapshot;

  // 이미지 상태 (crop_editor.dart 구조 참고)
  double _imageScale = 1.0;
  Offset _imageOffset = Offset.zero;
  double _minScale = 1.0; // 원형 크롭박스를 덮는 최소 스케일
  double? _initialScale; // 핀치 시작 시 초기 scale
  double _imageRotation = 0.0; // ✅ 두 손 회전(라디안)
  double? _initialRotation; // 핀치 시작 시 초기 rotation
  Offset? _lastPanPosition;

  // 원형 크롭박스 크기 (고정)
  static const double _cropSize = 350.0;

  @override
  void initState() {
    super.initState();
    _dragResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _dragResetCurve = CurvedAnimation(
      parent: _dragResetController,
      curve: Curves.easeOutCubic,
    );
    _dragResetController.addListener(() {
      if (!mounted) return;
      setState(() {
        _dragOffset =
            Offset.lerp(_dragResetBegin, Offset.zero, _dragResetCurve.value) ??
            Offset.zero;
      });
    });
  }

  @override
  void dispose() {
    _dragResetController.dispose();
    super.dispose();
  }

  void _animateDragBack() {
    _dragResetBegin = _dragOffset;
    _dragResetController.stop();
    _dragResetController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ✅ 이미지 편집(추가/크롭/이동) 중에는 스와이프-닫기 제스처를 막아야 편집 제스처와 충돌하지 않음
    final bool canSwipeDismiss = _selectedImage == null && !_isAdjustMode;
    // 기본이미지 모드일 때는 프로필 이미지를 표시하지 않음
    final hasProfileImage =
        !_isDefaultImageMode &&
        widget.profileImageUrl != null &&
        widget.profileImageUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: GestureDetector(
        onVerticalDragStart:
            !canSwipeDismiss
                ? null
                : (details) {
                  _dragStartY = details.globalPosition.dy;
                  _currentDragY = 0.0;
                  _dragOffset = Offset.zero;
                  _dragResetController.stop();
                },
        onVerticalDragUpdate:
            !canSwipeDismiss
                ? null
                : (details) {
                  _currentDragY = details.globalPosition.dy - _dragStartY;
                  // 아래로 스와이프만 감지 (위로는 무시)
                  if (_currentDragY > 0) {
                    setState(() {
                      _dragOffset = Offset(0, _currentDragY);
                    });
                  }
                },
        onVerticalDragEnd:
            !canSwipeDismiss
                ? null
                : (details) {
                  // 아래로 100픽셀 이상 스와이프하면 닫기
                  if (_currentDragY > 100) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      _currentDragY = 0.0;
                    });
                    _animateDragBack();
                  }
                },
        onHorizontalDragStart:
            !canSwipeDismiss
                ? null
                : (details) {
                  _dragStartX = details.globalPosition.dx;
                  _currentDragX = 0.0;
                  _dragOffset = Offset.zero;
                  _dragResetController.stop();
                },
        onHorizontalDragUpdate:
            !canSwipeDismiss
                ? null
                : (details) {
                  _currentDragX = details.globalPosition.dx - _dragStartX;
                  setState(() {
                    _dragOffset = Offset(_currentDragX, 0);
                  });
                },
        onHorizontalDragEnd:
            !canSwipeDismiss
                ? null
                : (details) {
                  // 좌/우 100픽셀 이상 스와이프하면 닫기
                  if (_currentDragX.abs() > 100) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      _currentDragX = 0.0;
                    });
                    _animateDragBack();
                  }
                },
        child: Stack(
          children: [
            // 중앙 프로필 이미지 (Hero 애니메이션) - 위쪽으로 약간 이동
            Align(
              alignment: const Alignment(
                0,
                -0.25,
              ), // 위로 약간 이동 (0 = 중앙, -1 = 최상단)
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ✅ Hero는 고정 레이아웃(앵커)만 잡고, Transform은 Hero 바깥에서 적용
                  //    드래그 피드백은 유지하되 Hero 전환 시 깜빡임은 방지
                  if (_selectedImage == null)
                    Transform.translate(
                      offset:
                          canSwipeDismiss
                              ? Offset(
                                (_dragOffset.dx * 0.18).clamp(-40.0, 40.0),
                                (_dragOffset.dy * 0.18).clamp(-40.0, 40.0),
                              )
                              : Offset.zero,
                      child: Hero(
                        tag: 'profile_image_${widget.username}',
                        createRectTween:
                            (begin, end) => RectTween(begin: begin, end: end),
                        flightShuttleBuilder: (
                          flightContext,
                          animation,
                          flightDirection,
                          fromHeroContext,
                          toHeroContext,
                        ) {
                          // ✅ 비행 중에는 "출발/도착 Hero의 child"를 그대로 재사용해야
                          //    CachedNetworkImage placeholder ↔ image 스왑으로 인한 시작 깜빡임이 줄어듭니다.
                          final fromHero =
                              fromHeroContext.widget is Hero
                                  ? (fromHeroContext.widget as Hero).child
                                  : fromHeroContext.widget;
                          final toHero =
                              toHeroContext.widget is Hero
                                  ? (toHeroContext.widget as Hero).child
                                  : toHeroContext.widget;

                          final stableChild =
                              flightDirection == HeroFlightDirection.push
                                  ? fromHero
                                  : toHero;

                          return SizedBox(
                            width: _cropSize,
                            height: _cropSize,
                            child: Material(
                              color: Colors.transparent,
                              child: stableChild,
                            ),
                          );
                        },
                        child: SizedBox(
                          width: _cropSize,
                          height: _cropSize,
                          // ✅ 이미지 URL이 바뀔 때 위젯을 완전히 재생성하여 잔상 방지
                          key: ValueKey(
                            'hero_avatar_${widget.profileImageUrl}',
                          ),
                          child: _buildHeroAvatar(
                            enableTransform: false, // Hero 내부는 정적
                            dragOffset: Offset.zero, // Transform은 외부에서 처리
                          ),
                        ),
                      ),
                    ),

                  // 선택된 이미지가 있을 때 표시
                  if (_selectedImage != null &&
                      _uiImage != null &&
                      widget.isOwnProfile)
                    _buildImageEditor(theme),
                ],
              ),
            ),

            // 상단 뒤로가기 버튼
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.arrow_back,
                        color: theme.colorScheme.onSurface,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 하단 버튼들
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 40.0,
                    left: 24.0,
                    right: 24.0,
                  ),
                  child:
                      widget.isOwnProfile
                          ? _selectedImage != null
                              ? (_isAdjustMode
                                  ? _buildAdjustBottomSheet(theme)
                                  : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildCircleButton(
                                        context: context,
                                        icon: Icons.check,
                                        label: AppLocalizations.of(
                                          context,
                                        ).translate('complete'),
                                        onTap: () async {
                                          if (_selectedImage != null &&
                                              _uiImage != null) {
                                            final croppedFile =
                                                await _cropImageToCircle();
                                            if (croppedFile != null &&
                                                mounted) {
                                              widget.onGallerySelected(
                                                croppedFile,
                                              );
                                              Navigator.pop(context);
                                            }
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 16),
                                      _buildCircleButton(
                                        context: context,
                                        icon: Icons.tune,
                                        label: AppLocalizations.of(
                                          context,
                                        ).translate('adjust'),
                                        onTap: _enterAdjustMode,
                                      ),
                                      const SizedBox(width: 16),
                                      _buildCircleButton(
                                        context: context,
                                        icon: Icons.close,
                                        label: AppLocalizations.of(
                                          context,
                                        ).translate('cancel'),
                                        onTap: () {
                                          setState(() {
                                            _selectedImage = null;
                                            _uiImage = null;
                                            _imageScale = 1.0;
                                            _imageOffset = Offset.zero;
                                            _minScale = 1.0;
                                            _initialScale = null;
                                            _lastPanPosition = null;
                                            _isAdjustMode = false;
                                            _adjustSnapshot = null;
                                          });
                                        },
                                      ),
                                    ],
                                  ))
                              : _isDefaultImageMode
                              ? // 기본이미지 모드: 확인, 취소 버튼 표시
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildCircleButton(
                                    context: context,
                                    icon: Icons.check,
                                    label: AppLocalizations.of(
                                      context,
                                    ).translate('confirm'),
                                    onTap: () {
                                      widget.onSetDefaultImage();
                                      Navigator.pop(context);
                                    },
                                  ),
                                  const SizedBox(width: 16),
                                  _buildCircleButton(
                                    context: context,
                                    icon: Icons.close,
                                    label: AppLocalizations.of(
                                      context,
                                    ).translate('cancel'),
                                    onTap: () {
                                      setState(() {
                                        _isDefaultImageMode = false;
                                      });
                                    },
                                  ),
                                ],
                              )
                              : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  // 공유하기 버튼
                                  _buildCircleButton(
                                    context: context,
                                    icon: Icons.ios_share,
                                    label: AppLocalizations.of(
                                      context,
                                    ).translate('share'),
                                    onTap: widget.onShareProfile,
                                  ),

                                  // 갤러리선택 버튼
                                  _buildCircleButton(
                                    context: context,
                                    icon: Icons.photo_library,
                                    label: AppLocalizations.of(
                                      context,
                                    ).translate('select_from_gallery'),
                                    onTap: () {
                                      _showMediaPicker();
                                    },
                                  ),

                                  // 기본이미지 버튼
                                  _buildCircleButton(
                                    context: context,
                                    icon: Icons.person,
                                    label: AppLocalizations.of(
                                      context,
                                    ).translate('change_to_default'),
                                    onTap: () {
                                      // 기본이미지 모드로 전환 (확인/취소 버튼 표시)
                                      setState(() {
                                        _isDefaultImageMode = true;
                                        _selectedImage = null;
                                        _uiImage = null;
                                        _isAdjustMode = false;
                                        _adjustSnapshot = null;
                                      });
                                    },
                                  ),
                                ],
                              )
                          : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // 팔로우/팔로잉 버튼
                              Consumer<FriendProvider>(
                                builder: (context, friendProvider, _) {
                                  final isFollowing =
                                      friendProvider.friendStatus ==
                                      FriendRequestStatus.accepted;
                                  final isRequested =
                                      friendProvider.friendStatus ==
                                      FriendRequestStatus.requested;

                                  return _buildCircleButton(
                                    context: context,
                                    icon:
                                        isFollowing
                                            ? Icons.check_circle
                                            : Icons.person_add,
                                    label:
                                        isFollowing
                                            ? AppLocalizations.of(
                                              context,
                                            ).translate('following')
                                            : isRequested
                                            ? AppLocalizations.of(
                                              context,
                                            ).translate('request_sent')
                                            : AppLocalizations.of(
                                              context,
                                            ).translate('follow'),
                                    onTap: () async {
                                      if (isFollowing) {
                                        // 팔로우 해제
                                        await _unfollow(context);
                                      } else if (isRequested) {
                                        // 요청 취소
                                        await _cancelRequest(context);
                                      } else {
                                        // 팔로우 요청 보내기
                                        await _follow(context);
                                      }
                                    },
                                  );
                                },
                              ),

                              // 공유하기 버튼
                              _buildCircleButton(
                                context: context,
                                icon: Icons.ios_share,
                                label: AppLocalizations.of(
                                  context,
                                ).translate('share'),
                                onTap: widget.onShareProfile,
                              ),

                              // 다운로드 버튼
                              hasProfileImage
                                  ? _buildCircleButton(
                                    context: context,
                                    icon:
                                        _isDownloading
                                            ? Icons.downloading
                                            : Icons.download,
                                    label: AppLocalizations.of(
                                      context,
                                    ).translate('download'),
                                    onTap: () => _downloadImage(context),
                                  )
                                  : const SizedBox(),
                            ],
                          ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroAvatar({
    required bool enableTransform,
    required Offset dragOffset,
  }) {
    final theme = Theme.of(context);
    final bool hasProfileImage =
        !_isDefaultImageMode &&
        widget.profileImageUrl != null &&
        widget.profileImageUrl!.isNotEmpty;

    // UserProfileScreen과 동일한 보더 스타일 적용
    final borderColor =
        theme.brightness == Brightness.dark
            ? Colors.grey.shade500
            : Colors.grey.shade400;

    return Material(
      color: Colors.transparent,
      // ✅ Hero child는 Transform/placeholder 애니메이션과 독립적인 "정적" 위젯이어야
      //    비행 시작/종료 시 튐/깜빡임이 줄어듭니다.
      child: StaticProfileAvatar(
        key: ValueKey(
          'static_avatar_${widget.profileImageUrl}_${widget.username}',
        ), // ✅ 이미지 URL이 바뀔 때 완전히 재생성하여 잔상 방지
        imageUrl: hasProfileImage ? widget.profileImageUrl : null,
        username: widget.username,
        size: _cropSize,
        borderWidth: 3.0,
        borderColor: borderColor,
        backgroundColor: theme.colorScheme.surfaceVariant,
      ),
    );
  }

  Widget _buildCircleButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: theme.colorScheme.surface, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _follow(BuildContext context) async {
    final friendProvider = context.read<FriendProvider>();
    try {
      final success = await friendProvider.sendFriendRequest(widget.username);
      if (success && widget.onFollowStatusChanged != null) {
        widget.onFollowStatusChanged!();
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showError(
          context,
          AppLocalizations.of(context).translate('friend_request_failed'),
        );
      }
    }
  }

  Future<void> _unfollow(BuildContext context) async {
    final friendProvider = context.read<FriendProvider>();
    try {
      await friendProvider.deleteFriend(widget.username);
      if (widget.onFollowStatusChanged != null) {
        widget.onFollowStatusChanged!();
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showError(
          context,
          AppLocalizations.of(context).translate('unfriend_failed'),
        );
      }
    }
  }

  Future<void> _cancelRequest(BuildContext context) async {
    final friendProvider = context.read<FriendProvider>();
    try {
      final success = await friendProvider.cancelSentRequestOptimistic(
        widget.username,
      );
      if (success && widget.onFollowStatusChanged != null) {
        widget.onFollowStatusChanged!();
      } else if (!success && context.mounted) {
        ErrorHandler.showError(
          context,
          AppLocalizations.of(context).translate('cancel_request_failed'),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showError(
          context,
          AppLocalizations.of(context).translate('cancel_request_failed'),
        );
      }
    }
  }

  Future<void> _downloadImage(BuildContext context) async {
    if (_isDownloading ||
        widget.profileImageUrl == null ||
        widget.profileImageUrl!.isEmpty) {
      return;
    }

    setState(() => _isDownloading = true);

    try {
      final response = await http.get(Uri.parse(widget.profileImageUrl!));

      if (response.statusCode == 200) {
        final result = await ImageGallerySaver.saveImage(
          response.bodyBytes,
          quality: 100,
          name:
              'doppy_profile_${widget.username}_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (mounted) {
          setState(() => _isDownloading = false);

          if (result != null && result['isSuccess'] == true) {
            ErrorHandler.showInfo(
              context,
              AppLocalizations.of(context).translate('image_saved'),
            );
          } else {
            ErrorHandler.showError(
              context,
              AppLocalizations.of(context).translate('image_save_failed'),
            );
          }
        }
      } else {
        if (mounted) {
          setState(() => _isDownloading = false);
          ErrorHandler.showError(
            context,
            AppLocalizations.of(context).translate('image_download_failed'),
          );
        }
      }
    } catch (e) {
      debugPrint('[ProfileImageView] 다운로드 실패: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ErrorHandler.showError(
          context,
          AppLocalizations.of(context).translate('image_save_failed'),
        );
      }
    }
  }

  /// 미디어 피커 표시
  Future<void> _showMediaPicker() async {
    final result = await Navigator.push<MediaPickerResult>(
      context,
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder:
            (context) => MediaPickerScreen(
              initialMediaType: MediaType.image,
              maxSelectionCount: 1,
              enableToggle: false, // 영상 토글 비활성화
              onMediaSelected: (file) {
                // 단일 선택이므로 바로 처리하지 않음 (Navigator.pop의 result로 처리)
              },
            ),
      ),
    );

    if (result != null && result.files.isNotEmpty && mounted) {
      final file = result.files.first;
      // 이미지 로드
      _loadImageAndCalculateScale(file);
    }
  }

  void _enterAdjustMode() {
    if (_selectedImage == null) return;
    setState(() {
      _adjustSnapshot = _AdjustSnapshot(
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        warmth: _warmth,
      );
      _isAdjustMode = true;
      _activeAdjustTool = _AdjustTool.brightness;
    });
  }

  void _exitAdjustMode({required bool apply}) {
    if (!apply) {
      final snap = _adjustSnapshot;
      if (snap != null) {
        _brightness = snap.brightness;
        _contrast = snap.contrast;
        _saturation = snap.saturation;
        _warmth = snap.warmth;
      }
    }
    setState(() {
      _isAdjustMode = false;
      _adjustSnapshot = null;
    });
  }

  Widget _buildAdjustBottomSheet(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () => _exitAdjustMode(apply: false),
                child: Text(
                  AppLocalizations.of(context).translate('cancel'),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _exitAdjustMode(apply: true),
                child: Text(
                  AppLocalizations.of(context).translate('complete'),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildAdjustToolButton(
                  theme: theme,
                  tool: _AdjustTool.brightness,
                  icon: Icons.brightness_6,
                  label: AppLocalizations.of(context).translate('brightness'),
                ),
                _buildAdjustToolButton(
                  theme: theme,
                  tool: _AdjustTool.contrast,
                  icon: Icons.contrast,
                  label: AppLocalizations.of(context).translate('contrast'),
                ),
                _buildAdjustToolButton(
                  theme: theme,
                  tool: _AdjustTool.saturation,
                  icon: Icons.palette,
                  label: AppLocalizations.of(context).translate('saturation'),
                ),
                _buildAdjustToolButton(
                  theme: theme,
                  tool: _AdjustTool.warmth,
                  icon: Icons.thermostat,
                  label: AppLocalizations.of(context).translate('warmth'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildAdjustSlider(theme),
        ],
      ),
    );
  }

  Widget _buildAdjustToolButton({
    required ThemeData theme,
    required _AdjustTool tool,
    required IconData icon,
    required String label,
  }) {
    final selected = _activeAdjustTool == tool;
    return GestureDetector(
      onTap: () => setState(() => _activeAdjustTool = tool),
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected
                  ? theme.colorScheme.primary.withOpacity(0.12)
                  : theme.colorScheme.surfaceVariant.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                selected
                    ? theme.colorScheme.primary.withOpacity(0.6)
                    : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:
                    selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustSlider(ThemeData theme) {
    double value;
    String label;
    switch (_activeAdjustTool) {
      case _AdjustTool.brightness:
        value = _brightness;
        label = AppLocalizations.of(context).translate('brightness');
        break;
      case _AdjustTool.contrast:
        value = _contrast;
        label = AppLocalizations.of(context).translate('contrast');
        break;
      case _AdjustTool.saturation:
        value = _saturation;
        label = AppLocalizations.of(context).translate('saturation');
        break;
      case _AdjustTool.warmth:
        value = _warmth;
        label = AppLocalizations.of(context).translate('warmth');
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              value.toStringAsFixed(0),
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: -100,
          max: 100,
          onChanged: (v) {
            setState(() {
              switch (_activeAdjustTool) {
                case _AdjustTool.brightness:
                  _brightness = v;
                  break;
                case _AdjustTool.contrast:
                  _contrast = v;
                  break;
                case _AdjustTool.saturation:
                  _saturation = v;
                  break;
                case _AdjustTool.warmth:
                  _warmth = v;
                  break;
              }
            });
          },
        ),
      ],
    );
  }

  /// 이미지 로드 및 초기 스케일 계산
  Future<void> _loadImageAndCalculateScale(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final imageSize = Size(img.width.toDouble(), img.height.toDouble());
      final containerSize = Size(_cropSize, _cropSize);

      // 원형을 완전히 덮는 최소 스케일 계산
      final imageRect = ImageRectUtils.computeImageRect(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: 1.0,
        offset: Offset.zero,
      );

      // 원형 크롭박스를 완전히 덮는 최소 스케일
      final minScale =
          math.max(_cropSize / imageRect.width, _cropSize / imageRect.height) *
          1.01; // 약간의 여유

      setState(() {
        _selectedImage = file;
        _uiImage = img;
        _minScale = minScale;
        _imageScale = minScale;
        _imageOffset = Offset.zero;
        _imageRotation = 0.0;
        _initialScale = null;
        _initialRotation = null;
        _lastPanPosition = null;
      });
    } catch (e) {
      debugPrint('[ProfileImageView] 이미지 로드 실패: $e');
      if (mounted) {
        setState(() {
          _selectedImage = file;
          _minScale = 1.0;
          _imageScale = 1.0;
          _imageOffset = Offset.zero;
          _imageRotation = 0.0;
          _initialScale = null;
          _initialRotation = null;
          _lastPanPosition = null;
        });
      }
    }
  }

  /// 이미지 에디터 빌드 (단일 CustomPainter로 통합)
  Widget _buildImageEditor(ThemeData theme) {
    if (_uiImage == null) return const SizedBox.shrink();

    final imageSize = Size(
      _uiImage!.width.toDouble(),
      _uiImage!.height.toDouble(),
    );
    final containerSize = Size(_cropSize, _cropSize);

    // ImageRectUtils로 이미지 rect 계산 (컨테이너 기준)
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: _imageScale,
      offset: _imageOffset,
    );

    // 화면 중앙에 위치한 크롭 영역의 화면 좌표
    final screenSize = MediaQuery.of(context).size;
    final cropCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final cropRect = Rect.fromCenter(
      center: cropCenter,
      width: _cropSize,
      height: _cropSize,
    );

    // imageRect를 화면 좌표계로 변환 (컨테이너가 화면 중앙에 위치)
    final screenImageRect = Rect.fromLTWH(
      cropCenter.dx - containerSize.width / 2 + imageRect.left,
      cropCenter.dy - containerSize.height / 2 + imageRect.top,
      imageRect.width,
      imageRect.height,
    );

    return GestureDetector(
      onScaleStart: (details) {
        _initialScale = _imageScale;
        _initialRotation = _imageRotation;
        _lastPanPosition = details.focalPoint;
      },
      onScaleUpdate: (details) {
        if (_uiImage == null) return;

        final startScale = _initialScale ?? _imageScale;
        final startRotation = _initialRotation ?? _imageRotation;

        final newScale = (startScale * details.scale).clamp(_minScale, 5.0);
        final newRotation = startRotation + details.rotation;

        // scale 변경 시 offset을 중심 기준으로 비례 보정
        final scaleRatio = (newScale / _imageScale);
        Offset newOffset = _imageOffset * scaleRatio;

        // 드래그 처리 (scale/rotation과 함께 동시 적용)
        if (_lastPanPosition != null) {
          final delta = details.focalPoint - _lastPanPosition!;

          // 드래그 감도 조정: 기본 감도 + 스케일에 비례한 감도 증가
          final baseSensitivity = 1.5;
          final scaleMultiplier = (newScale / _minScale).clamp(1.0, 5.0);
          final dragSensitivity = baseSensitivity * scaleMultiplier;

          newOffset =
              newOffset +
              Offset(
                delta.dx / newScale * dragSensitivity,
                delta.dy / newScale * dragSensitivity,
              );
          _lastPanPosition = details.focalPoint;
        }

        // ✅ 회전까지 고려해서 원형 크롭을 항상 덮도록 clamp
        newOffset = _clampOffsetWithRotation(
          offset: newOffset,
          scale: newScale,
          rotation: newRotation,
          imageSize: imageSize,
          containerSize: containerSize,
        );

        setState(() {
          _imageScale = newScale;
          _imageRotation = newRotation;
          _imageOffset = newOffset;
        });
      },
      onScaleEnd: (_) {
        setState(() {
          _lastPanPosition = null;
          _initialScale = null;
          _initialRotation = null;
          // 최종 clamp
          if (_uiImage != null) {
            _imageOffset = _clampOffsetWithRotation(
              offset: _imageOffset,
              scale: _imageScale,
              rotation: _imageRotation,
              imageSize: Size(
                _uiImage!.width.toDouble(),
                _uiImage!.height.toDouble(),
              ),
              containerSize: Size(_cropSize, _cropSize),
            );
          }
        });
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _UnifiedImagePainter(
          image: _uiImage!,
          screenImageRect: screenImageRect,
          cropRect: cropRect,
          borderColor: theme.colorScheme.onSurface.withOpacity(0.3),
          adjustmentFilter: _buildAdjustmentColorFilter(),
          rotation: _imageRotation,
        ),
      ),
    );
  }

  /// ✅ 이동 한계 계산 (회전 포함)
  /// - 회전은 "크롭 원 중심"을 기준으로 적용되므로, 크롭 원 위의 점들을 역회전시킨 뒤
  ///   axis-aligned 이미지 rect 안에 들어오도록 오프셋을 보정한다.
  Offset _clampOffsetWithRotation({
    required Offset offset,
    required double scale,
    required double rotation,
    required Size imageSize,
    required Size containerSize,
  }) {
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: scale,
      offset: offset,
    );

    final center = Offset(containerSize.width / 2, containerSize.height / 2);
    final radius = _cropSize / 2;

    // 원형 크롭 경계의 샘플 포인트들을 "역회전"하여 이미지 rect가 커버해야 하는 범위 계산
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    const sampleCount = 16;
    for (int i = 0; i < sampleCount; i++) {
      final a = (2 * math.pi) * (i / sampleCount);
      final p = center + Offset(math.cos(a) * radius, math.sin(a) * radius);
      final pr = _rotateAround(p, center, -rotation);
      minX = math.min(minX, pr.dx);
      maxX = math.max(maxX, pr.dx);
      minY = math.min(minY, pr.dy);
      maxY = math.max(maxY, pr.dy);
    }

    double dx = 0.0;
    double dy = 0.0;

    if (imageRect.left > minX) {
      dx -= (imageRect.left - minX);
    }
    if (imageRect.right < maxX) {
      dx += (maxX - imageRect.right);
    }
    if (imageRect.top > minY) {
      dy -= (imageRect.top - minY);
    }
    if (imageRect.bottom < maxY) {
      dy += (maxY - imageRect.bottom);
    }

    return offset + Offset(dx, dy);
  }

  Offset _rotateAround(Offset p, Offset center, double angle) {
    final v = p - center;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c) + center;
  }

  /// 원형 크롭된 이미지 생성
  Future<File?> _cropImageToCircle() async {
    if (_uiImage == null || _selectedImage == null) return null;

    try {
      final imageSize = Size(
        _uiImage!.width.toDouble(),
        _uiImage!.height.toDouble(),
      );
      final containerSize = const Size(_cropSize, _cropSize);
      // ✅ export는 DPR을 반영해 더 높은 해상도로 렌더링(아바타에서 색 점/aliasing 완화)
      final dpr = MediaQuery.of(context).devicePixelRatio;

      // ✅ 화면에서 보던 것과 동일한 방식으로 렌더링해서 결과에도 회전/이동/확대/보정 반영
      final imageRect = ImageRectUtils.computeImageRect(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: _imageScale,
        offset: _imageOffset,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = containerSize;

      // 고해상도 렌더링(좌표계는 그대로 두고 캔버스만 스케일)
      canvas.scale(dpr, dpr);

      // 원형 클립
      // ✅ fringing 완화: 경계 1px(물리 픽셀) 안쪽으로 살짝 줄여 알파 경계 색 번짐을 덜 보이게 함
      final inset = 1.0 / dpr;
      final clipPath =
          Path()..addOval(
            Rect.fromLTWH(
              inset,
              inset,
              size.width - inset * 2,
              size.height - inset * 2,
            ),
          );
      canvas.clipPath(clipPath);

      final center = Offset(size.width / 2, size.height / 2);
      final srcRect = Rect.fromLTWH(
        0,
        0,
        _uiImage!.width.toDouble(),
        _uiImage!.height.toDouble(),
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(_imageRotation);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawImageRect(
        _uiImage!,
        srcRect,
        imageRect,
        Paint()
          ..isAntiAlias = true
          // ✅ fringing 완화: export에서는 high → medium (미리보기 품질은 유지)
          ..filterQuality = FilterQuality.medium
          ..colorFilter = _buildAdjustmentColorFilter(),
      );
      canvas.restore();

      // Picture를 Image로 변환
      final picture = recorder.endRecording();
      final outW = (size.width * dpr).round();
      final outH = (size.height * dpr).round();
      final image = await picture.toImage(outW, outH);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // 임시 파일로 저장
      final tempDir = await Directory.systemTemp.createTemp('profile_crop_');
      final tempFile = File(
        '${tempDir.path}/cropped_profile_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(pngBytes);
      debugPrint(
        '[ProfileImageView] crop export: logical=${size.width.toInt()}x${size.height.toInt()} '
        'dpr=${dpr.toStringAsFixed(2)} '
        'out=${outW}x${outH} bytes=${pngBytes.length} path=${tempFile.path}',
      );

      // 임시 디렉토리 정리 (파일은 유지)
      try {
        await tempDir.delete(recursive: false);
      } catch (_) {}

      return tempFile;
    } catch (e) {
      debugPrint('[ProfileImageView] 원형 크롭 실패: $e');
      return null;
    }
  }
}

/// 통합 이미지 Painter (배경 + 원형 클립을 같은 좌표계에서 처리)
class _UnifiedImagePainter extends CustomPainter {
  final ui.Image image;
  final Rect screenImageRect; // 화면 좌표계의 이미지 rect
  final Rect cropRect; // 화면 좌표계의 크롭 영역
  final Color borderColor;
  final ColorFilter? adjustmentFilter;
  final double rotation;

  _UnifiedImagePainter({
    required this.image,
    required this.screenImageRect,
    required this.cropRect,
    required this.borderColor,
    this.adjustmentFilter,
    this.rotation = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final center = cropRect.center;

    // 1. 배경: 원형 영역 밖에 반투명 이미지 그리기
    // 원형 영역을 제외한 나머지 영역에만 그리기
    final backgroundPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high
          ..colorFilter = adjustmentFilter;

    // 원형 영역을 제외한 경로 생성
    final backgroundPath =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addOval(cropRect)
          ..fillType = PathFillType.evenOdd;

    canvas.save();
    canvas.clipPath(backgroundPath);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawImageRect(image, srcRect, screenImageRect, backgroundPaint);
    canvas.restore();
    canvas.restore();

    // 2. 중앙: 원형 클립된 이미지 그리기
    canvas.save();
    // 원형 클립 경로
    final cropPath = Path()..addOval(cropRect);
    canvas.clipPath(cropPath);
    // 원형 영역 내부에 이미지 그리기 (회전 포함)
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawImageRect(
      image,
      srcRect,
      screenImageRect,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..colorFilter = adjustmentFilter,
    );
    canvas.restore();

    // 3. 원형 테두리 그리기
    final borderPaint =
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
    canvas.drawOval(cropRect, borderPaint);
  }

  @override
  bool shouldRepaint(_UnifiedImagePainter oldDelegate) {
    return oldDelegate.screenImageRect != screenImageRect ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.image != image ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.adjustmentFilter != adjustmentFilter ||
        oldDelegate.rotation != rotation;
  }
}

enum _AdjustTool { brightness, contrast, saturation, warmth }

class _AdjustSnapshot {
  const _AdjustSnapshot({
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.warmth,
  });
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
}

extension on _ProfileImageViewScreenState {
  ColorFilter? _buildAdjustmentColorFilter() {
    if (_brightness == 0.0 &&
        _contrast == 0.0 &&
        _saturation == 0.0 &&
        _warmth == 0.0) {
      return null;
    }

    final b = _brightness / 100.0; // -1..1
    final c = 1.0 + (_contrast / 100.0); // 0..2
    final s = 1.0 + (_saturation / 100.0); // 0..2
    final w = _warmth / 100.0; // -1..1

    // contrast around 128 + brightness
    final t = (1.0 - c) * 128.0 + (b * 255.0);

    // saturation
    const lumR = 0.299;
    const lumG = 0.587;
    const lumB = 0.114;
    final sr = (1.0 - s) * lumR;
    final sg = (1.0 - s) * lumG;
    final sb = (1.0 - s) * lumB;

    // warmth: red up / blue down (간단 근사)
    final warmR = 30.0 * w;
    final warmB = -30.0 * w;

    final m = <double>[
      c * (sr + s),
      c * sg,
      c * sb,
      0,
      t + warmR,
      c * sr,
      c * (sg + s),
      c * sb,
      0,
      t,
      c * sr,
      c * sg,
      c * (sb + s),
      0,
      t + warmB,
      0,
      0,
      0,
      1,
      0,
    ];

    return ColorFilter.matrix(m);
  }
}
