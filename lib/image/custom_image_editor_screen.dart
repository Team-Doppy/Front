import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:doppy/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:provider/provider.dart';

// Services
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/l10n/app_localizations.dart';

/// pro_image_editor 패키지 기반의 이미지 편집 화면
/// 최소 설정으로 시작하여 점진적으로 확장
class CustomImageEditorScreen extends StatefulWidget {
  const CustomImageEditorScreen({
    super.key,
    this.imageBytes,
    this.imageBytesList,
    this.onApplyChanges,
  }) : assert(
         imageBytes != null || imageBytesList != null,
         'imageBytes 또는 imageBytesList 중 하나는 필수입니다.',
       );

  final Uint8List? imageBytes;
  final List<Uint8List>? imageBytesList;

  /// 편집 완료 시 업로드 및 노드 교체를 처리하는 콜백
  /// 반환값: true면 성공, false면 실패/타임아웃
  final Future<bool> Function(Uint8List bytes)? onApplyChanges;

  @override
  State<CustomImageEditorScreen> createState() =>
      _CustomImageEditorScreenState();
}

class _CustomImageEditorScreenState extends State<CustomImageEditorScreen> {
  late final List<Uint8List> _images;
  late final PageController _pageController;
  int _currentIndex = 0;
  final Map<int, Uint8List> _editedImages = {}; // 편집된 이미지 저장

  @override
  void initState() {
    super.initState();
    // 단일 이미지 또는 다중 이미지 처리
    if (widget.imageBytesList != null && widget.imageBytesList!.isNotEmpty) {
      _images = List.from(widget.imageBytesList!);
    } else if (widget.imageBytes != null) {
      _images = [widget.imageBytes!];
    } else {
      _images = [];
    }
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isMultiImage => _images.length > 1;

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onImageEdited(int index, Uint8List editedBytes) {
    setState(() {
      _editedImages[index] = editedBytes;
    });
  }

  void _handleDone() {
    // 편집된 이미지가 있으면 그것을, 없으면 원본을 반환
    final List<Uint8List> result = [];
    for (int i = 0; i < _images.length; i++) {
      result.add(_editedImages[i] ?? _images[i]);
    }
    // 단일 이미지인 경우 Uint8List 반환, 다중 이미지인 경우 List<Uint8List> 반환
    if (result.length == 1) {
      Navigator.pop(context, result.first);
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodeService = context.read<NodeComponentService>();
    final selectedId = nodeService.selectedImageId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Theme.of(context).colorScheme.background,
        brightness: Theme.of(context).brightness,
      ),
      useMaterial3: true,
    );

    // 테마에 따른 색상 설정
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final barBgColor =
        isDark
            ? AppColors.darkBackground.withOpacity(0.9)
            : AppColors.lightBackground.withOpacity(0.95);

    final configs = ProImageEditorConfigs(
      designMode:
          Platform.isIOS
              ? ImageEditorDesignMode.cupertino
              : ImageEditorDesignMode.material,
      theme: theme.copyWith(
        // 🎯 로딩 다이얼로그 텍스트 색상 (짙은 회색)
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey[700], // 🎯 짙은 회색
          ),
        ),
        // 🎯 로딩 인디케이터 색상
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: Theme.of(context).colorScheme.primary, // 🎯 Primary 색상
        ),
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
      i18n: I18n(
        cancel: AppLocalizations.of(context).t('cancel'),
        undo: '되돌리기',
        redo: '다시하기',
        done: AppLocalizations.of(context).t('done'),
        remove: AppLocalizations.of(context).t('delete'),
        doneLoadingMsg: AppLocalizations.of(
          context,
        ).t('applying_changes'), // 🎯 텍스트 없이 스피너만 표시
        importStateHistoryMsg: AppLocalizations.of(context).t('loading_image'),
      ),
      mainEditor: MainEditorConfigs(
        style: MainEditorStyle(
          appBarBackground: barBgColor,
          appBarColor: fgColor,
          bottomBarBackground: barBgColor,
          bottomBarColor: fgColor,
          background: bgColor,
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
          appBarBackground: barBgColor,
          appBarColor: fgColor,
          bottomBarBackground: barBgColor,
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
          appBarBackground: barBgColor,
          appBarColor: fgColor,
          bottomBarBackground: barBgColor,
          background: bgColor,
          bottomBarActiveItemColor: fgColor,
          bottomBarInactiveItemColor: fgColor.withOpacity(0.5),
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
          appBarBackground: barBgColor,
          appBarColor: fgColor,
          background: bgColor,
        ),
        icons: FilterEditorIcons(
          backButton: Icons.arrow_back_ios_new,
          bottomNavBar: Icons.auto_awesome,
        ),
      ),
      cropRotateEditor: CropRotateEditorConfigs(
        style: CropRotateEditorStyle(
          appBarBackground: barBgColor, // 🎯 bgColor와 일치
          appBarColor: fgColor, // 🎯 fgColor와 일치
          bottomBarBackground: barBgColor, // 🎯 bgColor와 일치
          background: bgColor, // 🎯 bgColor로 통일
          cropCornerColor:
              Theme.of(context).colorScheme.primary, // 🎯 Primary 색상
          helperLineColor: Theme.of(
            context,
          ).colorScheme.primary.withOpacity(0.6), // 🎯 Primary 색상 (반투명)
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
          appBarBackground: barBgColor, // 🎯 bgColor와 일치
          appBarColor: fgColor, // 🎯 fgColor와 일치
          bottomBarBackground: barBgColor, // 🎯 bgColor와 일치
          background: bgColor, // 🎯 bgColor로 통일
          bottomBarActiveItemColor: fgColor, // 🎯 fgColor와 일치
          bottomBarInactiveItemColor: fgColor.withOpacity(
            0.4,
          ), // 🎯 fgColor와 일치
        ),
        icons: TuneEditorIcons(
          backButton: Icons.arrow_back_ios_new,
          bottomNavBar: Icons.tune,
        ),
      ),

      blurEditor: BlurEditorConfigs(
        style: BlurEditorStyle(
          appBarBackgroundColor: barBgColor,
          appBarForegroundColor: fgColor,
          background: bgColor,
        ),
        icons: BlurEditorIcons(
          backButton: Icons.arrow_back_ios_new,
          bottomNavBar: Icons.blur_on_outlined,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        top: false,
        bottom: false,
        child:
            _isMultiImage
                ? _buildMultiImageEditor(
                  context,
                  configs,
                  nodeService,
                  selectedId,
                )
                : _buildSingleImageEditor(
                  context,
                  configs,
                  nodeService,
                  selectedId,
                  _images[0],
                ),
      ),
    );
  }

  Widget _buildSingleImageEditor(
    BuildContext context,
    ProImageEditorConfigs configs,
    NodeComponentService nodeService,
    String? selectedId,
    Uint8List imageBytes,
  ) {
    return ProImageEditor.memory(
      imageBytes,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (Uint8List bytes) async {
          if (widget.onApplyChanges != null) {
            try {
              // 업로드 및 노드 교체 처리 (타임아웃 포함)
              final success = await widget.onApplyChanges!(bytes).timeout(
                const Duration(seconds: 30),
                onTimeout: () {
                  debugPrint('[CustomImageEditorScreen] 변경사항 반영 타임아웃 (30초)');
                  return false;
                },
              );

              // 🎯 로딩 다이얼로그만 닫기 (ProImageEditor가 알아서 편집기를 닫음)
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }

              // 🎯 편집기 닫기는 ProImageEditor가 알아서 함 (pop 제거)
              debugPrint(
                '[CustomImageEditorScreen] ✅ 변경사항 반영 완료: success=$success',
              );
            } catch (e) {
              debugPrint('[CustomImageEditorScreen] 변경사항 반영 중 오류: $e');

              // 로딩 다이얼로그만 닫기
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }

              // 🎯 편집기 닫기는 ProImageEditor가 알아서 함 (pop 제거)
            }
          } else {
            // 콜백이 없으면 기존 동작 (편집된 바이트만 반환)
            if (selectedId != null) {
              nodeService.applyEditedBytes(nodeId: selectedId, bytes: bytes);
            }
            // 🎯 ProImageEditor가 알아서 pop을 실행하므로 여기서는 하지 않음
          }
        },
      ),
      configs: configs,
    );
  }

  Widget _buildMultiImageEditor(
    BuildContext context,
    ProImageEditorConfigs configs,
    NodeComponentService nodeService,
    String? selectedId,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final barBgColor =
        isDark
            ? AppColors.darkBackground.withOpacity(0.9)
            : AppColors.lightBackground.withOpacity(0.95);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: barBgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: fgColor),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          '${_currentIndex + 1} / ${_images.length}',
          style: TextStyle(
            color: fgColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _handleDone,
            child: Text(
              '완료',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: _images.length,
        itemBuilder: (context, index) {
          // 각 이미지별로 독립적인 편집 상태 관리
          return _SingleImageEditorWrapper(
            imageBytes: _editedImages[index] ?? _images[index],
            configs: configs,
            onImageEdited: (bytes) {
              _onImageEdited(index, bytes);
            },
          );
        },
      ),
    );
  }
}

/// 단일 이미지 편집 래퍼 (다중 이미지 편집에서 사용)
class _SingleImageEditorWrapper extends StatelessWidget {
  final Uint8List imageBytes;
  final ProImageEditorConfigs configs;
  final Function(Uint8List) onImageEdited;

  const _SingleImageEditorWrapper({
    required this.imageBytes,
    required this.configs,
    required this.onImageEdited,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ProImageEditor.memory(
          imageBytes,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List bytes) async {
              // 편집 완료 시 현재 이미지만 저장 (자동으로 다음 이미지로 넘어가지 않음)
              onImageEdited(bytes);
            },
          ),
          configs: configs,
        ),
        // ProImageEditor의 내장 앱바를 가리는 오버레이
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.of(context).padding.top + kToolbarHeight,
          child: Container(
            color: Colors.transparent,
            // 터치 이벤트를 막아서 ProImageEditor의 앱바 버튼이 작동하지 않도록 함
            child: GestureDetector(
              onTap: () {}, // 빈 핸들러로 터치 이벤트 소비
              behavior: HitTestBehavior.opaque,
            ),
          ),
        ),
      ],
    );
  }
}

// 중복 클릭 방지를 위한 전역 플래그
bool _isImageEditorOpening = false;

/// 헬퍼: 에디터를 열고 결과 바이트를 돌려받는다. (취소 시 null)
/// 네트워크 이미지 로딩 중 로딩 인디케이터를 표시하고 중복 클릭을 방지합니다.
Future<Uint8List?> openImageEditorPlus(
  BuildContext context, {
  required Uint8List imageBytes,
}) async {
  if (_isImageEditorOpening) {
    debugPrint('[ImageEditor] 이미 열리는 중입니다. 중복 클릭 무시됨.');
    return null;
  }

  _isImageEditorOpening = true;

  try {
    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('loading_image'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // 최소 로딩 시간 보장 (너무 빠르게 깜빡이는 것 방지)
    await Future.delayed(const Duration(milliseconds: 300));

    // 로딩 다이얼로그 닫기
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    // 에디터 열기
    final edited = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomImageEditorScreen(imageBytes: imageBytes),
        fullscreenDialog: true,
      ),
    );

    return edited;
  } catch (e) {
    debugPrint('[ImageEditor] 에러 발생: $e');
    // 에러 발생 시 로딩 다이얼로그 닫기
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    return null;
  } finally {
    _isImageEditorOpening = false;
  }
}
