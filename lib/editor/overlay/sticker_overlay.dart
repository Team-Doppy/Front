import 'package:doppy/editor/overlay/drawing_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum StickerKind { draw }

enum ImageEditState {
  selecting, // 이미지 선택 중
  editing, // 이미지 편집 중
  completed, // 편집 완료
}

class StickerOverlay extends StatefulWidget {
  const StickerOverlay({
    super.key,
    required this.onSubmit,
    required this.initialKind,
    this.initialText,
    this.initialEmoji,
    this.initialImage,
    this.initialDrawingStrokes,
    this.scrollController,
  });

  final void Function({
    required String text,
    String? emoji,
    Uint8List? image,
    Map<String, dynamic>? textStyle,
  })
  onSubmit;
  final StickerKind initialKind;
  final String? initialText;
  final String? initialEmoji;
  final Uint8List? initialImage;
  final List<Map<String, dynamic>>? initialDrawingStrokes;
  final ScrollController? scrollController;

  @override
  State<StickerOverlay> createState() => _StickerOverlayState();
}

class _StickerOverlayState extends State<StickerOverlay> {
  late StickerKind _kind; // 툴바에서 항상 초기 종류가 제공됨
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 툴바에서 항상 initialKind가 제공됨
    _kind = widget.initialKind;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 그리기 모드일 때는 제스처로 닫기 비활성화
    if (_kind == StickerKind.draw) {
      return DrawingOverlay(
        initialStrokes: widget.initialDrawingStrokes,
        scrollController: widget.scrollController,
        onSubmitDrawing: (strokes, position, {int? groupIndex}) {
          // 🎯 PNG 또는 벡터 데이터 전달
          widget.onSubmit(
            text: '',
            textStyle: {
              'drawingData': {
                'strokes':
                    strokes, // PNG일 경우 [{'type': 'png_image', 'imageData': Uint8List, ...}]
                'position': {'x': position.dx, 'y': position.dy},
                'groupIndex': groupIndex,
              },
            },
          );
        },
      );
    }

    return Container(color: Colors.red, child: Text(''));
  }
}
