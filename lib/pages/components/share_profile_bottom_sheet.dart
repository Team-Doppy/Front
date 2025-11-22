import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 👤 프로필 공유 바텀시트
class ShareProfileBottomSheet extends StatelessWidget {
  final String username;
  final String? profileImageUrl;
  final String? bio;
  final int friendCount;

  const ShareProfileBottomSheet({
    super.key,
    required this.username,
    this.profileImageUrl,
    this.bio,
    required this.friendCount,
  });

  /// 바텀시트 표시
  static Future<void> show(
    BuildContext context, {
    required String username,
    String? profileImageUrl,
    String? bio,
    required int friendCount,
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
    );
  }

  /// 🎨 프로필 미리보기 (이미지 디자인과 동일하게)
  Widget _buildProfilePreview(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21.5),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // 🎯 상단: 프로필 이미지 (캐시된 이미지 재사용)
            if (profileImageUrl != null && profileImageUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: profileImageUrl!,
                width: double.infinity,
                height: 400,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(
                  milliseconds: 0,
                ), // 🎯 이미 로드된 이미지는 페이드인 없이 즉시 표시
                fadeOutDuration: const Duration(milliseconds: 0),
                memCacheWidth: 800, // 메모리 캐시 크기 지정
                maxWidthDiskCache: 800, // 디스크 캐시 크기
                placeholder:
                    (context, url) => Container(
                      width: double.infinity,
                      height: 400,
                      color: Theme.of(context).colorScheme.background,
                    ),
                errorWidget:
                    (context, url, error) => Container(
                      width: double.infinity,
                      height: 400,
                      child: Center(
                        child: Image.asset(
                          'assets/images/doppy_nobg.png',
                          width: 80,
                          height: 80,
                          color: Theme.of(context).colorScheme.onSurface,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
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
                              fontSize: 35,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 2),

                    // 🎯 설명 (바이오)
                    if (bio != null && bio!.isNotEmpty)
                      Text(
                        bio!,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withOpacity(0.9),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
  final String shareText; // 공유 텍스트
  final String shareTextWithoutImage; // 이미지 없이 링크와 메시지만
  final String username; // 🎯 username 전달용

  const ShareBottomSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.shareUrl,
    required this.previewWidget,
    required this.shareText,
    required this.shareTextWithoutImage,
    required this.username,
  });

  @override
  State<ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<ShareBottomSheet> {
  bool _isCopied = false;
  bool _isSharing = false; // 공유 중 로딩 상태
  bool _isSharingToInstagram = false; // 🎯 인스타그램 공유 중

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
                  child: widget.previewWidget,
                ),

                const SizedBox(height: 15),

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
                            color: Colors.black,
                            onTap: _shareToInstagram,
                            isLoading: _isSharingToInstagram,
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
                            icon:
                                _isSharing
                                    ? Icons.hourglass_empty
                                    : Icons.more_horiz,
                            label: context.tr('more'),
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

  // 🎯 시스템 공유 (딥링크로 링크 바로 연결)
  Future<void> _shareGeneral(String text) async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      // 🎯 shareTextWithoutImage에는 이미 링크가 포함되어 있으므로 중복 추가하지 않음
      await Share.share(widget.shareTextWithoutImage, subject: widget.title);

      setState(() => _isSharing = false);
    } catch (e) {
      print('⚠️ 시스템 공유 실패: $e');
      setState(() => _isSharing = false);

      // 폴백: 클립보드에 복사
      await Clipboard.setData(ClipboardData(text: widget.shareUrl));
    }
  }

  // 🎯 Instagram 공유 (링크만 클립보드 복사 후 DM 화면 열기)
  Future<void> _shareToInstagram() async {
    if (_isSharingToInstagram) return;

    setState(() => _isSharingToInstagram = true);

    try {
      // 🎯 링크를 클립보드에 복사 (이미지 캡처 없이)
      await Clipboard.setData(ClipboardData(text: widget.shareUrl));

      // 🎯 안내 메시지 먼저 표시 (인스타그램 앱이 열리는 동안)
      if (mounted) {
        ErrorHandler.showInfo(context, '링크가 클립보드에 복사되었습니다.\nDM에서 붙여넣어 공유하세요.');
      }

      // 🎯 Instagram DM 화면 열기
      // 참고: 인스타그램은 텍스트/링크만 전달하는 공식 딥링크가 없어서
      // DM 화면만 열리고, 사용자가 수동으로 붙여넣어야 합니다.
      final instagramDmUrl = Uri.parse('instagram://direct-inbox');

      if (await canLaunchUrl(instagramDmUrl)) {
        await launchUrl(instagramDmUrl, mode: LaunchMode.externalApplication);
        print('✅ Instagram DM 화면 열림');
      } else {
        // Instagram 앱이 없으면 클립보드 복사만
        print('⚠️ Instagram 앱 없음 - 클립보드에만 복사');
        if (mounted) {
          ErrorHandler.showInfo(
            context,
            '링크가 클립보드에 복사되었습니다.\nInstagram 앱이 설치되어 있지 않습니다.',
          );
        }
      }

      if (mounted) {
        setState(() => _isSharingToInstagram = false);
      }
    } catch (e) {
      print('❌ Instagram 공유 실패: $e');
      if (mounted) {
        setState(() => _isSharingToInstagram = false);
        // 실패해도 클립보드는 복사되어 있음
        ErrorHandler.showInfo(context, '링크가 클립보드에 복사되었습니다.');
      }
    }
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
                      ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
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
