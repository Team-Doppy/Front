import 'package:flutter/material.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';

class ProfileAvatar extends StatelessWidget {
  final String imageUrl;
  final String username;
  final double size;
  final double borderWidth;
  final Color borderColor;
  final bool isUploading;
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    required this.imageUrl,
    required this.username,
    required this.size,
    required this.borderWidth,
    required this.borderColor,
    required this.isUploading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = CommonProfileAvatar(
      imageUrl: imageUrl,
      username: username,
      size: size,
      borderWidth: borderWidth,
      borderColor: borderColor,
    );

    final content = Stack(
      alignment: Alignment.center,
      children: [
        avatar,
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
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }
    return content;
  }
}
