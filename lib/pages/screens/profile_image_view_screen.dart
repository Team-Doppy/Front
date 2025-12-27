import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/image/crop_editor.dart' show ImageRectUtils;
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

  // 이미지 선택 및 편집 관련
  File? _selectedImage;
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;
  Offset _lastFocalPoint = Offset.zero;
  double _startScale = 1.0; // 제스처 시작 시 스케일 (누적 방지용)
  ui.Image? _uiImage; // 원본 이미지 (크기 계산용)

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

                // 선택된 이미지가 있을 때 드래그 가능한 이미지 표시
                if (_selectedImage != null && widget.isOwnProfile)
                  Container(
                    width: 350,
                    height: 350,
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
                          _lastFocalPoint = details.focalPoint;
                          _startScale = _imageScale; // 제스처 시작 시 스케일 저장
                        },
                        onScaleUpdate: (details) {
                          if (_uiImage == null) return;

                          setState(() {
                            final imageSize = Size(
                              _uiImage!.width.toDouble(),
                              _uiImage!.height.toDouble(),
                            );
                            final containerSize = const Size(350, 350);

                            // 확대/축소: startScale * details.scale (누적 방지)
                            final newScale = _startScale * details.scale;

                            // 최소 스케일 계산: ImageRectUtils 사용
                            final imageRectAtScale1 =
                                ImageRectUtils.computeImageRect(
                                  containerSize: containerSize,
                                  imageSize: imageSize,
                                  scale: 1.0,
                                  offset: Offset.zero,
                                );
                            final scaleForWidth =
                                imageRectAtScale1.width / imageSize.width;
                            final scaleForHeight =
                                imageRectAtScale1.height / imageSize.height;
                            final minScale =
                                (scaleForWidth > scaleForHeight
                                    ? scaleForWidth
                                    : scaleForHeight) *
                                1.05;

                            _imageScale = newScale.clamp(minScale, 4.0);

                            // 이동: delta / scale (스케일 반영)
                            final delta = details.focalPoint - _lastFocalPoint;
                            final newOffset =
                                _imageOffset + (delta / _imageScale);

                            // 매 프레임 clamp 적용 (인스타 방식)
                            _imageOffset = _clampOffset(
                              offset: newOffset,
                              imageSize: imageSize,
                              scale: _imageScale,
                              containerSize: containerSize,
                            );

                            _lastFocalPoint = details.focalPoint;
                          });
                        },
                        onScaleEnd: (details) {
                          // 드래그 종료 시 미세 snap만 (이미 clamp되어 있으므로 최소한의 보정)
                          if (_uiImage != null) {
                            final imageSize = Size(
                              _uiImage!.width.toDouble(),
                              _uiImage!.height.toDouble(),
                            );
                            final containerSize = const Size(350, 350);

                            // 최소 스케일 확인
                            final minScaleForWidth =
                                containerSize.width / imageSize.width;
                            final minScaleForHeight =
                                containerSize.height / imageSize.height;
                            final minScale =
                                (minScaleForWidth > minScaleForHeight
                                    ? minScaleForWidth
                                    : minScaleForHeight) *
                                1.01;

                            setState(() {
                              // 스케일 보정
                              if (_imageScale < minScale) {
                                _imageScale = minScale;
                              }

                              // offset은 이미 clamp되어 있지만, 한 번 더 확인
                              _imageOffset = _clampOffset(
                                offset: _imageOffset,
                                imageSize: imageSize,
                                scale: _imageScale,
                                containerSize: containerSize,
                              );
                            });
                          }
                        },
                        child: Transform(
                          transform:
                              Matrix4.identity()
                                ..translate(_imageOffset.dx, _imageOffset.dy)
                                ..scale(_imageScale),
                          alignment: Alignment.center,
                          child:
                              _uiImage != null
                                  ? SizedBox(
                                    width: _uiImage!.width.toDouble(),
                                    height: _uiImage!.height.toDouble(),
                                    child: Image.file(
                                      _selectedImage!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                  : Image.file(
                                    _selectedImage!,
                                    fit: BoxFit.cover,
                                  ),
                        ),
                      ),
                    ),
                  ),
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
                                      _imageOffset = Offset.zero;
                                      _imageScale = 1.0;
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
      // 이미지 로드 및 초기 스케일 계산
      _loadImageAndCalculateScale(file);
    }
  }

  /// 이미지 로드 및 원형 컨테이너를 채우는 초기 스케일 계산
  /// 에디터의 ImageRectUtils.computeImageRect 로직 사용
  Future<void> _loadImageAndCalculateScale(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      if (mounted) {
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());
        final containerSize = const Size(350, 350); // 원형 컨테이너 크기

        // 단일 좌표계: ImageRectUtils.computeImageRect 사용
        final imageRectAtScale1 = ImageRectUtils.computeImageRect(
          containerSize: containerSize,
          imageSize: imageSize,
          scale: 1.0,
          offset: Offset.zero,
        );

        // 원본 이미지 크기 대비 표시 크기의 비율 = 최소 스케일
        final scaleForWidth = imageRectAtScale1.width / imageSize.width;
        final scaleForHeight = imageRectAtScale1.height / imageSize.height;
        // 둘 중 큰 값을 사용하여 컨테이너를 완전히 채움
        final minScale =
            (scaleForWidth > scaleForHeight ? scaleForWidth : scaleForHeight) *
            1.05; // 5% 여유

        setState(() {
          _selectedImage = file;
          _uiImage = image;
          _imageOffset = Offset.zero;
          _imageScale = minScale.clamp(1.0, 4.0);
        });
      }
    } catch (e) {
      debugPrint('[ProfileImageView] 이미지 로드 실패: $e');
      if (mounted) {
        setState(() {
          _selectedImage = file;
          _imageOffset = Offset.zero;
          _imageScale = 1.0;
        });
      }
    }
  }

  /// 인스타 방식: rect 기반 clamp (매 프레임 적용)
  /// ImageRectUtils.computeImageRect를 단일 진실로 사용
  Offset _clampOffset({
    required Offset offset,
    required Size imageSize,
    required double scale,
    required Size containerSize,
  }) {
    // 단일 좌표계: ImageRectUtils.computeImageRect 사용
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: scale,
      offset: offset,
    );

    // 컨테이너 rect (사각형 기준)
    final containerRect = Rect.fromLTWH(
      0,
      0,
      containerSize.width,
      containerSize.height,
    );

    // rect containment: 이미지가 컨테이너를 완전히 덮어야 함
    double fixX = 0;
    double fixY = 0;

    if (imageRect.left > containerRect.left) {
      fixX = containerRect.left - imageRect.left;
    }
    if (imageRect.right < containerRect.right) {
      fixX = containerRect.right - imageRect.right;
    }
    if (imageRect.top > containerRect.top) {
      fixY = containerRect.top - imageRect.top;
    }
    if (imageRect.bottom < containerRect.bottom) {
      fixY = containerRect.bottom - imageRect.bottom;
    }

    return offset + Offset(fixX, fixY);
  }
}
