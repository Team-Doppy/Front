import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../service/editor_service.dart';

/// 앱바용 언두/리두 버튼 그룹.
/// [androidPadding], [iosPadding]으로 플랫폼별 세부 패딩 조절 가능.
class UndoRedoButtons extends StatelessWidget {
  final EditorService editorService;

  /// Android에서 적용할 패딩 (버튼 그룹 전체). null이면 [defaultPadding] 사용.
  final EdgeInsets? androidPadding;

  /// iOS에서 적용할 패딩 (버튼 그룹 전체). null이면 [defaultPadding] 사용.
  final EdgeInsets? iosPadding;

  /// 플랫폼별 미지정 시 사용할 기본 패딩. 호출부에서 반드시 전달.
  final EdgeInsets defaultPadding;

  const UndoRedoButtons({
    super.key,
    required this.editorService,
    required this.defaultPadding,
    this.androidPadding,
    this.iosPadding,
  });

  EdgeInsets get _effectivePadding {
    if (Platform.isAndroid && androidPadding != null) return androidPadding!;
    if (Platform.isIOS && iosPadding != null) return iosPadding!;
    return defaultPadding;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _effectivePadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: editorService,
            builder: (context, _) => IconButton(
              onPressed: editorService.canUndo
                  ? () => editorService.undo()
                  : null,
              icon: SvgPicture.asset(
                'assets/icons/undo.svg',
                width: 19,
                height: 19,
                colorFilter: ColorFilter.mode(
                  Theme.of(context).colorScheme.onSurface.withOpacity(
                    editorService.canUndo ? 0.6 : 0.15,
                  ),
                  BlendMode.srcIn,
                ),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          AnimatedBuilder(
            animation: editorService,
            builder: (context, _) => IconButton(
              onPressed: editorService.canRedo
                  ? () => editorService.redo()
                  : null,
              icon: SvgPicture.asset(
                'assets/icons/redo.svg',
                width: 19,
                height: 19,
                colorFilter: ColorFilter.mode(
                  Theme.of(context).colorScheme.onSurface.withOpacity(
                    editorService.canRedo ? 0.6 : 0.15,
                  ),
                  BlendMode.srcIn,
                ),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }
}
