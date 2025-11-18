import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:image/image.dart' as img;
import 'package:google_fonts/google_fonts.dart';

/// 👤 프로필 공유 바텀시트
class ShareProfileBottomSheet extends StatelessWidget {
  final String username;
  final String? profileImageUrl;
  final String? bio;
  final int friendCount;
  final List<String>? links; // 🎯 프로필 링크 목록
  final Map<String, String>? linkTitles; // 🎯 링크 타이틀 (URL -> 타이틀)

  const ShareProfileBottomSheet({
    super.key,
    required this.username,
    this.profileImageUrl,
    this.bio,
    required this.friendCount,
    this.links,
    this.linkTitles,
  });

  /// 바텀시트 표시
  static Future<void> show(
    BuildContext context, {
    required String username,
    String? profileImageUrl,
    String? bio,
    required int friendCount,
    List<String>? links,
    Map<String, String>? linkTitles,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => ShareProfileBottomSheet(
            username: username,
            profileImageUrl: profileImageUrl,
            bio: bio,
            friendCount: friendCount,
            links: links,
            linkTitles: linkTitles,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shareUrl = 'https://doppy.app/profile/$username';
    // 🎯 Instagram용 전체 텍스트 (이미지와 함께 공유)
    final shareText =
        '${context.tr('share_profile_message').replaceAll('{username}', username)}\n$shareUrl';
    // 🎯 Instagram 제외한 나머지용 메시지 (이미지 없이 링크와 메시지만)
    final shareTextWithoutImage =
        '${context.tr('friend_request_message').replaceAll('{username}', username)}\n$shareUrl';

    return ShareBottomSheet(
      title: context.tr('share_profile'),
      subtitle: context.tr('share_profile_subtitle'),
      shareUrl: shareUrl,
      shareText: shareText,
      shareTextWithoutImage: shareTextWithoutImage,
      username: username,
      previewWidget: _buildProfilePreview(context),
      links: links,
      linkTitles: linkTitles,
    );
  }

  /// 🎨 프로필 미리보기 (이미지 디자인과 동일하게)
  Widget _buildProfilePreview(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // 🎯 상단: 프로필 이미지
            if (profileImageUrl != null && profileImageUrl!.isNotEmpty)
              Image.network(
                profileImageUrl!,
                width: double.infinity,
                height: 400,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return Container(
                    width: double.infinity,
                    height: 400,
                    color: Colors.grey[200],
                    child: Center(
                      child: CircularProgressIndicator(
                        value:
                            loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: double.infinity,
                    height: 400,
                    child: Center(
                      child: Image.asset(
                        'assets/images/doppy_nobg.png',
                        width: 80,
                        height: 80,
                        color: Colors.white.withOpacity(0.8),
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              )
            else
              Container(
                width: double.infinity,
                height: 400,
                child: Center(
                  child: Image.asset(
                    'assets/images/doppy_nobg.png',
                    width: 80,
                    height: 80,
                    color: Colors.white.withOpacity(0.8),
                    fit: BoxFit.contain,
                  ),
                ),
              ),

            // 🎯 하단: 반투명 다크 오버레이 + 텍스트 및 버튼
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                      Colors.black.withOpacity(0.9),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🎯 이름 + 인증 배지
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            username,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // 🎯 설명 (바이오)
                    if (bio != null && bio!.isNotEmpty)
                      Text(
                        bio!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withOpacity(0.9),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                    const SizedBox(height: 12),

                    // 🎯 하단 버튼 2개
                    Row(
                      children: [
                        // Get In Touch 버튼
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.black.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Get in Touch',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🔗 공유 바텀시트 베이스 위젯
class ShareBottomSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String shareUrl;
  final Widget previewWidget;
  final String shareText; // 🎯 Instagram용 (이미지 포함)
  final String shareTextWithoutImage; // 🎯 Instagram 제외용 (이미지 없이 링크와 메시지만)
  final String username; // 🎯 username 전달용
  final List<String>? links; // 🎯 프로필 링크 목록
  final Map<String, String>? linkTitles; // 🎯 링크 타이틀 (URL -> 타이틀)

  const ShareBottomSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.shareUrl,
    required this.previewWidget,
    required this.shareText,
    required this.shareTextWithoutImage,
    required this.username,
    this.links,
    this.linkTitles,
  });

  @override
  State<ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<ShareBottomSheet> {
  bool _isCopied = false;
  bool _isSharing = false; // 🎯 공유 중 로딩 상태
  final GlobalKey _cardKey = GlobalKey(); // 🎯 카드 위젯 캡처용

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 드래그 핸들
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // 닫기 버튼
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),

                // 프리뷰 위젯 (프로필 사진 또는 글 썸네일)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: RepaintBoundary(
                    key: _cardKey, // 🎯 캡처용 키
                    child: widget.previewWidget,
                  ),
                ),

                const SizedBox(height: 15),

                // 🎯 링크 목록 섹션 (링크가 있을 때만 표시)
                if (widget.links != null && widget.links!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 링크 아이콘 헤더
                        Row(
                          children: [
                            Icon(
                              Icons.link,
                              size: 20,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Links',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // 링크 목록
                        ...widget.links!.asMap().entries.map((entry) {
                          final index = entry.key;
                          final url = entry.value;
                          return _buildLinkItem(context, url, index);
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // 프로필 공유 URL 섹션
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: GestureDetector(
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: widget.shareUrl),
                                );
                                setState(() {
                                  _isCopied = true;
                                });

                                // 2초 후 다시 복사 아이콘으로 변경
                                Future.delayed(const Duration(seconds: 2), () {
                                  if (mounted) {
                                    setState(() {
                                      _isCopied = false;
                                    });
                                  }
                                });
                              },
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.shareUrl,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      child: Icon(
                                        _isCopied ? Icons.check : Icons.copy,
                                        key: ValueKey(_isCopied),
                                        size: 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // SNS 공유 섹션
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ShareButton(
                            imagePath: 'assets/images/instagram_logo.jpg',
                            label: 'Instagram',
                            color: const Color(0xFFE4405F),
                            onTap:
                                () =>
                                    _shareToSNS('instagram', widget.shareText),
                            isLoading: _isSharing, // 🎯 로딩 상태 전달
                          ),
                          _ShareButton(
                            icon: Icons.facebook,
                            label: 'Facebook',
                            color: const Color(0xFF1877F2),
                            onTap:
                                () => _shareToSNS(
                                  'facebook',
                                  widget.shareTextWithoutImage,
                                ),
                          ),
                          _ShareButton(
                            imagePath: 'assets/images/x_logo.jpg',
                            label: 'X',
                            color: Colors.black,
                            onTap:
                                () => _shareToSNS(
                                  'twitter',
                                  widget.shareTextWithoutImage,
                                ),
                          ),
                          _ShareButton(
                            imagePath: 'assets/images/thread_logo.jpg',
                            label: 'Threads',
                            color: Colors.black,
                            onTap:
                                () => _shareToSNS(
                                  'threads',
                                  widget.shareTextWithoutImage,
                                ),
                          ),
                          _ShareButton(
                            icon:
                                _isSharing
                                    ? Icons.hourglass_empty
                                    : Icons.more_horiz,
                            label: '더보기',
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderColor: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.17),
                            onTap:
                                _isSharing
                                    ? () {}
                                    : () => _shareGeneral(
                                      widget.shareTextWithoutImage,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _shareToSNS(String platform, String text) async {
    String? url;
    final encodedText = Uri.encodeComponent(text);

    switch (platform) {
      case 'instagram':
        // 🎯 Instagram은 이미지 포함 공유
        // 이미지를 캡처해서 Instagram 앱에 공유
        await _shareToInstagramWithImage(text);
        return; // 🎯 별도 처리이므로 여기서 종료
      case 'facebook':
        // 🎯 이미지 없이 링크와 메시지만 전달
        url =
            'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(widget.shareUrl)}&quote=${Uri.encodeComponent(text)}';
        break;
      case 'twitter':
        // 🎯 이미지 없이 링크와 메시지만 전달
        url = 'https://twitter.com/intent/tweet?text=$encodedText';
        break;
      case 'threads':
        // 🎯 이미지 없이 링크와 메시지만 전달
        // Threads (Meta) - 클립보드에 텍스트 복사 후 앱 열기
        await Clipboard.setData(ClipboardData(text: text));
        url = 'barcelona://create'; // Threads 앱 열기
        break;
      case 'telegram':
        // 🎯 이미지 없이 링크와 메시지만 전달
        url =
            'https://t.me/share/url?url=${Uri.encodeComponent(widget.shareUrl)}&text=$encodedText';
        break;
    }

    if (url != null) {
      final uri = Uri.parse(url);
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          // URL을 열 수 없으면 클립보드에 복사
          await Clipboard.setData(ClipboardData(text: text));
        }
      } catch (e) {
        // 에러 발생 시 클립보드에 복사
        await Clipboard.setData(ClipboardData(text: text));
      }
    }
  }

  // 🎯 Instagram에 이미지 포함 공유 (글 공유와 동일한 메커니즘)
  Future<void> _shareToInstagramWithImage(String text) async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      // 1️⃣ previewWidget을 이미지로 캡처
      final imageFile = await _capturePreviewAsImage();

      if (imageFile == null) {
        print('❌ 이미지 캡처 실패');
        if (mounted) {
          setState(() => _isSharing = false);
          ErrorHandler.showError(context, '이미지 캡처에 실패했습니다.');
        }
        return;
      }

      // 2️⃣ 이미지를 갤러리에 저장
      final bytes = await imageFile.readAsBytes();
      final result = await ImageGallerySaver.saveImage(
        bytes,
        quality: 100,
        name:
            'doppy_profile_${widget.username}_${DateTime.now().millisecondsSinceEpoch}',
      );

      // 3️⃣ 링크를 클립보드에 복사
      await Clipboard.setData(ClipboardData(text: widget.shareUrl));

      // 4️⃣ 임시 파일 정리
      try {
        await imageFile.delete();
      } catch (_) {}

      // 5️⃣ 저장 실패 시
      if (result == null || result['isSuccess'] != true) {
        if (mounted) {
          setState(() => _isSharing = false);
          ErrorHandler.showError(context, '이미지 저장에 실패했습니다.');
        }
        return;
      }

      // 6️⃣ Instagram 갤러리 선택 화면으로 이동
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
            'Instagram 앱이 설치되어 있지 않습니다.\n이미지가 갤러리에 저장되었습니다.',
          );
        }
      }

      if (mounted) {
        setState(() => _isSharing = false);
      }
    } catch (e) {
      print('❌ Instagram 공유 실패: $e');
      if (mounted) {
        setState(() => _isSharing = false);
        ErrorHandler.showError(context, '공유에 실패했습니다.');
      }
    }
  }

  // 🎯 시스템 공유 (이미지 없이 링크와 메시지만 전달)
  Future<void> _shareGeneral(String text) async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      // 🎯 Instagram 제외한 나머지는 이미지 없이 텍스트만 공유
      await Share.share(text, subject: widget.title);

      setState(() => _isSharing = false);
    } catch (e) {
      print('⚠️ 시스템 공유 실패: $e');
      setState(() => _isSharing = false);

      // 폴백: 클립보드에 복사
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  // 🎯 Preview 위젯을 이미지로 캡처 (카드 부분만 정확하게 + 여백 추가)
  Future<File?> _capturePreviewAsImage() async {
    try {
      // 🎯 렌더링 완료 대기
      await Future.delayed(const Duration(milliseconds: 100));

      // RepaintBoundary로 감싸진 위젯 찾기
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        print('❌ 캡처할 위젯을 찾을 수 없음');
        return null;
      }

      // 고화질로 이미지 렌더링 (3배 해상도)
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData == null) {
        print('❌ 이미지 데이터 추출 실패');
        return null;
      }

      // 🎯 이미지를 디코드하여 카드 부분만 crop하고 여백 추가
      final originalImage = img.decodeImage(byteData.buffer.asUint8List());
      if (originalImage == null) {
        print('❌ 이미지 디코딩 실패');
        return null;
      }

      print('📏 원본 이미지 크기: ${originalImage.width}x${originalImage.height}');

      // 🎯 카드 부분만 정확하게 crop (패딩 제거)
      // RepaintBoundary는 Padding(24px) + 카드를 포함하므로 패딩을 제거해야 함
      final cardPadding = (24 * 3).round(); // pixelRatio 3.0 적용
      final cardWidth = originalImage.width - (cardPadding * 2);
      final cardHeight = originalImage.height;

      // 🎯 카드 부분만 crop (중앙 정렬)
      final cropX = cardPadding;
      final cropY = 0;
      final cropWidth = cardWidth;
      final cropHeight = cardHeight;

      print(
        '✂️ 카드 Crop 영역: x=$cropX, y=$cropY, width=$cropWidth, height=$cropHeight',
      );

      final croppedCard = img.copyCrop(
        originalImage,
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
      );

      print('✅ 카드 Crop 완료: ${croppedCard.width}x${croppedCard.height}');

      // 🎯 카드를 축소하지 않고 원본 크기 유지 (더 예쁘게)
      // 카드 자체가 이미 예쁘게 디자인되어 있으므로 축소하지 않음
      final finalCard = croppedCard;

      print('✅ 카드 크기 유지: ${finalCard.width}x${finalCard.height}');

      // 🎯 최종 이미지 크기 (카드 + 여백)
      // 가로 여백: 카드 크기의 40%씩 양쪽에 (더 넉넉하게)
      // 세로 여백: 카드 크기의 30%씩 위아래에
      final horizontalPadding = (finalCard.width * 0.4).round();
      final verticalPadding = (finalCard.height * 0.3).round();
      final finalWidth = finalCard.width + (horizontalPadding * 2);
      final finalHeight = finalCard.height + (verticalPadding * 2);

      // 🎯 밝은 그라데이션 배경에 카드 이미지 배치
      final finalImage = img.Image(width: finalWidth, height: finalHeight);

      // 🎯 밝은 그라데이션 배경 생성 (위에서 아래로: 밝은 보라색 → 밝은 핑크색)
      // 각 행마다 다른 색상으로 채우기
      for (int y = 0; y < finalHeight; y++) {
        final ratio = y / finalHeight;
        // 그라데이션 색상 계산
        final r = (255 * (1 - ratio * 0.3)).round().clamp(0, 255);
        final g = (230 * (1 - ratio * 0.2)).round().clamp(0, 255);
        final b = (255 * (1 - ratio * 0.1)).round().clamp(0, 255);

        // 각 행을 색상으로 채우기 (fillRect 사용)
        final rowImage = img.Image(width: finalWidth, height: 1);
        img.fill(rowImage, color: img.ColorRgb8(r, g, b));
        img.compositeImage(finalImage, rowImage, dstX: 0, dstY: y);
      }

      // 카드를 중앙에 배치
      img.compositeImage(
        finalImage,
        finalCard,
        dstX: horizontalPadding,
        dstY: verticalPadding,
      );

      print(
        '✅ 여백 추가 완료: ${finalImage.width}x${finalImage.height} (가로 여백: ${horizontalPadding}px, 세로 여백: ${verticalPadding}px)',
      );

      // 🎯 PNG로 인코딩
      final pngBytes = img.encodePng(finalImage);

      // 임시 디렉토리에 저장
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'doppy_share_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      await file.writeAsBytes(pngBytes);
      print('✅ 공유 이미지 생성 완료 (카드 + 여백): $filePath');

      return file;
    } catch (e) {
      print('❌ 이미지 캡처 에러: $e');
      return null;
    }
  }

  /// 🎯 링크 아이템 위젯 (이미지 디자인과 동일하게)
  Widget _buildLinkItem(BuildContext context, String url, int index) {
    // URL 정규화
    String displayUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      displayUrl = 'https://$url';
    }

    // 도메인 추출
    String domain = url;
    String? thumbnailUrl;
    try {
      final uri = Uri.parse(displayUrl);
      domain = uri.host.replaceFirst('www.', '');
      // 🎯 썸네일 URL 생성 (Google Favicon API)
      thumbnailUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
    } catch (_) {
      domain = url;
    }

    // 🎯 사용자가 입력한 타이틀 가져오기
    final customTitle = widget.linkTitles?[url];
    final displayTitle =
        (customTitle != null && customTitle.isNotEmpty) ? customTitle : domain;

    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () async {
        try {
          final uri = Uri.parse(displayUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } catch (e) {
          if (mounted) {
            ErrorHandler.showError(context, '링크를 열 수 없습니다: $url');
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // 🎯 링크 썸네일 아이콘
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  thumbnailUrl != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          thumbnailUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.link,
                              size: 20,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.5,
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              return child;
                            }
                            return Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value:
                                      loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress
                                                  .cumulativeBytesLoaded /
                                              loadingProgress
                                                  .expectedTotalBytes!
                                          : null,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                      : Icon(
                        Icons.link,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
            ),
            const SizedBox(width: 16),
            // 링크 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🎯 사용자가 입력한 타이틀 (두꺼운 글자)
                  Text(
                    displayTitle,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 전체 URL (작은 글자)
                  Text(
                    url,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 📱 SNS 공유 버튼
class _ShareButton extends StatelessWidget {
  final IconData? icon;
  final String? imagePath; // 🎯 이미지 경로 추가
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Color? borderColor;
  final bool isLoading; // 🎯 로딩 상태

  const _ShareButton({
    this.icon,
    this.imagePath,
    required this.label,
    required this.color,
    required this.onTap,
    this.borderColor,
    this.isLoading = false, // 🎯 기본값 false
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
              color: color,
              shape: BoxShape.circle,
              border:
                  borderColor != null
                      ? Border.all(color: borderColor!, width: 2)
                      : null,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child:
                  isLoading
                      ? Center(
                        // 🎯 로딩 중일 때 스피너 표시
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              borderColor != null ? borderColor! : Colors.white,
                            ),
                          ),
                        ),
                      )
                      : (imagePath != null
                          ? Image.asset(imagePath!, fit: BoxFit.cover)
                          : Icon(
                            icon,
                            color:
                                borderColor != null
                                    ? borderColor!
                                    : Colors.white,
                            size: 24,
                          )),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
