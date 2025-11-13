import 'dart:ui';
import 'dart:io';

import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;

/// 📝 포스트 공유 오버레이 (Medium 스타일)
class SharePostOverlay extends StatefulWidget {
  final String postId;
  final String title;
  final String summary; // 🎯 excerpt → summary로 변경
  final String authorUsername;
  final String? authorProfileImageUrl; // 🎯 작성자 프로필 이미지
  final String? thumbnailUrl;
  final int readTime; // 분

  const SharePostOverlay({
    super.key,
    required this.postId,
    required this.title,
    required this.summary, // 🎯 summary 사용
    required this.authorUsername,
    this.authorProfileImageUrl,
    this.thumbnailUrl,
    required this.readTime,
  });

  /// 오버레이 표시
  static Future<void> show(
    BuildContext context, {
    required String postId,
    required String title,
    required String summary, // 🎯 excerpt → summary
    required String authorUsername,
    String? authorProfileImageUrl, // 🎯 추가
    String? thumbnailUrl,
    required int readTime,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.85),
        pageBuilder: (context, animation, secondaryAnimation) {
          return SharePostOverlay(
            postId: postId,
            title: title,
            summary: summary, // 🎯 summary 전달
            authorUsername: authorUsername,
            authorProfileImageUrl: authorProfileImageUrl, // 🎯 전달
            thumbnailUrl: thumbnailUrl,
            readTime: readTime,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 🎯 슬라이드 대신 페이드인 애니메이션
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250), // 🎯 빠르게
      ),
    );
  }

  @override
  State<SharePostOverlay> createState() => _SharePostOverlayState();
}

enum ShareTheme { darkBlur, lightBlur, dark, light }

class _SharePostOverlayState extends State<SharePostOverlay> {
  final GlobalKey _fullScreenKey = GlobalKey(); // 🎯 전체 화면 캡처용
  bool _isSaving = false;
  bool _isCopied = false; // 🎯 복사 완료 상태
  bool _isBottomSheetCopied = false; // 🎯 바텀시트 내 복사 상태
  ShareTheme _currentTheme = ShareTheme.darkBlur; // 🎯 기본 테마
  String? _extractedThumbnailPath; // 🎯 비디오에서 추출한 썸네일 경로
  bool _isExtractingThumbnail = false; // 🎯 썸네일 추출 중

  @override
  void initState() {
    super.initState();
    _checkAndExtractVideoThumbnail();
  }

  @override
  void dispose() {
    // 추출한 썸네일 파일 정리
    if (_extractedThumbnailPath != null) {
      try {
        File(_extractedThumbnailPath!).delete();
      } catch (_) {}
    }
    super.dispose();
  }

  /// 🎯 비디오 URL인지 확인하고 썸네일 추출
  Future<void> _checkAndExtractVideoThumbnail() async {
    if (widget.thumbnailUrl == null || widget.thumbnailUrl!.isEmpty) return;

    final url = widget.thumbnailUrl!.toLowerCase();
    final isVideo =
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.avi') ||
        url.contains('/video/') ||
        url.contains('video');

    if (!isVideo) return;

    print('[SharePostOverlay] 비디오 URL 감지 - 썸네일 추출 시작: ${widget.thumbnailUrl}');

    setState(() => _isExtractingThumbnail = true);

    try {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: widget.thumbnailUrl!,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.PNG,
        maxHeight: 1920,
        quality: 90,
      );

      if (mounted && thumbnailPath != null) {
        setState(() {
          _extractedThumbnailPath = thumbnailPath;
          _isExtractingThumbnail = false;
        });
        print('[SharePostOverlay] 썸네일 추출 완료: $thumbnailPath');
      }
    } catch (e) {
      print('[SharePostOverlay] 썸네일 추출 실패: $e');
      if (mounted) {
        setState(() => _isExtractingThumbnail = false);
      }
    }
  }

  /// 🎯 표시할 썸네일 URL/경로 가져오기
  String? get _displayThumbnail {
    // 추출된 썸네일이 있으면 우선 사용
    if (_extractedThumbnailPath != null) {
      return _extractedThumbnailPath;
    }
    // 아니면 원본 URL
    return widget.thumbnailUrl;
  }

  /// 🎯 썸네일이 로컬 파일인지 확인
  bool get _isThumbnailLocal => _extractedThumbnailPath != null;

  /// 🎯 썸네일 이미지 빌더 (로컬/네트워크 자동 판단)
  Widget _buildThumbnailImage({
    required BoxFit fit,
    required Widget errorWidget,
  }) {
    if (_isExtractingThumbnail) {
      // 썸네일 추출 중이면 로딩 표시
      return Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }

    final thumbnail = _displayThumbnail;
    if (thumbnail == null || thumbnail.isEmpty) {
      return errorWidget;
    }

    // 로컬 파일이면 Image.file, 네트워크면 Image.network
    if (_isThumbnailLocal) {
      return Image.file(
        File(thumbnail),
        fit: fit,
        errorBuilder: (context, error, stackTrace) => errorWidget,
      );
    } else {
      return Image.network(
        thumbnail,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => errorWidget,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 🎯 캡처 영역 (배경 + 블러 + 카드만)
            Positioned.fill(
              child: RepaintBoundary(
                key: _fullScreenKey, // 🎯 전체 화면 캡처용
                child: Stack(
                  children: [
                    // 배경: 썸네일 이미지
                    Positioned.fill(
                      child: _buildThumbnailImage(
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 블러 효과
                    Positioned.fill(child: _buildBackgroundOverlay()),

                    // 카드만 (헤더, 버튼 제외)
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60), // 🎯 헤더 공간
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _buildPostCard(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 🎯 헤더 (캡처에서 제외)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(child: _buildHeader()),
            ),

            // 🎯 공유 버튼들 (캡처에서 제외)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [_buildShareOptions(), const SizedBox(height: 20)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: EdgeInsets.all(8),

              child: Icon(
                Icons.close,
                color: _getTextColor(),
                size: 24,
              ), // 🎯 테마별 색상
            ),
          ),

          Spacer(),
          // 🎯 테마 선택 버튼
          _buildThemeSelector(),
        ],
      ),
    );
  }

  /// 🎯 테마 선택 버튼
  Widget _buildThemeSelector() {
    return GestureDetector(
      onTap: _cycleTheme,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getButtonBackgroundColor(), // 🎯 테마별 배경
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getThemeLabel(),
              style: TextStyle(
                fontSize: 12,
                color: _getTextColor(), // 🎯 테마별 색상
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🎯 테마 순환
  void _cycleTheme() {
    setState(() {
      switch (_currentTheme) {
        case ShareTheme.darkBlur:
          _currentTheme = ShareTheme.lightBlur;
          break;
        case ShareTheme.lightBlur:
          _currentTheme = ShareTheme.dark;
          break;
        case ShareTheme.dark:
          _currentTheme = ShareTheme.light;
          break;
        case ShareTheme.light:
          _currentTheme = ShareTheme.darkBlur;
          break;
      }
    });
  }

  /// 🎯 테마 라벨
  String _getThemeLabel() {
    switch (_currentTheme) {
      case ShareTheme.darkBlur:
        return context.tr('theme_dark_blur'); // 어두운 블러
      case ShareTheme.lightBlur:
        return context.tr('theme_light_blur'); // 밝은 블러
      case ShareTheme.dark:
        return context.tr('theme_dark'); // 어두운
      case ShareTheme.light:
        return context.tr('theme_light'); // 밝은
    }
  }

  /// 🎯 배경 오버레이 (테마별)
  Widget _buildBackgroundOverlay() {
    switch (_currentTheme) {
      case ShareTheme.darkBlur:
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(color: Colors.black.withOpacity(0.7)),
        );
      case ShareTheme.lightBlur:
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            color: const Color.fromARGB(255, 209, 209, 209).withOpacity(0.2),
          ),
        );
      case ShareTheme.dark:
        return Container(color: AppColors.darkBackground);
      case ShareTheme.light:
        return Container(color: AppColors.lightBackground);
    }
  }

  /// 🎯 텍스트 색상 (테마별)
  Color _getTextColor({double opacity = 1.0}) {
    switch (_currentTheme) {
      case ShareTheme.darkBlur:
      case ShareTheme.dark:
      case ShareTheme.lightBlur:
        return Colors.white.withOpacity(opacity);

      case ShareTheme.light:
        return Colors.black.withOpacity(opacity);
    }
  }

  /// 🎯 보조 텍스트 색상 (테마별)
  Color _getSecondaryTextColor() {
    switch (_currentTheme) {
      case ShareTheme.darkBlur:
      case ShareTheme.lightBlur:
      case ShareTheme.dark:
        return Colors.white.withOpacity(0.7);

      case ShareTheme.light:
        return Colors.black.withOpacity(0.6);
    }
  }

  /// 🎯 버튼 배경 색상 (테마별)
  Color _getButtonBackgroundColor() {
    switch (_currentTheme) {
      case ShareTheme.darkBlur:
      case ShareTheme.dark:
        return Colors.white.withOpacity(0.1);
      case ShareTheme.lightBlur:
      case ShareTheme.light:
        return Colors.black.withOpacity(0.08);
    }
  }

  /// 🎯 포스트 카드 (Medium 스타일)
  Widget _buildPostCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 콘텐츠
        Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Row(
                  children: [
                    // 작성자 프로필 (원형) - 🎯 authorProfileImageUrl 사용
                    if (widget.authorProfileImageUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 10.0),
                        child: CommonProfileAvatar(
                          imageUrl: widget.authorProfileImageUrl ?? "",
                          username: widget.authorUsername,
                          size: 28,
                          borderWidth: 1,
                        ),
                      ),

                    // 작성자 이름
                    Expanded(
                      child: Text(
                        widget.authorProfileImageUrl!.isNotEmpty
                            ? widget.authorUsername
                            : '@' + widget.authorUsername,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _getTextColor(), // 🎯 테마별 색상
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // 제목
              Padding(
                padding: const EdgeInsets.only(left: 4.0, top: 4.0),
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _getTextColor(), // 🎯 테마별 색상
                    height: 1.3,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Summary
              if (widget.summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0, top: 6.0),
                  child: Text(
                    widget.summary, // 🎯 스키마에서 가져온 summary 사용
                    style: TextStyle(
                      fontSize: 14,
                      color: _getSecondaryTextColor(), // 🎯 테마별 색상
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 🎯 3:4 비율 프로필 이미지
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child:
                            _displayThumbnail != null &&
                                    _displayThumbnail!.isNotEmpty
                                ? _buildThumbnailImage(
                                  fit: BoxFit.cover,
                                  errorWidget: Container(
                                    color: Color(0xFF667EEA),
                                  ),
                                )
                                : Container(
                                  color: Color(0xFF667EEA),
                                  child: Center(
                                    child: Text(
                                      widget.authorUsername[0].toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  /// 🎯 공유 옵션들
  Widget _buildShareOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ShareOption(
            icon: _isCopied ? Icons.check : Icons.link,
            label: context.tr('copy_link'),
            onTap: _copyLink,
            iconColor: _getTextColor(),
            backgroundColor: _getButtonBackgroundColor(),
          ),
          _ShareOption(
            icon: Icons.share,
            label: context.tr('share_via'),
            onTap: _shareViaSystem,
            iconColor: _getTextColor(),
            backgroundColor: _getButtonBackgroundColor(),
          ),
          _ShareOption(
            icon: Icons.save_alt,
            label: context.tr('save_image'),
            onTap: _saveImage,
            iconColor: _getTextColor(),
            backgroundColor: _getButtonBackgroundColor(),
          ),
          _ShareOption(
            imagePath: 'assets/icons/instagram_logo.svg',
            label: 'Instagram',
            onTap: _shareToInstagram,
            iconColor: _getTextColor(),
            backgroundColor: _getButtonBackgroundColor(),
          ),
        ],
      ),
    );
  }

  /// 🎯 링크 복사
  Future<void> _copyLink() async {
    final shareUrl = 'https://doppy.app/post/${widget.postId}';
    await Clipboard.setData(ClipboardData(text: shareUrl));

    if (mounted) {
      setState(() => _isCopied = true);

      // 2초 후 원래 아이콘으로 복귀
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isCopied = false);
      });

      ErrorHandler.showInfo(context, context.tr('link_copied'));
    }
  }

  /// 🎯 시스템 공유 (바텀시트)
  Future<void> _shareViaSystem() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildShareBottomSheet(),
    );
  }

  /// 🎯 공유 바텀시트 (iOS 스타일)
  Widget _buildShareBottomSheet() {
    final shareUrl = 'https://doppy.app/post/${widget.postId}';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                // 핸들
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // URL 바
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isDark
                              ? Colors
                                  .grey
                                  .shade800 // 🎯 다크: 어둡게
                              : Colors.grey.shade100, // 라이트: 기존 유지
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            shareUrl,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark
                                      ? Colors
                                          .white // 🎯 다크: 희게
                                      : Colors.grey.shade700, // 라이트: 기존 유지
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: shareUrl),
                            );
                            if (mounted) {
                              setState(() => _isBottomSheetCopied = true);
                              setModalState(() {}); // 바텀시트 리빌드

                              // 2초 후 아이콘만 복귀 (시트는 열린 상태 유지)
                              Future.delayed(const Duration(seconds: 2), () {
                                if (mounted) {
                                  setState(() => _isBottomSheetCopied = false);
                                  setModalState(() {}); // 아이콘 복귀
                                }
                              });
                            }
                          },
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              _isBottomSheetCopied ? Icons.check : Icons.copy,
                              key: ValueKey(_isBottomSheetCopied),
                              size: 16,
                              color:
                                  _isBottomSheetCopied
                                      ? Theme.of(context).colorScheme.onSurface
                                      : (isDark
                                          ? Colors.white70
                                          : Colors.grey.shade600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // SNS 공유 버튼들
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SNSShareButton(
                        imagePath: 'assets/images/instagram_logo.jpg',
                        label: 'Instagram',
                        onTap: () {
                          Navigator.pop(context);
                          _shareToInstagram();
                        },
                      ),
                      _SNSShareButton(
                        imagePath: 'assets/images/facebook_logo.jpg',
                        label: 'Facebook',
                        onTap: () {
                          Navigator.pop(context);
                          _shareToSNS('facebook');
                        },
                      ),
                      _SNSShareButton(
                        imagePath: 'assets/images/x_logo.jpg',
                        label: 'X',
                        onTap: () {
                          Navigator.pop(context);
                          _shareToSNS('x');
                        },
                      ),
                      _SNSShareButton(
                        imagePath: 'assets/images/thread_logo.jpg',
                        label: 'Threads',
                        onTap: () {
                          Navigator.pop(context);
                          _shareToSNS('threads');
                        },
                      ),
                      _SNSShareButton(
                        icon: Icons.more_horiz,
                        label: context.tr('more'),
                        onTap: () {
                          Navigator.pop(context);
                          _shareViaSystemNative();
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 🎯 네이티브 시스템 공유
  Future<void> _shareViaSystemNative() async {
    final shareUrl = 'https://doppy.app/post/${widget.postId}';
    final shareText = '${widget.title}\n\n$shareUrl';

    try {
      final imageFile = await _captureCardAsImage();

      if (imageFile != null) {
        await Share.shareXFiles(
          [XFile(imageFile.path)],
          text: shareText,
          subject: widget.title,
        );

        try {
          await imageFile.delete();
        } catch (_) {}
      } else {
        await Share.share(shareText, subject: widget.title);
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: shareText));
    }
  }

  /// 🎯 SNS로 공유
  Future<void> _shareToSNS(String platform) async {
    final shareUrl = 'https://doppy.app/post/${widget.postId}';
    String url = '';

    switch (platform) {
      case 'facebook':
        url = 'https://www.facebook.com/sharer/sharer.php?u=$shareUrl';
        break;
      case 'x':
        url =
            'twitter://post?message=${Uri.encodeComponent(widget.title)}&url=$shareUrl';
        break;
      case 'threads':
        url = 'barcelona://create';
        break;
    }

    try {
      await Clipboard.setData(ClipboardData(text: shareUrl));

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (platform == 'facebook') {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      print('❌ $platform 공유 실패: $e');
    }
  }

  /// 🎯 이미지로 저장 (갤러리)
  Future<void> _saveImage() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final imageFile = await _captureCardAsImage();

      if (imageFile != null) {
        // 🎯 갤러리에 저장
        final bytes = await imageFile.readAsBytes();
        await ImageGallerySaver.saveImage(
          bytes,
          quality: 100,
          name:
              'doppy_post_${widget.postId}_${DateTime.now().millisecondsSinceEpoch}',
        );

        // 임시 파일 삭제
        try {
          await imageFile.delete();
        } catch (_) {}

        if (mounted) {
          ErrorHandler.showInfo(context, context.tr('image_saved'));
        }
      }
    } catch (e) {
      print('❌ 이미지 저장 실패: $e');

      if (mounted) {
        ErrorHandler.showError(context, context.tr('image_save_failed'));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 🎯 Instagram 공유 (갤러리 선택 화면으로)
  Future<void> _shareToInstagram() async {
    try {
      // 🎯 이미지를 갤러리에 먼저 저장
      final imageFile = await _captureCardAsImage();

      if (imageFile == null) {
        print('❌ 이미지 캡처 실패');
        return;
      }

      // 갤러리에 저장
      final bytes = await imageFile.readAsBytes();
      final result = await ImageGallerySaver.saveImage(
        bytes,
        quality: 100,
        name:
            'doppy_post_${widget.postId}_${DateTime.now().millisecondsSinceEpoch}',
      );

      // 링크를 클립보드에 복사
      final shareUrl = 'https://doppy.app/post/${widget.postId}';
      await Clipboard.setData(ClipboardData(text: shareUrl));

      // 임시 파일 정리
      try {
        imageFile.delete();
      } catch (_) {}

      // 저장 실패 시
      if (result == null || result['isSuccess'] != true) {
        if (mounted) {
          ErrorHandler.showError(context, context.tr('image_save_failed'));
        }
        return;
      }

      // 🎯 Instagram 갤러리 선택 화면으로 이동
      // instagram://library → 갤러리에서 선택 후 게시물/릴스/스토리 선택 가능
      final instagramUrl = Uri.parse('instagram://library?AssetPath=ALL');

      if (await canLaunchUrl(instagramUrl)) {
        await launchUrl(instagramUrl, mode: LaunchMode.externalApplication);
        print('✅ Instagram 갤러리 선택 화면 열림');
      } else {
        // Instagram 앱이 없으면 갤러리만 저장
        print('⚠️ Instagram 앱 없음 - 갤러리에만 저장');
        if (mounted) {
          ErrorHandler.showInfo(
            context,
            context.tr('instagram_not_installed') + '\n이미지가 갤러리에 저장되었습니다.',
          );
        }
      }
    } catch (e) {
      print('❌ Instagram 공유 실패: $e');
      if (mounted) {
        ErrorHandler.showError(context, context.tr('share_failed'));
      }
    }
  }

  /// 🎯 전체 화면을 캡처하고 4:5 비율로 crop
  Future<File?> _captureCardAsImage() async {
    try {
      // 🎯 렌더링 완료 대기
      await Future.delayed(const Duration(milliseconds: 100));

      // 🎯 전체 화면 캡처 (배경 이미지 + 블러 효과 포함, 헤더/버튼 제외)
      final boundary =
          _fullScreenKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) {
        print('❌ 캡처할 위젯을 찾을 수 없음 (_fullScreenKey)');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData == null) {
        print('❌ 이미지 데이터 추출 실패');
        return null;
      }

      // 🎯 이미지를 디코드하여 crop
      final originalImage = img.decodeImage(byteData.buffer.asUint8List());
      if (originalImage == null) {
        print('❌ 이미지 디코딩 실패');
        return null;
      }

      print('📏 원본 이미지 크기: ${originalImage.width}x${originalImage.height}');

      // 🎯 3:4 비율 계산 (너비 기준) - 더 세로로 길게
      final targetWidth = originalImage.width;
      final targetHeight = (targetWidth * 4 / 3).round(); // 3:4 비율

      // 🎯 상하를 균등하게 잘라냄 (중앙 정렬)
      final cropY = ((originalImage.height - targetHeight) / 2).round().clamp(
        0,
        originalImage.height,
      );
      final cropHeight = targetHeight.clamp(0, originalImage.height);

      print(
        '✂️ Crop 영역 (3:4): x=0, y=$cropY, width=$targetWidth, height=$cropHeight',
      );

      // 🎯 이미지 crop
      final croppedImage = img.copyCrop(
        originalImage,
        x: 0,
        y: cropY,
        width: targetWidth,
        height: cropHeight,
      );

      print('✅ Crop 완료: ${croppedImage.width}x${croppedImage.height}');

      // 🎯 PNG로 인코딩
      final pngBytes = img.encodePng(croppedImage);

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'doppy_post_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      await file.writeAsBytes(pngBytes);
      print('✅ 공유 이미지 생성 완료 (3:4 비율): $filePath');

      return file;
    } catch (e) {
      print('❌ 이미지 캡처 에러: $e');
      return null;
    }
  }
}

/// 🎯 공유 옵션 버튼
class _ShareOption extends StatelessWidget {
  final IconData? icon;
  final String? imagePath; // 🎯 이미지 지원
  final String label;
  final VoidCallback onTap;
  final Color iconColor; // 🎯 아이콘 색상
  final Color backgroundColor; // 🎯 배경 색상

  const _ShareOption({
    this.icon,
    this.imagePath,
    required this.label,
    required this.onTap,
    required this.iconColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: backgroundColor, // 🎯 테마별 배경
              shape: BoxShape.circle,
            ),
            child:
                imagePath != null
                    ? Padding(
                      padding: const EdgeInsets.all(16.0), // 🎯 SVG 여백
                      child: SvgPicture.asset(
                        imagePath!,
                        colorFilter: ColorFilter.mode(
                          iconColor,
                          BlendMode.srcIn,
                        ), // 🎯 테마별 색상 적용
                        fit: BoxFit.contain,
                      ),
                    )
                    : Icon(
                      icon ?? Icons.share,
                      color: iconColor,
                      size: 26,
                    ), // 🎯 테마별 색상
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: iconColor.withOpacity(0.9), // 🎯 테마별 색상
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 🎯 SNS 공유 버튼 (iOS 스타일)
class _SNSShareButton extends StatelessWidget {
  final String? imagePath;
  final IconData? icon;
  final String label;
  final VoidCallback onTap;

  const _SNSShareButton({
    this.imagePath,
    this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: imagePath == null ? Colors.grey.shade300 : null,
            ),
            child: ClipOval(
              child:
                  imagePath != null
                      ? Image.asset(
                        imagePath!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade300,
                            child: Icon(
                              Icons.image,
                              color: Colors.grey.shade600,
                            ),
                          );
                        },
                      )
                      : Icon(
                        icon ?? Icons.share,
                        color: Colors.grey.shade700,
                        size: 24,
                      ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
