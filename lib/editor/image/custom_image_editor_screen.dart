import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/service/image_service.dart';

/// image_editor_plus 기반의 간단한 편집 화면
/// - 입력: Uint8List 이미지 바이트
/// - 출력: Navigator.pop 으로 편집된 Uint8List 반환 (취소 시 null)
class ImageEditorPlusScreen extends StatelessWidget {
  const ImageEditorPlusScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    // ImageEditor 자체가 편집 UI와 완료/취소 동작을 내장하고 있음
    // 완료 시 Navigator.pop(context, Uint8List) 호출
    return ImageEditor(image: imageBytes);
  }
}

/// 헬퍼: 에디터를 열고 결과 바이트를 돌려받는다. (취소 시 null)
Future<Uint8List?> openImageEditorPlus(
  BuildContext context, {
  required Uint8List imageBytes,
}) async {
  // 커스텀 에디터 화면 오픈
  final edited = await Navigator.push<Uint8List?>(
    context,
    MaterialPageRoute(
      builder: (context) => CustomImageEditorScreen(imageBytes: imageBytes),
      fullscreenDialog: true,
    ),
  );
  return edited;
}

class CustomImageEditorScreen extends StatefulWidget {
  const CustomImageEditorScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CustomImageEditorScreen> createState() =>
      _CustomImageEditorScreenState();
}

class _CustomImageEditorScreenState extends State<CustomImageEditorScreen> {
  late Uint8List _currentImage;

  @override
  void initState() {
    _currentImage = widget.imageBytes;
    super.initState();
  }

  Future<void> _onCrop() async {
    final edited = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (context) => ImageCropper(image: _currentImage),
        fullscreenDialog: true,
      ),
    );
    if (edited != null && mounted) {
      setState(() {
        _currentImage = edited;
      });
    }
  }

  Future<void> _onFilter() async {
    final edited = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (context) => ImageFilters(image: _currentImage),
        fullscreenDialog: true,
      ),
    );
    if (edited != null && mounted) {
      setState(() {
        _currentImage = edited;
      });
    }
  }

  void _onDone() {
    // 편집 결과를 ImageService에 반영. 선택된 이미지가 존재하는 경우에만.
    final imageService = context.read<NodeComponentService>();
    final selectedId = imageService.selectedImageId;
    if (selectedId != null) {
      imageService.applyEditedBytes(nodeId: selectedId, bytes: _currentImage);
    }
    Navigator.pop(context, _currentImage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 미리보기(핀치-줌/팬을 위한 InteractiveViewer)
            Positioned.fill(
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 8,
                  child: Image.memory(_currentImage, fit: BoxFit.contain),
                ),
              ),
            ),

            // 상단 바
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                color: Colors.black.withOpacity(0.25),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.white),
                      onPressed: _onDone,
                    ),
                  ],
                ),
              ),
            ),

            // 하단 바
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: Colors.black87,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ToolButton(
                        icon: Icons.crop,
                        label: '자르기',
                        onTap: _onCrop,
                      ),
                      const SizedBox(width: 18),
                      _ToolButton(
                        icon: Icons.color_lens,
                        label: '필터',
                        onTap: _onFilter,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
