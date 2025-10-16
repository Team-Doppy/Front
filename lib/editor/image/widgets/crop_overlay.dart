import 'package:flutter/material.dart';

/// 자르기 오버레이 (드래그 가능한 핸들과 그리드 포함)
class CropOverlay extends StatelessWidget {
  const CropOverlay({
    super.key,
    required this.cropRect,
    required this.onUpdate,
    required this.imageSize,
    required this.containerSize,
    required this.scale,
  });

  final Rect cropRect;
  final Function(Offset delta, String handle) onUpdate;
  final Size imageSize;
  final Size containerSize;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // 이미지의 실제 표시 영역 계산 (BoxFit.contain 기준)
        final imageAspectRatio = imageSize.width / imageSize.height;
        final containerAspectRatio = containerSize.width / containerSize.height;

        double imageDisplayWidth, imageDisplayHeight;
        double imageOffsetX, imageOffsetY;

        if (imageAspectRatio > containerAspectRatio) {
          // 이미지가 더 넓음 - 가로에 맞춤
          imageDisplayWidth = width * scale; // 스케일 적용
          imageDisplayHeight = (width / imageAspectRatio) * scale;
          imageOffsetX = (width - imageDisplayWidth) / 2;
          imageOffsetY = (height - imageDisplayHeight) / 2;
        } else {
          // 이미지가 더 높음 - 세로에 맞춤
          imageDisplayHeight = height * scale; // 스케일 적용
          imageDisplayWidth = (height * imageAspectRatio) * scale;
          imageOffsetX = (width - imageDisplayWidth) / 2;
          imageOffsetY = (height - imageDisplayHeight) / 2;
        }

        // Transform.scale로 이미지가 축소되면 오버레이도 함께 축소
        // 스케일이 1.0보다 작으면 오버레이도 축소
        final overlayScale = scale < 1.0 ? scale : 1.0;
        imageDisplayWidth *= overlayScale;
        imageDisplayHeight *= overlayScale;
        imageOffsetX = (width - imageDisplayWidth) / 2;
        imageOffsetY = (height - imageDisplayHeight) / 2;

        return Stack(
          children: [
            // 자르기 프레임
            Positioned(
              left: imageOffsetX + cropRect.left * imageDisplayWidth,
              top: imageOffsetY + cropRect.top * imageDisplayHeight,
              width: cropRect.width * imageDisplayWidth,
              height: cropRect.height * imageDisplayHeight,
              child: GestureDetector(
                onPanUpdate: (details) {
                  onUpdate(
                    Offset(
                      details.delta.dx / imageDisplayWidth,
                      details.delta.dy / imageDisplayHeight,
                    ),
                    'move',
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: CustomPaint(painter: GridPainter()),
                ),
              ),
            ),

            // 핸들들
            ..._buildHandles(
              imageOffsetX,
              imageOffsetY,
              imageDisplayWidth,
              imageDisplayHeight,
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildHandles(
    double imageOffsetX,
    double imageOffsetY,
    double imageDisplayWidth,
    double imageDisplayHeight,
  ) {
    final handleSize = 10.0;
    final handles = [
      {'name': 'topLeft', 'x': cropRect.left, 'y': cropRect.top},
      {'name': 'topRight', 'x': cropRect.right, 'y': cropRect.top},
      {'name': 'bottomLeft', 'x': cropRect.left, 'y': cropRect.bottom},
      {'name': 'bottomRight', 'x': cropRect.right, 'y': cropRect.bottom},
    ];

    return handles.map((h) {
      return Positioned(
        left:
            imageOffsetX +
            (h['x'] as double) * imageDisplayWidth -
            handleSize / 2,
        top:
            imageOffsetY +
            (h['y'] as double) * imageDisplayHeight -
            handleSize / 2,
        child: GestureDetector(
          onPanUpdate: (details) {
            onUpdate(
              Offset(
                details.delta.dx / imageDisplayWidth,
                details.delta.dy / imageDisplayHeight,
              ),
              h['name'] as String,
            );
          },
          child: Container(
            width: handleSize,
            height: handleSize,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 1),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }).toList();
  }
}

/// 그리드 페인터 (3x3 그리드)
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white.withOpacity(0.6)
          ..strokeWidth = 1;

    // 세로선 2개
    for (int i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // 가로선 2개
    for (int i = 1; i <= 2; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
