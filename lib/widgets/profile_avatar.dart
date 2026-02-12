import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

enum _ImageSource { network, file, unknown }

_ImageSource _imageSource(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return _ImageSource.network;
  }
  if (url.startsWith('file://')) return _ImageSource.file;
  return _ImageSource.unknown;
}

class CommonProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final double size;
  final double borderWidth;
  final Color? borderColor;
  final Color? backgroundColor;

  const CommonProfileAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    required this.size,
    this.borderWidth = 2.0,
    this.borderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final borderC = borderColor ??
        Theme.of(context).colorScheme.onSurface.withAlpha(40);

    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderC, width: borderWidth),
        ),
        child: ClipOval(
          child:
              url != null && url.isNotEmpty
                  ? _AvatarImage(
                    imageUrl: url,
                    size: size,
                    fallback:
                        (_) => _AvatarPlaceholder(
                          username: username,
                          size: size,
                          backgroundColor: backgroundColor,
                        ),
                  )
                  : _AvatarPlaceholder(
                    username: username,
                    size: size,
                    backgroundColor: backgroundColor,
                  ),
        ),
      ),
    );
  }
}

class _AvatarImage extends StatelessWidget {
  final String imageUrl;
  final double size;
  final WidgetBuilder fallback;

  const _AvatarImage({
    required this.imageUrl,
    required this.size,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    switch (_imageSource(imageUrl)) {
      case _ImageSource.network:
        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          memCacheWidth: (size * 4).round(),
          maxWidthDiskCache: (size * 4).round(),
          filterQuality: FilterQuality.high,
          fadeInDuration: const Duration(milliseconds: 200),
          fadeOutDuration: const Duration(milliseconds: 200),
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => fallback(context),
        );
      case _ImageSource.file:
        final path = Uri.parse(imageUrl).toFilePath();
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
          frameBuilder:
              (_, child, frame, synced) =>
                  (synced || frame != null) ? child : const SizedBox.shrink(),
          errorBuilder: (_, __, ___) => fallback(context),
        );
      case _ImageSource.unknown:
        return fallback(context);
    }
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final String username;
  final double size;
  final Color? backgroundColor;

  const _AvatarPlaceholder({
    required this.username,
    required this.size,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final letter = username.isNotEmpty ? username[0].toUpperCase() : '';
    return Container(
      width: size,
      height: size,
      color: backgroundColor ?? Theme.of(context).colorScheme.background,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          fontSize: size * 0.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
