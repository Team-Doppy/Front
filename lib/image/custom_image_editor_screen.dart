import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:provider/provider.dart';

// Services
import 'package:doppy/editor/service/node_component_service.dart';

/// pro_image_editor 패키지 기반의 이미지 편집 화면
/// 최소 설정으로 시작하여 점진적으로 확장
class CustomImageEditorScreen extends StatelessWidget {
  const CustomImageEditorScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    final nodeService = context.read<NodeComponentService>();
    final selectedId = nodeService.selectedImageId;

    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Theme.of(context).colorScheme.background,
        brightness: Theme.of(context).brightness,
      ),
      useMaterial3: true,
    );

    final configs = ProImageEditorConfigs(
      designMode:
          Platform.isIOS
              ? ImageEditorDesignMode.cupertino
              : ImageEditorDesignMode.material,
      theme: theme.copyWith(
        chipTheme: theme.chipTheme.copyWith(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          labelStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
          selectedColor: Theme.of(context).colorScheme.onSurface,
        ),
        scrollbarTheme: ScrollbarThemeData(
          thickness: WidgetStateProperty.all(4.0),
          radius: const Radius.circular(8),
          thumbColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            hoverColor: Theme.of(
              context,
            ).colorScheme.onSurface.withOpacity(0.1),
            splashFactory: InkRipple.splashFactory,
          ),
        ),
        sliderTheme: theme.sliderTheme.copyWith(
          activeTrackColor: Theme.of(context).colorScheme.onSurface,
          thumbColor: Theme.of(context).colorScheme.onSurface,
          inactiveTrackColor: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.3),
        ),
      ),
      i18n: const I18n(
        cancel: '취소',
        undo: '되돌리기',
        redo: '다시하기',
        done: '완료',
        remove: '삭제',
        doneLoadingMsg: '변경사항 적용 중...',
        importStateHistoryMsg: '에디터 초기화 중...',
      ),
      mainEditor: MainEditorConfigs(
        style: MainEditorStyle(
          appBarBackground: Theme.of(context).colorScheme.background,
          appBarColor: Theme.of(context).colorScheme.onSurface,
          bottomBarBackground: Theme.of(context).colorScheme.background,
          background: Theme.of(context).colorScheme.background,
        ),
        icons: MainEditorIcons(
          closeEditor: Icons.close,
          doneIcon: Icons.check,
          applyChanges: Icons.check_circle_outline,
          backButton: Icons.arrow_back_ios_new,
          undoAction: Icons.undo,
          redoAction: Icons.redo,
          removeElementZone: Icons.delete_outline,
        ),
      ),
      textEditor: TextEditorConfigs(
        customTextStyles: [GoogleFonts.roboto(), GoogleFonts.lato()],
        style: TextEditorStyle(
          appBarBackground: Theme.of(context).colorScheme.background,
          appBarColor: Theme.of(context).colorScheme.onSurface,
          bottomBarBackground: Theme.of(context).colorScheme.background,
          background: Colors.transparent,
        ),
        icons: const TextEditorIcons(
          bottomNavBar: Icons.title,
          backButton: Icons.arrow_back_ios_new,
          alignLeft: Icons.format_align_left,
          alignCenter: Icons.format_align_center,
          alignRight: Icons.format_align_right,
          backgroundMode: Icons.square,
          fontScale: Icons.text_increase,
          resetFontScale: Icons.restore,
        ),
      ),
      paintEditor: PaintEditorConfigs(
        style: PaintEditorStyle(
          appBarBackground: Theme.of(context).colorScheme.background,
          appBarColor: Theme.of(context).colorScheme.onSurface,
          bottomBarBackground: Theme.of(context).colorScheme.background,
          background: Theme.of(context).colorScheme.background,
          bottomBarActiveItemColor: Theme.of(context).colorScheme.onSurface,
          bottomBarInactiveItemColor: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.4),
        ),
        icons: PaintEditorIcons(
          backButton: Icons.arrow_back_ios_new,
          bottomNavBar: Icons.brush_outlined,
          lineWeight: Icons.line_weight_rounded,
          freeStyle: Icons.gesture,
          arrow: Icons.arrow_upward,
          line: Icons.remove,
          fill: Icons.format_color_fill,
          noFill: Icons.format_color_reset,
          rectangle: Icons.crop_square,
          circle: Icons.circle_outlined,
          dashLine: Icons.timeline,
        ),
      ),
      filterEditor: FilterEditorConfigs(
        style: FilterEditorStyle(
          appBarBackground: Theme.of(context).colorScheme.background,
          appBarColor: Theme.of(context).colorScheme.onSurface,
          background: Theme.of(context).colorScheme.background,
        ),
        icons: FilterEditorIcons(
          backButton: Icons.arrow_back_ios_new,
          bottomNavBar: Icons.auto_awesome,
        ),
      ),
      cropRotateEditor: CropRotateEditorConfigs(
        style: CropRotateEditorStyle(
          appBarBackground: Theme.of(context).colorScheme.background,
          appBarColor: Theme.of(context).colorScheme.onSurface,
          bottomBarBackground: Theme.of(context).colorScheme.background,
          background: Theme.of(context).colorScheme.background,
          cropCornerColor: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.4),
          helperLineColor: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.4),
        ),
        icons: CropRotateEditorIcons(
          bottomNavBar: Icons.crop,
          rotate: Icons.rotate_left,
          aspectRatio: Icons.aspect_ratio,
          flip: Icons.flip,
          reset: Icons.restart_alt,
        ),
      ),
      tuneEditor: TuneEditorConfigs(
        style: TuneEditorStyle(
          appBarBackground: Theme.of(context).colorScheme.background,
          appBarColor: Theme.of(context).colorScheme.onSurface,
          bottomBarBackground: Theme.of(context).colorScheme.background,
          background: Theme.of(context).colorScheme.background,
          bottomBarActiveItemColor: Theme.of(context).colorScheme.onSurface,
          bottomBarInactiveItemColor: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.4),
        ),
        icons: TuneEditorIcons(
          backButton: Icons.arrow_back_ios_new,
          bottomNavBar: Icons.tune,
        ),
      ),

      blurEditor: BlurEditorConfigs(
        style: BlurEditorStyle(
          appBarBackgroundColor: Theme.of(context).colorScheme.background,
          appBarForegroundColor: Theme.of(context).colorScheme.onSurface,

          background: Theme.of(context).colorScheme.background,
        ),
        icons: BlurEditorIcons(
          backButton: Icons.arrow_back_ios_new,
          bottomNavBar: Icons.blur_on_outlined,
        ),
      ),
    );

    return ProImageEditor.memory(
      imageBytes,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (Uint8List bytes) async {
          // 편집 완료 시 NodeComponentService에 반영
          if (selectedId != null) {
            nodeService.applyEditedBytes(nodeId: selectedId, bytes: bytes);
          }
          Navigator.pop(context, bytes);
        },
      ),
      configs: configs,
    );
  }
}

/// 헬퍼: 에디터를 열고 결과 바이트를 돌려받는다. (취소 시 null)
Future<Uint8List?> openImageEditorPlus(
  BuildContext context, {
  required Uint8List imageBytes,
}) async {
  final edited = await Navigator.push<Uint8List?>(
    context,
    MaterialPageRoute(
      builder: (context) => CustomImageEditorScreen(imageBytes: imageBytes),
      fullscreenDialog: true,
    ),
  );
  return edited;
}
