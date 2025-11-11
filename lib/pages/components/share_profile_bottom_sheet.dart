import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:doppy/l10n/app_localizations.dart';

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
    final shareText =
        context.tr('share_profile_message').replaceAll('{username}', username) +
        '\n$shareUrl';

    return ShareBottomSheet(
      title: context.tr('share_profile'),
      subtitle: context.tr('share_profile_subtitle'),
      shareUrl: shareUrl,
      shareText: shareText,
      previewWidget: _buildProfilePreview(context),
    );
  }

  /// 🎨 프로필 미리보기 (프로필 이미지를 배경으로)
  Widget _buildProfilePreview(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        constraints: BoxConstraints(
          maxWidth: 320,
          minHeight: 400, // 🎯 4:5 비율 유지
        ),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 400, // 🎯 명시적 높이 지정
            child: Stack(
              fit: StackFit.expand, // 🎯 passthrough → expand
              children: [
                // 🎯 배경: 프로필 이미지 전체
                Positioned.fill(
                  child:
                      profileImageUrl != null && profileImageUrl!.isNotEmpty
                          ? Image.network(
                            profileImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildGradientFallback();
                            },
                          )
                          : _buildGradientFallback(),
                ),

                // 🎯 하단 블러 (정보 영역만)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 100,
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                      child: Container(),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 90,
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2.3, sigmaY: 2.3),
                      child: Container(),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 80,
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2.6, sigmaY: 2.6),
                      child: Container(),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 70,
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                      child: Container(),
                    ),
                  ),
                ),

                // 🎯 상단: 사용자명
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "@$username",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        bio ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 🎯 하단: 사용자 정보 & 버튼
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Row(
                    children: [
                      // 중앙: 정보

                      // 우측: Share 버튼
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 16, color: Colors.black87),
                            SizedBox(width: 4),
                            Text(
                              context.tr('add_member'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🎯 프로필 이미지 없을 때 그라데이션 폴백
  Widget _buildGradientFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
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
  final String shareText;

  const ShareBottomSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.shareUrl,
    required this.previewWidget,
    required this.shareText,
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

                const SizedBox(height: 50),

                // 링크 공유 섹션
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
                          ),
                          _ShareButton(
                            icon: Icons.facebook,
                            label: 'Facebook',
                            color: const Color(0xFF1877F2),
                            onTap:
                                () => _shareToSNS('facebook', widget.shareText),
                          ),
                          _ShareButton(
                            imagePath: 'assets/images/x_logo.jpg',
                            label: 'X',
                            color: Colors.black,
                            onTap:
                                () => _shareToSNS('twitter', widget.shareText),
                          ),
                          _ShareButton(
                            imagePath: 'assets/images/thread_logo.jpg',
                            label: 'Threads',
                            color: Colors.black,
                            onTap:
                                () => _shareToSNS('threads', widget.shareText),
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
                                    : () => _shareGeneral(widget.shareText),
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
        // Instagram은 스토리 공유만 지원 (텍스트 직접 공유 불가)
        // 클립보드에 복사하고 Instagram 앱 열기
        await Clipboard.setData(ClipboardData(text: text));
        url = 'instagram://story-camera';
        break;
      case 'facebook':
        url =
            'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(widget.shareUrl)}';
        break;
      case 'twitter':
        url = 'https://twitter.com/intent/tweet?text=$encodedText';
        break;
      case 'threads':
        // Threads (Meta)
        await Clipboard.setData(ClipboardData(text: text));
        url = 'barcelona://create'; // Threads 앱 열기
        break;
      case 'telegram':
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

  // 🎯 시스템 공유 (커스텀 이미지 카드 + 텍스트)
  Future<void> _shareGeneral(String text) async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      // 1️⃣ previewWidget을 이미지로 캡처
      final imageFile = await _capturePreviewAsImage();

      if (imageFile != null) {
        // 2️⃣ 이미지 + 텍스트 함께 공유
        final result = await Share.shareXFiles(
          [XFile(imageFile.path)],
          text: text,
          subject: widget.title,
        );

        // 3️⃣ 임시 파일 삭제
        try {
          await imageFile.delete();
        } catch (_) {}

        print('✅ 공유 완료: ${result.status}');
      } else {
        // 캡처 실패 시 텍스트만 공유
        await Share.share(text, subject: widget.title);
      }

      setState(() => _isSharing = false);
    } catch (e) {
      print('⚠️ 시스템 공유 실패: $e');
      setState(() => _isSharing = false);

      // 폴백: 클립보드에 복사
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  // 🎯 Preview 위젯을 이미지로 캡처
  Future<File?> _capturePreviewAsImage() async {
    try {
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

      // 임시 디렉토리에 저장
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'doppy_share_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      await file.writeAsBytes(byteData.buffer.asUint8List());
      print('✅ 공유 이미지 생성 완료: $filePath');

      return file;
    } catch (e) {
      print('❌ 이미지 캡처 에러: $e');
      return null;
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

  const _ShareButton({
    this.icon,
    this.imagePath,
    required this.label,
    required this.color,
    required this.onTap,
    this.borderColor,
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
                  imagePath != null
                      ? Image.asset(imagePath!, fit: BoxFit.cover)
                      : Icon(
                        icon,
                        color:
                            borderColor != null ? borderColor! : Colors.white,
                        size: 24,
                      ),
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
