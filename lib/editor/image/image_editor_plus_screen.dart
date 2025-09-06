import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_editor_plus/image_editor_plus.dart';

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
  final result = await Navigator.push<Uint8List?>(
    context,
    MaterialPageRoute(
      builder: (context) => ImageEditorPlusScreen(imageBytes: imageBytes),
      fullscreenDialog: true,
    ),
  );
  return result;
}
