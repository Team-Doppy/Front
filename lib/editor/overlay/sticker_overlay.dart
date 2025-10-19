import 'dart:ui' as ui;
import 'package:doppy/editor/overlay/drawing_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/editor/image/native_image_picker.dart';

enum StickerKind { text, emoji, image, draw }

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

  // 이미지 편집 상태 관리
  ImageEditState _imageEditState = ImageEditState.selecting;
  Uint8List? _selectedImageBytes;
  double _imageBrightness = 0.0;
  double _imageContrast = 1.0;
  double _imageSaturation = 1.0;
  double _imageRotation = 0.0;
  bool _imageFlipped = false;

  @override
  void initState() {
    super.initState();
    // 툴바에서 항상 initialKind가 제공됨
    _kind = widget.initialKind;

    // 초기 이미지가 있으면 편집 모드로 시작
    if (_kind == StickerKind.image && widget.initialImage != null) {
      _selectedImageBytes = widget.initialImage;
      _imageEditState = ImageEditState.editing;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    switch (_kind) {
      case StickerKind.text:
      case StickerKind.emoji:
        return false; // 텍스트와 이모지는 비활성화
      case StickerKind.image:
        return _imageEditState == ImageEditState.editing &&
            _selectedImageBytes != null;
      case StickerKind.draw:
        return false; // 드로잉은 DrawingOverlay에서 처리
    }
  }

  @override
  Widget build(BuildContext context) {
    // 그리기 모드일 때는 제스처로 닫기 비활성화
    if (_kind == StickerKind.draw) {
      return DrawingOverlay(
        initialStrokes: widget.initialDrawingStrokes,
        scrollController: widget.scrollController,
        onSubmitDrawing: (strokes, position) {
          // 벡터 데이터를 전달
          widget.onSubmit(
            text: '',
            textStyle: {
              'drawingData': {
                'strokes': strokes,
                'position': {'x': position.dx, 'y': position.dy},
              },
            },
          );
        },
      );
    }

    return GestureDetector(
      onPanUpdate: (details) {
        // 드래그 중에는 아무것도 하지 않음 (시각적 피드백만)
      },
      onPanEnd: (details) {
        // 드래그 방향에 따라 오버레이 닫기
        final velocity = details.velocity.pixelsPerSecond;
        if (velocity.dy.abs() > velocity.dx.abs()) {
          // 세로 드래그 (아래로)
          if (velocity.dy > 300) {
            Navigator.of(context).pop();
          }
        } else {
          // 가로 드래그 (좌우)
          if (velocity.dx.abs() > 300) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,

        body: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const ui.Color.fromARGB(182, 144, 144, 144),
                    const ui.Color.fromARGB(200, 100, 100, 100),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).padding.top + 50,
                      child: Row(
                        children: [
                          const SizedBox(width: 20),
                          GestureDetector(
                            onTap: () {
                              _focus.unfocus();

                              Navigator.of(context).pop();
                            },
                            child: Icon(
                              Icons.arrow_back_ios_new,
                              color: Colors.white.withOpacity(0.9),
                              size: 20,
                            ),
                          ),
                          Spacer(),
                          _canSubmit
                              ? TextButton(
                                onPressed: _submit,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(
                                  _getSubmitButtonText(),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              )
                              : Padding(
                                padding: const EdgeInsets.only(right: 20),
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Icon(
                                    Icons.close,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),

                    // 중앙 프리뷰/에디터 영역
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildEditor(),
                        ),
                      ),
                    ),

                    // 텍스트 편집 하단 컨트롤
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    switch (_kind) {
      case StickerKind.text:
      case StickerKind.emoji:
        return const SizedBox.shrink(); // 텍스트와 이모지는 비활성화
      case StickerKind.image:
        return _buildImageEditor();
      case StickerKind.draw:
        return const SizedBox.shrink(); // 드로잉은 오버레이에서 처리
    }
  }

  void _submit() {
    Navigator.of(context).pop();
    switch (_kind) {
      case StickerKind.text:
      case StickerKind.emoji:
        // 텍스트와 이모지는 비활성화
        return;
      case StickerKind.image:
        if (_selectedImageBytes != null) {
          widget.onSubmit(text: '', image: _selectedImageBytes);
        }
        break;
      case StickerKind.draw:
        return;
    }
  }

  // ===== Helpers =====
  Future<void> _pickImageFromGallery() async {
    try {
      if (!mounted) return;

      final picker = NativeImagePicker();
      final file = await picker.pickSingleImage();

      if (file != null) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;

        // 이미지 선택 시 편집 모드로 전환
        setState(() {
          _selectedImageBytes = bytes;
          _imageEditState = ImageEditState.editing;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('이미지를 불러올 수 없습니다: $e')));
    }
  }

  String _getSubmitButtonText() {
    switch (_kind) {
      case StickerKind.image:
        return '완료';
      default:
        return '완료';
    }
  }

  // ===== Image Editor =====
  Widget _buildImageEditor() {
    if (_imageEditState == ImageEditState.selecting) {
      return _buildImageSelector();
    } else if (_imageEditState == ImageEditState.editing) {
      return _buildImageEditView();
    }
    return const SizedBox.shrink();
  }

  Widget _buildImageSelector() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image_outlined,
          size: 80,
          color: Colors.white.withOpacity(0.7),
        ),
        const SizedBox(height: 20),
        Text(
          '이미지를 선택하세요',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 30),
        ElevatedButton.icon(
          onPressed: _pickImageFromGallery,
          icon: const Icon(Icons.photo_library),
          label: const Text('갤러리에서 선택'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.2),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildImageEditView() {
    if (_selectedImageBytes == null) return const SizedBox.shrink();

    return Column(
      children: [
        // 이미지 미리보기
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(_getImageFilterMatrix()),
                child: Transform.rotate(
                  angle: _imageRotation,
                  child: Transform.flip(
                    flipX: _imageFlipped,
                    child: Image.memory(
                      _selectedImageBytes!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 편집 옵션들
        Expanded(flex: 2, child: _buildEditOptions()),
      ],
    );
  }

  Widget _buildEditOptions() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 밝기 조절
          _buildSliderOption(
            '밝기',
            _imageBrightness,
            -1.0,
            1.0,
            (value) => setState(() => _imageBrightness = value),
            Icons.brightness_6,
          ),

          const SizedBox(height: 12),

          // 대비 조절
          _buildSliderOption(
            '대비',
            _imageContrast,
            0.0,
            2.0,
            (value) => setState(() => _imageContrast = value),
            Icons.contrast,
          ),

          const SizedBox(height: 12),

          // 채도 조절
          _buildSliderOption(
            '채도',
            _imageSaturation,
            0.0,
            2.0,
            (value) => setState(() => _imageSaturation = value),
            Icons.palette,
          ),

          const SizedBox(height: 16),

          // 회전 및 뒤집기 버튼들
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildEditButton(
                '회전',
                Icons.rotate_right,
                () => setState(() => _imageRotation += 0.5),
              ),
              _buildEditButton(
                '뒤집기',
                Icons.flip,
                () => setState(() => _imageFlipped = !_imageFlipped),
              ),
              _buildEditButton('초기화', Icons.refresh, _resetImageEdit),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderOption(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.3),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          value.toStringAsFixed(1),
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildEditButton(String label, IconData icon, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetImageEdit() {
    setState(() {
      _imageBrightness = 0.0;
      _imageContrast = 1.0;
      _imageSaturation = 1.0;
      _imageRotation = 0.0;
      _imageFlipped = false;
    });
  }

  List<double> _getImageFilterMatrix() {
    // ColorFilter.matrix를 위한 변환 행렬 생성
    final brightness = _imageBrightness;
    final contrast = _imageContrast;

    // 간단한 밝기/대비 조절 (실제로는 더 복잡한 행렬이 필요할 수 있음)
    return [
      contrast,
      0,
      0,
      0,
      brightness * 255,
      0,
      contrast,
      0,
      0,
      brightness * 255,
      0,
      0,
      contrast,
      0,
      brightness * 255,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}
