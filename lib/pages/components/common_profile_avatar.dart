import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/shimmer_box.dart';

class CommonProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final double size;
  final double? borderWidth;
  final Color? borderColor;
  final bool isUploading;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  // 이미지 대신 중앙에 임의 위젯을 표시하고 싶을 때 사용 (예: 검색 아이콘)
  final Widget? centerWidget;

  CommonProfileAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    this.size = 70.0,
    this.borderWidth,
    this.borderColor,
    this.isUploading = false,
    this.onTap,
    this.centerWidget,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final double effectiveBorderWidth = borderWidth ?? 2.0;
    final Color effectiveBorderColor =
        isDarkMode ? Colors.grey.shade300 : Colors.grey.shade300;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  backgroundColor ?? Theme.of(context).colorScheme.background,
              border: Border.all(
                color: borderColor ?? effectiveBorderColor,
                width: effectiveBorderWidth,
              ),
            ),
            child: ClipOval(
              child:
                  centerWidget != null
                      ? Container(
                        color: backgroundColor ?? Colors.transparent,
                        child: Center(child: centerWidget),
                      )
                      : imageUrl != null && imageUrl!.isNotEmpty
                      ? _buildImage(context, imageUrl!, isDarkMode)
                      : _buildPlaceholder(context, isDarkMode),
            ),
          ),
          if (isUploading)
            Positioned.fill(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(BuildContext context, String imageUrl, bool isDarkMode) {
    final bool isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final bool isFileUrl = imageUrl.startsWith('file://');

    if (isNetwork) {
      // 🎯 네트워크 URL: CachedNetworkImage 사용
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => ShimmerBox(width: size, height: size),
        errorWidget:
            (context, url, error) => _buildPlaceholder(context, isDarkMode),
        // ✅ 화질 개선: 캐시 크기를 3배로 증가 (더 선명한 이미지)
        memCacheWidth: (size * 3).round(),
        maxWidthDiskCache: (size * 3).round(),
        fadeInDuration: const Duration(milliseconds: 200), // 🎯 즉시 표시
        fadeOutDuration: const Duration(milliseconds: 200), // 🎯 즉시 표시
        // ✅ 고품질 필터링 적용
        filterQuality: FilterQuality.high,
      );
    } else if (isFileUrl) {
      // 🎯 로컬 파일 경로: Image.file 사용
      final String path = Uri.parse(imageUrl).toFilePath();
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        // ✅ 고품질 필터링 적용
        filterQuality: FilterQuality.high,
        errorBuilder:
            (context, error, stackTrace) =>
                _buildPlaceholder(context, isDarkMode),
      );
    } else {
      // 알 수 없는 형식: 플레이스홀더 표시
      return _buildPlaceholder(context, isDarkMode);
    }
  }

  Widget _buildPlaceholder(BuildContext context, bool isDarkMode) {
    // 사용자명의 첫 글자를 가져와서 표시
    final String firstLetter =
        username.isNotEmpty ? username[0].toUpperCase() : '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle),
      child: Center(
        child: Text(
          firstLetter,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            fontSize: size * 0.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Hero 전환 등에 사용할 "정적" 아바타
/// - Shimmer/Progress/제스처/애니메이션 없이 이미지(또는 placeholder)만 표시
/// - Hero flight 중 placeholder ↔ image 스왑/애니메이션으로 인한 깜빡임을 줄이기 위한 용도
class StaticProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final double size;
  final double borderWidth;
  final Color borderColor;
  final Color? backgroundColor;

  const StaticProfileAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    required this.size,
    this.borderWidth = 2.0,
    required this.borderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final String? url = imageUrl;

    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor ?? Theme.of(context).colorScheme.background,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: ClipOval(
          child:
              (url != null && url.isNotEmpty)
                  ? _StaticAvatarImage(imageUrl: url, size: size)
                  : _StaticAvatarPlaceholder(
                    username: username,
                    size: size,
                    isDarkMode: isDarkMode,
                  ),
        ),
      ),
    );
  }
}

class _StaticAvatarImage extends StatelessWidget {
  final String imageUrl;
  final double size;
  const _StaticAvatarImage({required this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final bool isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final bool isFileUrl = imageUrl.startsWith('file://');

    if (isNetwork) {
      // ✅ Hero 전환용 고품질 이미지: 캐시 크기를 더 크게 설정하여 선명도 향상
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        // ✅ 화질 개선: Hero 전환용이므로 더 높은 해상도 사용 (4배)
        memCacheWidth: (size * 4).round(),
        maxWidthDiskCache: (size * 4).round(),
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 200),
        // ✅ 고품질 필터링 적용
        filterQuality: FilterQuality.high,
        // ✅ 잔상 방지: 이전 프레임을 숨기고 새 이미지가 로드될 때만 표시
        placeholder: (context, url) => const SizedBox.shrink(),
        errorWidget: (context, url, error) {
          return _StaticAvatarPlaceholder(
            username: '',
            size: size,
            isDarkMode: Theme.of(context).brightness == Brightness.dark,
          );
        },
      );
    }

    if (isFileUrl) {
      final String path = Uri.parse(imageUrl).toFilePath();
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        // ✅ 잔상 방지: 이전 프레임을 숨기고 새 이미지가 로드될 때만 표시
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          // 로딩 중에는 투명하게 (이전 이미지 잔상 방지)
          return const SizedBox.shrink();
        },
        errorBuilder: (context, error, stackTrace) {
          return _StaticAvatarPlaceholder(
            username: '',
            size: size,
            isDarkMode: Theme.of(context).brightness == Brightness.dark,
          );
        },
      );
    }

    // 알 수 없는 형식은 placeholder로 대체
    return _StaticAvatarPlaceholder(
      username: '',
      size: size,
      isDarkMode: Theme.of(context).brightness == Brightness.dark,
    );
  }
}

class _StaticAvatarPlaceholder extends StatelessWidget {
  final String username;
  final double size;
  final bool isDarkMode;
  const _StaticAvatarPlaceholder({
    required this.username,
    required this.size,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final String firstLetter =
        username.isNotEmpty ? username[0].toUpperCase() : '';
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        firstLetter,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          fontSize: size * 0.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// 작은 크기용 프리셋
class SmallProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final double? borderWidth;
  final Color? borderColor;

  const SmallProfileAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    this.borderWidth,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return CommonProfileAvatar(
      imageUrl: imageUrl,
      username: username,
      size: 40.0,
      borderWidth: borderWidth,
      borderColor: borderColor,
    );
  }
}

// 중간 크기용 프리셋
class MediumProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final double? borderWidth;
  final Color? borderColor;

  const MediumProfileAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    this.borderWidth,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return CommonProfileAvatar(
      imageUrl: imageUrl,
      username: username,
      size: 70.0,
      borderWidth: borderWidth,
      borderColor: borderColor,
    );
  }
}
