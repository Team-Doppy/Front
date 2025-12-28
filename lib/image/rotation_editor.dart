import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'crop_editor.dart' show RotationRulerSlider;

/// 회전 편집 전용 유틸 + 바텀시트 UI
///
/// - SimpleImageEditorScreen에서는 "붙이기"만 하고
/// - 회전 동작/바텀시트 정의는 여기서 책임진다.
class RotationEditor {
  RotationEditor._();

  /// 90도 단위 회전 (오른쪽: +90, 왼쪽: -90)
  ///
  /// - preview는 bytes 자체를 갱신해서 처리한다(Transform 미적용).
  /// - 포맷은 PNG로 반환한다(단순/안정성 우선).
  static Uint8List rotate90(Uint8List bytes, {required bool clockwise}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('이미지 디코딩 실패');
    }
    final angle = clockwise ? 90.0 : -90.0;
    final rotated = img.copyRotate(decoded, angle: angle);
    return Uint8List.fromList(img.encodePng(rotated));
  }

  /// 이미지 반전 (좌우 또는 상하)
  static Uint8List flip(Uint8List bytes, {required bool horizontal}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('이미지 디코딩 실패');
    }
    final flipped =
        horizontal ? img.flipHorizontal(decoded) : img.flipVertical(decoded);
    return Uint8List.fromList(img.encodePng(flipped));
  }

  /// 이미지 회전 (임의 각도)
  static Uint8List rotate(Uint8List bytes, {required double angle}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('이미지 디코딩 실패');
    }
    final rotated = img.copyRotate(decoded, angle: angle);
    return Uint8List.fromList(img.encodePng(rotated));
  }

  /// 회전 모드 고정 프레임(크롭 박스) 비율에 맞춰 중앙 기준으로 크롭
  ///
  /// - 프리뷰에서 보여주는 "고정 크롭 박스"의 결과물을 맞추기 위한 단계.
  /// - 가장 큰 중앙 사각형을 찾아 비율을 맞춘다(가장자리 정보는 버림).
  static Uint8List cropCenterToAspect(
    Uint8List bytes, {
    required double aspectRatio,
  }) {
    if (aspectRatio <= 0) return bytes;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('이미지 디코딩 실패');
    }

    final w = decoded.width.toDouble();
    final h = decoded.height.toDouble();
    if (w <= 1 || h <= 1) return bytes;

    final current = w / h;

    double cropW;
    double cropH;
    if (current > aspectRatio) {
      // 더 넓음: 높이를 유지하고 너비를 줄인다
      cropH = h;
      cropW = h * aspectRatio;
    } else {
      // 더 높음: 너비를 유지하고 높이를 줄인다
      cropW = w;
      cropH = w / aspectRatio;
    }

    // 최소 크기 방어
    cropW = cropW.clamp(1.0, w);
    cropH = cropH.clamp(1.0, h);

    final x = ((w - cropW) / 2).round();
    final y = ((h - cropH) / 2).round();
    final cw = cropW.round();
    final ch = cropH.round();

    final cropped = img.copyCrop(decoded, x: x, y: y, width: cw, height: ch);
    return Uint8List.fromList(img.encodePng(cropped));
  }
}

/// 회전 바텀시트(콘텐츠) - SimpleImageEditorScreen의 공용 바텀시트 컨테이너 안에 끼워 넣는다.
class RotationEditorBottomSheet extends StatefulWidget {
  const RotationEditorBottomSheet({
    super.key,
    required this.rotation,
    required this.onRotationChanged,
    required this.onRotate90,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
    this.onReset,
  });

  final int rotation; // 0-360
  final ValueChanged<int> onRotationChanged;
  final VoidCallback onRotate90;
  final VoidCallback onFlipHorizontal;
  final VoidCallback onFlipVertical;
  final VoidCallback? onReset;

  @override
  State<RotationEditorBottomSheet> createState() =>
      _RotationEditorBottomSheetState();
}

class _RotationEditorBottomSheetState extends State<RotationEditorBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _optionsOpacityController;
  late Animation<double> _optionsOpacityAnimation;
  String _selectedOption = 'free';
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _optionsOpacityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _optionsOpacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(_optionsOpacityController);
  }

  @override
  void dispose() {
    _optionsOpacityController.dispose();
    super.dispose();
  }

  void _onSliderDragStart() {
    setState(() {
      _isDragging = true;
    });
    _optionsOpacityController.forward();
  }

  void _onSliderDragEnd() {
    setState(() {
      _isDragging = false;
    });
    _optionsOpacityController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 상단: 가로 스크롤 옵션 버튼들 + 중앙 원형 표시기
        SizedBox(
          height: 60,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 버튼들 (드래그 중일 때만 숨김)
                AnimatedBuilder(
                  animation: _optionsOpacityAnimation,
                  builder: (context, child) {
                    return IgnorePointer(
                      ignoring: _optionsOpacityAnimation.value < 0.5,
                      child: Opacity(
                        opacity: _optionsOpacityAnimation.value,
                        child: child,
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      _buildOptionButton(
                        context,
                        icon: Icons.crop_rotate,
                        isSelected: _selectedOption == 'free',
                        onTap: () {
                          setState(() {
                            _selectedOption = 'free';
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildOptionButton(
                        context,
                        icon: Icons.flip,
                        isSelected: _selectedOption == 'flip_h',
                        onTap: () {
                          setState(() {
                            _selectedOption = 'flip_h';
                          });
                          widget.onFlipHorizontal();
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildOptionButton(
                        context,
                        icon: Icons.flip_camera_ios,
                        isSelected: _selectedOption == 'flip_v',
                        onTap: () {
                          setState(() {
                            _selectedOption = 'flip_v';
                          });
                          widget.onFlipVertical();
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildOptionButton(
                        context,
                        icon: Icons.rotate_right,
                        isSelected: _selectedOption == 'rotate_90',
                        onTap: () {
                          setState(() {
                            _selectedOption = 'rotate_90';
                          });
                          widget.onRotate90();
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildOptionButton(
                        context,
                        icon: Icons.refresh,
                        isSelected: false,
                        onTap: () {
                          setState(() {
                            _selectedOption = 'free';
                          });
                          widget.onReset?.call();
                        },
                      ),
                    ],
                  ),
                ),

                // 중앙 원형 표시기 (드래그 중일 때만 Row 중앙에 표시)
                if (_isDragging) ...[
                  const Spacer(),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.85),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${widget.rotation}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 하단: 눈금 슬라이더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RotationRulerSlider(
            value: widget.rotation,
            onChanged: widget.onRotationChanged,
            onDragStart: _onSliderDragStart,
            onDragEnd: _onSliderDragEnd,
            isDragging: _isDragging,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? cs.primary : Colors.white.withOpacity(0.3),
            width: isSelected ? 2.5 : 1.5,
          ),
          color: Colors.transparent,
        ),
        child: Icon(
          icon,
          color: isSelected ? cs.primary : Colors.white,
          size: 26,
        ),
      ),
    );
  }
}
