import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ImageBarWidget extends StatelessWidget {
  const ImageBarWidget({
    super.key,
    required this.imageUrl,
    this.onAdjust,
    this.onCrop,
    this.onDelete,
  });

  final String imageUrl;
  final VoidCallback? onAdjust;
  final VoidCallback? onCrop;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(icon: Icons.tune, onTap: onAdjust),
          _buildDivider(),
          _buildOption(icon: Icons.crop, onTap: onCrop),
          _buildDivider(),
          _buildOption(
            icon: Icons.delete_outline,
            onTap: onDelete,
            color: Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final textColor = color ?? Colors.black;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque, // 자식 영역을 명확히 히트 처리
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (TapGestureRecognizer instance) {
                instance.onTap = onTap;
              },
            ),
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 18, color: textColor)],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.black.withOpacity(0.08),
    );
  }
}

class RowImageBarWidget extends StatelessWidget {
  const RowImageBarWidget({
    super.key,
    required this.imageUrl,
    this.onAdjust,
    this.onCrop,
    this.onDelete,
  });

  final String imageUrl;
  final VoidCallback? onAdjust;
  final VoidCallback? onCrop;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            icon: Icons.delete_outline,
            onTap: onDelete,
            color: Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,

    required VoidCallback? onTap,
    Color? color,
  }) {
    final textColor = color ?? Colors.black;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 18, color: textColor)],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.black.withOpacity(0.08),
    );
  }
}
