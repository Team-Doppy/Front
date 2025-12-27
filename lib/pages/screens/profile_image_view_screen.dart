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

  // 이미지 상태 (crop_editor.dart 구조 참고)
  double _imageScale = 1.0;
  Offset _imageOffset = Offset.zero;
  double? _initialScale; // 핀치 시작 시 초기 scale
  Offset? _lastPanPosition;

  // 원형 크롭박스 크기 (고정)
  static const double _cropSize = 350.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProfileImage =
        widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty;

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

                // 오른쪽 하단 + 버튼 (갤러리 선택) - 계정 주인일 때만
                if (widget.isOwnProfile)
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: GestureDetector(
                      onTap: () {
                        _showMediaPicker();
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add,
                          color: theme.colorScheme.surface,
                          size: 28,
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
                            ? // 이미지가 선택된 경우 완료 버튼 표시
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildCircleButton(
                                  context: context,
                                  icon: Icons.check,
                                  label: '완료',
                                  onTap: () {
                                    widget.onGallerySelected(_selectedImage!);
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
                                      _selectedImage = null;
                                      _uiImage = null;
                                      _imageScale = 1.0;
                                      _imageOffset = Offset.zero;
                                      _initialScale = null;
                                      _lastPanPosition = null;
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
                                    widget.onSetDefaultImage();
                                    Navigator.pop(context);
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
          _imageScale = 1.0;
          _imageOffset = Offset.zero;
        });
      }
    }
  }

  /// 이미지 에디터 빌드 (crop_editor.dart 구조 참고)
  Widget _buildImageEditor(ThemeData theme) {
    if (_uiImage == null) return const SizedBox.shrink();

    final imageSize = Size(
      _uiImage!.width.toDouble(),
      _uiImage!.height.toDouble(),
    );
    final containerSize = Size(_cropSize, _cropSize);

    // ImageRectUtils로 이미지 rect 계산
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: _imageScale,
      offset: _imageOffset,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        // 배경: 원형 클립 밖에 투명하게 표시되는 원본 이미지
        CustomPaint(
          size: Size.infinite,
          painter: _BackgroundImagePainter(
            image: _uiImage!,
            imageRect: imageRect,
            cropSize: _cropSize,
          ),
        ),
        // 중앙: 원형 클립된 이미지 (제스처 가능)
        Container(
          width: _cropSize,
          height: _cropSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: ClipOval(
            child: GestureDetector(
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
                    1.0,
                    5.0,
                  );

                  setState(() {
                    _imageScale = newScale;
                  });
                  return;
                }

                // 드래그 처리
                if (_lastPanPosition != null) {
                  final delta = details.focalPoint - _lastPanPosition!;

                  // 원형 크롭박스를 벗어나지 않도록 clamp
                  final newOffset = _clampOffset(
                    _imageOffset +
                        Offset(delta.dx / _imageScale, delta.dy / _imageScale),
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
                      Size(
                        _uiImage!.width.toDouble(),
                        _uiImage!.height.toDouble(),
                      ),
                      Size(_cropSize, _cropSize),
                    );
                  }
                });
              },
              child: CustomPaint(
                size: Size(_cropSize, _cropSize),
                painter: _CroppedImagePainter(
                  image: _uiImage!,
                  imageRect: imageRect,
                ),
              ),
            ),
          ),
        ),
      ],
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
}

/// 배경 이미지 Painter (투명하게 표시)
class _BackgroundImagePainter extends CustomPainter {
  final ui.Image image;
  final Rect imageRect;
  final double cropSize;

  _BackgroundImagePainter({
    required this.image,
    required this.imageRect,
    required this.cropSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..colorFilter = ColorFilter.mode(
            Colors.white.withOpacity(0.3),
            BlendMode.modulate,
          );

    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(image, srcRect, imageRect, paint);
  }

  @override
  bool shouldRepaint(_BackgroundImagePainter oldDelegate) {
    return oldDelegate.imageRect != imageRect || oldDelegate.image != image;
  }
}

/// 크롭된 이미지 Painter (원형 클립 내부)
class _CroppedImagePainter extends CustomPainter {
  final ui.Image image;
  final Rect imageRect;

  _CroppedImagePainter({required this.image, required this.imageRect});

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // 원형 클립 경로 (크롭박스 크기만큼)
    final path = Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.clipPath(path);

    // imageRect는 전체 컨테이너 기준이므로, 크롭박스 영역으로 변환
    // 크롭박스는 컨테이너 중앙에 위치
    final cropRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width,
      height: size.height,
    );

    // imageRect와 cropRect의 교집합 영역만 그리기
    final drawRect = imageRect.intersect(cropRect);
    if (drawRect.width > 0 && drawRect.height > 0) {
      canvas.drawImageRect(image, srcRect, imageRect, Paint());
    }
  }

  @override
  bool shouldRepaint(_CroppedImagePainter oldDelegate) {
    return oldDelegate.imageRect != imageRect || oldDelegate.image != image;
  }
}
