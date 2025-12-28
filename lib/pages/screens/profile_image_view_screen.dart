import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/image/crop_editor.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
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

class _ProfileImageViewScreenState extends State<ProfileImageViewScreen> {
  bool _isDownloading = false;

  // 이미지 선택 관련
  File? _selectedImage;
  ui.Image? _uiImage;
  bool _isDefaultImageMode = false; // 기본이미지 모드

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
  Offset? _lastPanPosition;

  // 원형 크롭박스 크기 (고정)
  static const double _cropSize = 350.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 기본이미지 모드일 때는 프로필 이미지를 표시하지 않음
    final hasProfileImage =
        !_isDefaultImageMode &&
        widget.profileImageUrl != null &&
        widget.profileImageUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          // 중앙 프로필 이미지 (Hero 애니메이션)
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 프로필 이미지 (원형) - Hero 위젯으로 감싸기 (선택된 이미지가 없을 때만 표시)
                // 기본이미지 모드일 때는 프로필 이미지 URL을 null로 처리하여 플레이스홀더 표시
                if (_selectedImage == null)
                  Hero(
                    tag: 'profile_image_${widget.username}',
                    createRectTween: (begin, end) {
                      // 직선 경로 생성 (수직 이동만, X는 시작 위치의 중앙 기준으로 유지)
                      if (begin == null || end == null) {
                        return RectTween(begin: begin, end: end);
                      }

                      // 시작 위치의 중앙 X 좌표 유지
                      final startCenterX = begin.left + begin.width / 2;

                      return RectTween(
                        begin: begin,
                        end: Rect.fromLTWH(
                          startCenterX - end.width / 2, // 중앙 정렬을 위해 width 절반 빼기
                          end.top,
                          end.width,
                          end.height,
                        ),
                      );
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: 350,
                        height: 350,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surfaceVariant,
                        ),
                        child: ClipOval(
                          child:
                              hasProfileImage
                                  ? CachedNetworkImage(
                                    imageUrl: widget.profileImageUrl!,
                                    fit: BoxFit.cover,
                                    placeholder:
                                        (context, url) => Container(
                                          color:
                                              theme.colorScheme.surfaceVariant,
                                          child: Center(
                                            child: Text(
                                              widget.username.isNotEmpty
                                                  ? widget.username[0]
                                                      .toUpperCase()
                                                  : '',
                                              style: TextStyle(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.3),
                                                fontSize: 100,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                    errorWidget:
                                        (context, url, error) =>
                                            _buildPlaceholder(),
                                  )
                                  : _buildPlaceholder(),
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

          // 상단 취소 버튼
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      AppLocalizations.of(context).translate('cancel'),
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                      ),
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
                                      label: '완료',
                                      onTap: () async {
                                        if (_selectedImage != null &&
                                            _uiImage != null) {
                                          final croppedFile =
                                              await _cropImageToCircle();
                                          if (croppedFile != null && mounted) {
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
                                      label: '보정',
                                      onTap: _enterAdjustMode,
                                    ),
                                    const SizedBox(width: 16),
                                    _buildCircleButton(
                                      context: context,
                                      icon: Icons.close,
                                      label: '취소',
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
                                  label: '확인',
                                  onTap: () {
                                    widget.onSetDefaultImage();
                                    Navigator.pop(context);
                                  },
                                ),
                                const SizedBox(width: 16),
                                _buildCircleButton(
                                  context: context,
                                  icon: Icons.close,
                                  label: '취소',
                                  onTap: () {
                                    setState(() {
                                      _isDefaultImageMode = false;
                                    });
                                  },
                                ),
                              ],
                            )
                            : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // 공유하기 버튼
                                _buildCircleButton(
                                  context: context,
                                  icon: Icons.ios_share,
                                  label: '공유하기',
                                  onTap: widget.onShareProfile,
                                ),

                                // 갤러리선택 버튼
                                _buildCircleButton(
                                  context: context,
                                  icon: Icons.photo_library,
                                  label: '갤러리선택',
                                  onTap: () {
                                    _showMediaPicker();
                                  },
                                ),

                                // 기본이미지 버튼
                                _buildCircleButton(
                                  context: context,
                                  icon: Icons.person,
                                  label: '기본이미지',
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
                                          ? '팔로잉'
                                          : isRequested
                                          ? '요청됨'
                                          : '팔로우',
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
                              label: '공유하기',
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
                                  label: '다운로드',
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
    );
  }

  Widget _buildPlaceholder() {
    final theme = Theme.of(context);
    final String firstLetter =
        widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.3),
            fontSize: 100,
            fontWeight: FontWeight.w600,
          ),
        ),
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
        ErrorHandler.showError(context, '팔로우 요청에 실패했습니다');
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
        ErrorHandler.showError(context, '팔로우 해제에 실패했습니다');
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
        ErrorHandler.showError(context, '요청 취소에 실패했습니다');
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showError(context, '요청 취소에 실패했습니다');
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
                  '취소',
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
                  '완료',
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
                  label: '밝기',
                ),
                _buildAdjustToolButton(
                  theme: theme,
                  tool: _AdjustTool.contrast,
                  icon: Icons.contrast,
                  label: '대비',
                ),
                _buildAdjustToolButton(
                  theme: theme,
                  tool: _AdjustTool.saturation,
                  icon: Icons.palette,
                  label: '채도',
                ),
                _buildAdjustToolButton(
                  theme: theme,
                  tool: _AdjustTool.warmth,
                  icon: Icons.thermostat,
                  label: '따뜻함',
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
        label = '밝기';
        break;
      case _AdjustTool.contrast:
        value = _contrast;
        label = '대비';
        break;
      case _AdjustTool.saturation:
        value = _saturation;
        label = '채도';
        break;
      case _AdjustTool.warmth:
        value = _warmth;
        label = '따뜻함';
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
        _initialScale = null;
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
        _lastPanPosition = details.focalPoint;
      },
      onScaleUpdate: (details) {
        if (_uiImage == null) return;

        // 핀치 줌 처리
        if ((details.scale - 1.0).abs() >= 0.001) {
          _initialScale ??= _imageScale;
          final newScale = (_initialScale! * details.scale).clamp(
            _minScale,
            5.0,
          );

          setState(() {
            // scale 변경 시 offset을 중심 기준으로 비례 보정
            final scaleRatio = newScale / _imageScale;
            _imageScale = newScale;
            _imageOffset = _imageOffset * scaleRatio;
          });
          return;
        }

        // 드래그 처리
        if (_lastPanPosition != null) {
          final delta = details.focalPoint - _lastPanPosition!;

          // 드래그 감도 조정: 기본 감도 + 스케일에 비례한 감도 증가
          final baseSensitivity = 1.5; // 기본 감도
          final scaleMultiplier = _imageScale / _minScale; // 스케일 비례 계수
          final dragSensitivity = baseSensitivity * scaleMultiplier;

          // 원형 크롭박스를 벗어나지 않도록 clamp
          final newOffset = _clampOffset(
            _imageOffset +
                Offset(
                  delta.dx / _imageScale * dragSensitivity,
                  delta.dy / _imageScale * dragSensitivity,
                ),
            _imageScale,
            imageSize,
            containerSize,
          );

          setState(() {
            _imageOffset = newOffset;
            _lastPanPosition = details.focalPoint;
          });
        }
      },
      onScaleEnd: (_) {
        setState(() {
          _lastPanPosition = null;
          _initialScale = null;
          // 최종 clamp
          if (_uiImage != null) {
            _imageOffset = _clampOffset(
              _imageOffset,
              _imageScale,
              Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble()),
              Size(_cropSize, _cropSize),
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
        ),
      ),
    );
  }

  /// 이동 한계 계산 (원형 크롭박스를 벗어나지 않도록)
  /// crop_editor.dart의 clamp 로직 참고: 이미지가 크롭박스를 완전히 덮어야 함
  Offset _clampOffset(
    Offset offset,
    double scale,
    Size imageSize,
    Size containerSize,
  ) {
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: scale,
      offset: offset,
    );

    // 원형 크롭박스 (정사각형으로 처리)
    final cropRect = Rect.fromCenter(
      center: Offset(containerSize.width / 2, containerSize.height / 2),
      width: _cropSize,
      height: _cropSize,
    );

    double dx = offset.dx;
    double dy = offset.dy;

    // 이미지가 크롭박스를 완전히 덮어야 함
    // 왼쪽 경계: 이미지가 크롭박스 왼쪽으로 벗어나면 안 됨
    if (imageRect.left > cropRect.left) {
      dx = offset.dx - (imageRect.left - cropRect.left);
    }
    // 오른쪽 경계: 이미지가 크롭박스 오른쪽으로 벗어나면 안 됨
    if (imageRect.right < cropRect.right) {
      dx = offset.dx + (cropRect.right - imageRect.right);
    }
    // 위쪽 경계: 이미지가 크롭박스 위로 벗어나면 안 됨
    if (imageRect.top > cropRect.top) {
      dy = offset.dy - (imageRect.top - cropRect.top);
    }
    // 아래쪽 경계: 이미지가 크롭박스 아래로 벗어나면 안 됨
    if (imageRect.bottom < cropRect.bottom) {
      dy = offset.dy + (cropRect.bottom - imageRect.bottom);
    }

    return Offset(dx, dy);
  }

  /// 원형 크롭된 이미지 생성
  Future<File?> _cropImageToCircle() async {
    if (_uiImage == null || _selectedImage == null) return null;

    try {
      final imageSize = Size(
        _uiImage!.width.toDouble(),
        _uiImage!.height.toDouble(),
      );
      final containerSize = Size(_cropSize, _cropSize);

      // 현재 이미지 rect 계산
      final imageRect = ImageRectUtils.computeImageRect(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: _imageScale,
        offset: _imageOffset,
      );

      // 원형 크롭 영역 (컨테이너 기준)
      final cropRect = Rect.fromCenter(
        center: Offset(containerSize.width / 2, containerSize.height / 2),
        width: _cropSize,
        height: _cropSize,
      );

      // 이미지 좌표계에서 크롭 영역 계산
      // imageRect는 컨테이너 기준이므로, 이미지 원본 좌표계로 변환
      final imageToContainerScaleX = imageRect.width / imageSize.width;
      final imageToContainerScaleY = imageRect.height / imageSize.height;

      // 크롭 영역의 중심을 이미지 좌표계로 변환
      final cropCenterInImage = Offset(
        (cropRect.center.dx - imageRect.left) / imageToContainerScaleX,
        (cropRect.center.dy - imageRect.top) / imageToContainerScaleY,
      );

      // 원형 크롭 반지름 (이미지 좌표계)
      final cropRadiusInImage = (_cropSize / 2) / imageToContainerScaleX;

      // 원형 크롭 영역 (이미지 좌표계)
      final cropRectInImage = Rect.fromCircle(
        center: cropCenterInImage,
        radius: cropRadiusInImage,
      );

      // 이미지 경계 내로 클램프
      final clampedCropRect = Rect.fromLTWH(
        cropRectInImage.left.clamp(0.0, imageSize.width),
        cropRectInImage.top.clamp(0.0, imageSize.height),
        cropRectInImage.width.clamp(
          0.0,
          imageSize.width - cropRectInImage.left,
        ),
        cropRectInImage.height.clamp(
          0.0,
          imageSize.height - cropRectInImage.top,
        ),
      );

      // 원형 크롭된 이미지 생성 (PictureRecorder 사용)
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = Size(_cropSize, _cropSize);

      // 원형 클립 경로
      final clipPath =
          Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.clipPath(clipPath);

      // 이미지의 크롭 영역을 원형 크롭박스에 맞춰 그리기
      final srcRect = Rect.fromLTWH(
        clampedCropRect.left,
        clampedCropRect.top,
        clampedCropRect.width,
        clampedCropRect.height,
      );
      final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

      canvas.drawImageRect(
        _uiImage!,
        srcRect,
        dstRect,
        Paint()..colorFilter = _buildAdjustmentColorFilter(),
      );

      // Picture를 Image로 변환
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // 임시 파일로 저장
      final tempDir = await Directory.systemTemp.createTemp('profile_crop_');
      final tempFile = File(
        '${tempDir.path}/cropped_profile_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(pngBytes);

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

  _UnifiedImagePainter({
    required this.image,
    required this.screenImageRect,
    required this.cropRect,
    required this.borderColor,
    this.adjustmentFilter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // 1. 배경: 원형 영역 밖에 반투명 이미지 그리기
    // 원형 영역을 제외한 나머지 영역에만 그리기
    final backgroundPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..colorFilter = adjustmentFilter;

    // 원형 영역을 제외한 경로 생성
    final backgroundPath =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addOval(cropRect)
          ..fillType = PathFillType.evenOdd;

    canvas.save();
    canvas.clipPath(backgroundPath);
    canvas.drawImageRect(image, srcRect, screenImageRect, backgroundPaint);
    canvas.restore();

    // 2. 중앙: 원형 클립된 이미지 그리기
    canvas.save();
    // 원형 클립 경로
    final cropPath = Path()..addOval(cropRect);
    canvas.clipPath(cropPath);
    // 원형 영역 내부에 이미지 그리기
    canvas.drawImageRect(
      image,
      srcRect,
      screenImageRect,
      Paint()..colorFilter = adjustmentFilter,
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
        oldDelegate.adjustmentFilter != adjustmentFilter;
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
