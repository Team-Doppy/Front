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

  const CommonProfileAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    this.size = 70.0,
    this.borderWidth,
    this.borderColor,
    this.isUploading = false,
    this.onTap,
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
              border: Border.all(
                color: effectiveBorderColor,
                width: effectiveBorderWidth,
              ),
            ),
            child: ClipOval(
              child:
                  imageUrl != null && imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) =>
                                ShimmerBox(width: size, height: size),
                        errorWidget:
                            (context, url, error) =>
                                _buildPlaceholder(context, isDarkMode),
                        memCacheWidth: (size * 2).round(),
                        maxWidthDiskCache: (size * 2).round(),
                        fadeInDuration: const Duration(milliseconds: 200),
                        fadeOutDuration: const Duration(milliseconds: 200),
                      )
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
            color: isDarkMode ? Colors.white : Colors.grey.shade700,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
          ),
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
