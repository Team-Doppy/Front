import 'dart:typed_data';
import 'dart:ui';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:flutter_drawing_board/paint_contents.dart';
import 'package:image/image.dart' as img;

// 확장 메뉴 종류(전역)
enum _Menu { none, pen, eraser, color }

// 펜 타입
enum _PenType { simple, smooth, straight }

class DrawingOverlay extends StatefulWidget {
  final void Function(
    List<Map<String, dynamic>> strokes,
    Offset position, {
    int? groupIndex,
  })
  onSubmitDrawing;
  final List<Map<String, dynamic>>? initialStrokes;
  final ScrollController? scrollController;

  const DrawingOverlay({
    required this.onSubmitDrawing,
    this.initialStrokes,
    this.scrollController,
  });

  @override
  State<DrawingOverlay> createState() => _DrawingOverlayState();
}

class _DrawingOverlayState extends State<DrawingOverlay>
    with SingleTickerProviderStateMixin {
  final GlobalKey _canvasKey = GlobalKey();
  Color _color = Colors.red; // 초기 펜 컬러를 눈에 띄는 빨강으로 설정
  double _width = 8;
  bool _eraser = false;
  bool _isAdjustingWidth = false; // 펜 두께 조절 중 여부
  bool _isUploading = false; // 업로드 중 여부
  bool _hasDrawing = false; // 그림이 그려졌는지 여부

  late AnimationController _animationController;

  // flutter_drawing_board (🎯 late로 변경하여 initState에서 초기화)
  late DrawingController _drawingController;

  // 확장 메뉴 상태
  _Menu _menu = _Menu.none;
  _PenType _penType = _PenType.simple; // 현재 선택된 펜 타입

  final List<Color> _palette = const [
    Colors.red,
    Colors.black,
    Colors.white,
    Color(0xFFFF6B6B),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFFB565D8),
    Color(0xFFFF8ED4),
    Color(0xFFFF9F45),
  ];

  void _toggleMenu(_Menu m) {
    setState(() {
      _menu = (_menu == m) ? _Menu.none : m;
    });
  }

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // 🎯 DrawingController를 새로 생성 (완전히 깨끗한 상태로 시작)
    _drawingController = DrawingController();
    debugPrint('[DrawingOverlay] DrawingController 새로 생성');

    // 🎯 DrawingController 변경 감지 리스너 추가
    _drawingController.addListener(_onDrawingChanged);

    // 🔍 BlendMode enum 값 확인
    debugPrint(
      '[DrawingOverlay] BlendMode.srcOver.index = ${BlendMode.srcOver.index}',
    );
    debugPrint(
      '[DrawingOverlay] BlendMode.clear.index = ${BlendMode.clear.index}',
    );

    // 초기 도구/스타일 세팅 (펜)
    _eraser = false;
    try {
      _drawingController.setPaintContent(SimpleLine());
    } catch (_) {}
    _applyStyle();

    // 🔍 디버깅: 초기화 후 상태 확인
    debugPrint(
      '[DrawingOverlay] 초기화 완료: _eraser=$_eraser, _color=$_color, _width=$_width, blendMode=srcOver',
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _drawingController.removeListener(_onDrawingChanged);
    _animationController.dispose();
    _drawingController.dispose();
    super.dispose();
  }

  // 🎯 그림 변경 감지 (undo/redo 버튼 상태도 업데이트)
  void _onDrawingChanged() {
    final jsonList = _drawingController.getJsonList();
    final hasContent = jsonList.isNotEmpty;
    // 🎯 항상 setState 호출하여 undo/redo 버튼 상태 업데이트
    setState(() {
      _hasDrawing = hasContent;
    });
  }

  void _applyStyle() {
    // 🎯 지우개 모드일 때는 투명색 + clear 블렌드 모드
    final effectiveColor = _eraser ? Colors.transparent : _color;
    final effectiveBlendMode = _eraser ? BlendMode.clear : BlendMode.srcOver;

    debugPrint(
      '[DrawingOverlay] _applyStyle 호출: _eraser=$_eraser, color=$effectiveColor, blendMode=$effectiveBlendMode',
    );

    _drawingController.setStyle(
      color: effectiveColor,
      strokeWidth: _width,
      isAntiAlias: true,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
      style: PaintingStyle.stroke,
      blendMode: effectiveBlendMode, // 🎯 지우개는 clear 모드
    );
  }

  void _applyPenTool() {
    debugPrint('[DrawingOverlay] 펜 모드로 전환');
    _eraser = false;
    try {
      _drawingController.setPaintContent(SimpleLine());
    } catch (_) {}
    _applyStyle(); // 🎯 펜 모드로 전환 시 즉시 스타일 적용
    debugPrint('[DrawingOverlay] 펜 모드 적용 완료: blendMode=srcOver');
  }

  void _applyEraserTool() {
    debugPrint('[DrawingOverlay] 지우개 모드로 전환 (투명하게 지우기)');
    _eraser = true;
    try {
      _drawingController.setPaintContent(Eraser()); // 🎯 진짜 지우개 사용
    } catch (_) {}
    _applyStyle(); // 🎯 투명색 + BlendMode.clear 적용
    debugPrint('[DrawingOverlay] 지우개 모드 적용 완료: BlendMode.clear');
  }

  @override
  Widget build(BuildContext context) {
    // 하단 툴바를 가리기 위해 불투명한 배경 사용

    return Scaffold(
      backgroundColor: Colors.transparent,

      body: Stack(
        children: [
          // 드로잉 보드
          Positioned.fill(
            child: RepaintBoundary(
              key: _canvasKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return DrawingBoard(
                    controller: _drawingController,
                    background: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      // 🎯 color 없음 = 진짜 투명 배경
                    ),
                    showDefaultActions: false,
                    showDefaultTools: false,
                  );
                },
              ),
            ),
          ),

          // 상단 툴바 (EditorAppBar와 동일한 스타일)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Theme.of(context).colorScheme.background.withOpacity(1),
              child: SafeArea(
                bottom: false,
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(1),
                      ),
                      height: kToolbarHeight,
                      width: MediaQuery.of(context).size.width,
                      child: Row(
                        children: [
                          // 뒤로가기 버튼
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 24,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.75),
                              ),
                            ),
                          ),

                          // 언두 버튼
                          Material(
                            color: Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: InkWell(
                                onTap: _canUndo() ? _undo : null,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.all(1),
                                  child: SvgPicture.asset(
                                    'assets/icons/editor_undo.svg',
                                    width: 30,
                                    height: 30,
                                    colorFilter: ColorFilter.mode(
                                      Theme.of(context).colorScheme.onSurface
                                          .withOpacity(_canUndo() ? 0.6 : 0.15),
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 리두 버튼
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _canRedo() ? _redo : null,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.all(1),
                                  child: SvgPicture.asset(
                                    'assets/icons/editor_redo.svg',
                                    width: 30,
                                    height: 30,
                                    colorFilter: ColorFilter.mode(
                                      Theme.of(context).colorScheme.onSurface
                                          .withOpacity(_canRedo() ? 0.6 : 0.15),
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),

                          // 완료 버튼
                          GestureDetector(
                            onTap:
                                (_isUploading || !_hasDrawing) ? null : _export,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child:
                                  _isUploading
                                      ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                        ),
                                      )
                                      : Text(
                                        AppLocalizations.of(
                                          context,
                                        ).t('complete'),
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface.withOpacity(
                                            _hasDrawing ? 0.9 : 0.3,
                                          ),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 좌측 세로 펜 두께 슬라이더
          Positioned(
            left: 0,
            top: MediaQuery.of(context).size.height * 0.3,
            bottom: MediaQuery.of(context).size.height * 0.3,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(
                _isAdjustingWidth ? 0 : -20,
                0,
                0,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: _isAdjustingWidth ? 60 : 54,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isAdjustingWidth)
                          Text(
                            '${_width.round()}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: -1,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 6,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 16,
                                ),
                              ),
                              child: Slider(
                                activeColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.9),
                                inactiveColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.2),
                                min: 1,
                                max: 30,
                                value: _width.clamp(1.0, 30.0),
                                onChangeStart: (v) {
                                  setState(() => _isAdjustingWidth = true);
                                },
                                onChanged: (v) {
                                  setState(() {
                                    _width = v.clamp(1.0, 30.0);
                                    _applyStyle();
                                  });
                                },
                                onChangeEnd: (v) {
                                  setState(() {
                                    _width = v.clamp(1.0, 30.0);
                                    _isAdjustingWidth = false;
                                    _applyStyle();
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 하단 툴바
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: MediaQuery.of(context).size.width,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 확장 영역
                    AnimatedSize(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      child:
                          (_menu == _Menu.none)
                              ? const SizedBox.shrink()
                              : Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: _buildExpandedRow(),
                              ),
                    ),
                    // 메인 툴바
                    Row(
                      children: [
                        _svgToolButton(
                          'assets/icons/pen.svg',
                          active: !_eraser, // 지우개가 아니면 펜 모드
                          onTap: () {
                            setState(() {
                              _applyPenTool(); // 이미 내부에서 _applyStyle() 호출
                            });
                            _toggleMenu(_Menu.pen);
                          },
                        ),
                        const SizedBox(width: 10),
                        _svgToolButton(
                          'assets/icons/eraser.svg',
                          active: _eraser, // 지우개 모드일 때만
                          onTap: () {
                            setState(() {
                              _applyEraserTool(); // 이미 내부에서 _applyStyle() 호출
                            });
                            _toggleMenu(_Menu.eraser);
                          },
                        ),
                        const SizedBox(width: 10),
                        _buildColorButton(),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedRow() {
    switch (_menu) {
      case _Menu.color:
        return Row(
          children: _palette
              .map((c) {
                final isSelected = _color == c && !_eraser;
                // 밝은 색상인지 판단 (체크 표시 색상 결정용)
                final isLightColor = c.computeLuminance() > 0.5;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _color = c;
                      _eraser = false; // 🎯 색상 선택 시 펜 모드로 전환
                      _applyStyle();
                      debugPrint('[DrawingOverlay] 색상 변경: $_color, 펜 모드로 전환');
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            isSelected
                                ? Colors
                                    .white // 선택된 색상은 흰색 테두리
                                : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.2),
                        width: isSelected ? 2.5 : 1.0, // 선택된 색상은 더 두꺼운 테두리
                      ),
                      color: c,
                    ),
                    // 선택된 색상에 체크 표시 추가 (밝은 색상은 검은색, 어두운 색상은 흰색)
                    child:
                        isSelected
                            ? Icon(
                              Icons.check,
                              color: isLightColor ? Colors.black : Colors.white,
                              size: 16,
                            )
                            : null,
                  ),
                );
              })
              .toList(growable: false),
        );
      case _Menu.pen:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip(
              'Simple',
              isSelected: _penType == _PenType.simple,
              onTap: () {
                setState(() {
                  _penType = _PenType.simple;
                  _eraser = false; // 🎯 명시적으로 펜 모드 설정
                  try {
                    _drawingController.setPaintContent(SimpleLine());
                  } catch (_) {}
                  _applyStyle(); // 🎯 스타일 적용
                });
              },
            ),
            const SizedBox(width: 6),
            _chip(
              'Smooth',
              isSelected: _penType == _PenType.smooth,
              onTap: () {
                setState(() {
                  _penType = _PenType.smooth;
                  _eraser = false; // 🎯 명시적으로 펜 모드 설정
                  try {
                    _drawingController.setPaintContent(SmoothLine());
                  } catch (_) {}
                  _applyStyle(); // 🎯 스타일 적용
                });
              },
            ),
            const SizedBox(width: 6),
            _chip(
              'Straight',
              isSelected: _penType == _PenType.straight,
              onTap: () {
                setState(() {
                  _penType = _PenType.straight;
                  _eraser = false; // 🎯 명시적으로 펜 모드 설정
                  try {
                    _drawingController.setPaintContent(StraightLine());
                  } catch (_) {}
                  _applyStyle(); // 🎯 스타일 적용
                });
              },
            ),
          ],
        );
      case _Menu.eraser:
      case _Menu.none:
        return const SizedBox.shrink();
    }
  }

  Widget _chip(
    String label, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        onTap(); // 원래 동작 실행
        setState(() => _menu = _Menu.none); // 메뉴 닫기
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(
                    0.45,
                  ) // 선택됨: 더 밝게
                  : Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.1), // 기본
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _undo() {
    _drawingController.undo();
    // 🎯 undo/redo 버튼 상태 업데이트를 위해 명시적으로 setState 호출
    setState(() {});
  }

  void _redo() {
    _drawingController.redo();
    // 🎯 undo/redo 버튼 상태 업데이트를 위해 명시적으로 setState 호출
    setState(() {});
  }

  // 🎯 Undo/Redo 가능 여부 확인
  bool _canUndo() {
    try {
      return _drawingController.currentIndex > 0;
    } catch (_) {
      return false;
    }
  }

  bool _canRedo() {
    try {
      final history = _drawingController.getHistory;
      return _drawingController.currentIndex < history.length;
    } catch (_) {
      return false;
    }
  }

  // 색상 버튼 (선택된 색상을 표시)
  Widget _buildColorButton() {
    final active = _menu == _Menu.color;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _toggleMenu(_Menu.color),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              active
                  ? (isDark
                      ? Colors.white.withOpacity(0.35) // 다크 모드: 더 밝은 회색
                      : Colors.black.withOpacity(0.25)) // 라이트 모드: 더 어두운 회색
                  : (isDark
                      ? Colors.white.withOpacity(0.10)
                      : Colors.black.withOpacity(0.08)),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.color_lens_outlined,
              color: active ? Colors.white : Colors.white.withOpacity(0.5),
              size: 24,
            ),
            // 선택된 색상을 작은 원으로 표시
            if (!_eraser)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _color,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _svgToolButton(
    String svgPath, {
    required bool active,
    required VoidCallback onTap,
    double? width,
    double? height,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              active
                  ? (isDark
                      ? Colors.white.withOpacity(0.35) // 다크 모드: 더 밝은 회색
                      : Colors.black.withOpacity(0.25)) // 라이트 모드: 더 어두운 회색
                  : (isDark
                      ? Colors.white.withOpacity(0.10)
                      : Colors.black.withOpacity(0.08)),
          borderRadius: BorderRadius.circular(30),
        ),
        child: SvgPicture.asset(
          svgPath,
          width: width ?? 24,
          height: height ?? 24,
          colorFilter: ColorFilter.mode(
            active ? Colors.white : Colors.white.withOpacity(0.5),
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    // 🎯 PNG 이미지로 추출 (지우개 정확하게 반영)
    setState(() => _isUploading = true);

    try {
      debugPrint('[DrawingOverlay] PNG 이미지 추출 시작');
      final byteData = await _drawingController.getImageData();

      if (byteData == null) {
        debugPrint('[DrawingOverlay] export: skip (null image data)');
        setState(() => _isUploading = false);
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // ByteData를 Uint8List로 변환
      final imageData = byteData.buffer.asUint8List();

      if (imageData.isEmpty) {
        debugPrint('[DrawingOverlay] export: skip (empty image data)');
        setState(() => _isUploading = false);
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // 🎯 실제 화면 크기 (MediaQuery)
      final screenWidth = MediaQuery.of(context).size.width.toInt();
      final screenHeight = MediaQuery.of(context).size.height.toInt();

      // 🎯 디바이스 픽셀 비율 (예: iPhone 3.0x)
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;

      final croppedResult = await _cropTransparentPixels(
        imageData,
        screenWidth,
        screenHeight,
      );

      if (croppedResult == null) {
        debugPrint('[DrawingOverlay] export: skip (크롭 실패 또는 빈 이미지)');
        setState(() => _isUploading = false);
        // 🎯 그림이 실제로 없으므로 화면 닫기
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final croppedImageData = croppedResult['imageData'] as Uint8List;
      final cropBounds = croppedResult['bounds'] as Rect;

      debugPrint(
        '[DrawingOverlay] 크롭 완료: ${croppedImageData.lengthInBytes} bytes, bounds=$cropBounds',
      );

      // 🎯 물리 픽셀 좌표를 논리 픽셀로 변환
      final logicalLeft = cropBounds.left / pixelRatio;
      final logicalTop = cropBounds.top / pixelRatio;
      final logicalWidth = cropBounds.width / pixelRatio;
      final logicalHeight = cropBounds.height / pixelRatio;

      final double scrollY = widget.scrollController?.offset ?? 0.0;
      // 🎯 DrawingOverlay는 전체 화면(상태바 포함) 기준 좌표로 크롭 bounds가 나온다.
      // 에디터의 스티커 캔버스는 Scaffold body(앱바 아래)를 (0,0)으로 사용하므로,
      // 상단 앱바 높이만큼 Y를 보정해서 body 로컬 좌표로 변환한 뒤, 문서 좌표로 만들기 위해 scrollY를 더한다.
      final double editorTopOffset =
          MediaQuery.paddingOf(context).top + kToolbarHeight;
      final double bodyLocalTop = (logicalTop - editorTopOffset).clamp(
        0.0,
        double.infinity,
      );
      final position = Offset(logicalLeft, bodyLocalTop + scrollY);

      debugPrint(
        '[DrawingOverlay] 📐 물리→논리 변환: ($cropBounds) → (${logicalLeft.toStringAsFixed(1)}, ${logicalTop.toStringAsFixed(1)}, ${logicalWidth.toStringAsFixed(1)}x${logicalHeight.toStringAsFixed(1)})',
      );
      debugPrint(
        '[DrawingOverlay] export: editorTopOffset=$editorTopOffset, scrollY=$scrollY, docPos=$position',
      );

      // 🎯 PNG를 서버에 업로드하고 URL 받기
      final uploadService = UploadService();
      final task = uploadService.enqueueBytes(
        croppedImageData,
        kind: UploadKind.editorImage,
        fileName: 'drawing_${DateTime.now().millisecondsSinceEpoch}.png',
      );

      debugPrint('[DrawingOverlay] 업로드 시작, 대기 중...');

      // 🎯 업로드 완료 대기
      await _waitForUpload(task);

      if (task.state == UploadState.success && task.url != null) {
        debugPrint('[DrawingOverlay] ✅ 업로드 완료: ${task.url}');

        // URL로 전달
        final pngStrokeWithUrl = {
          'type': 'png_image',
          'url': task.url!, // ✅ URL
          'width': logicalWidth,
          'height': logicalHeight,
        };

        widget.onSubmitDrawing([pngStrokeWithUrl], position, groupIndex: 0);

        if (mounted) Navigator.of(context).pop();
      } else {
        debugPrint('[DrawingOverlay] ❌ 업로드 실패');
        if (mounted) {
          setState(() => _isUploading = false);
          // 에러 표시 (선택사항)
        }
      }
    } catch (e) {
      debugPrint('[DrawingOverlay] PNG 추출/업로드 에러: $e');
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _waitForUpload(UploadTask task) async {
    // 업로드 완료 또는 실패까지 대기
    while (task.state != UploadState.success &&
        task.state != UploadState.failed &&
        task.state != UploadState.cancelled) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// PNG 이미지에서 투명한 부분 제거하고 크롭
  Future<Map<String, dynamic>?> _cropTransparentPixels(
    Uint8List pngBytes,
    int width,
    int height,
  ) async {
    try {
      // image 패키지로 디코딩
      final image = img.decodeImage(pngBytes);
      if (image == null) return null;

      debugPrint(
        '[DrawingOverlay] 🖼️ PNG 실제 크기: ${image.width}x${image.height}',
      );

      // 투명하지 않은 픽셀의 바운딩 박스 찾기
      int? minX, minY, maxX, maxY;

      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final alpha = pixel.a.toInt();

          // 완전히 투명하지 않은 픽셀 (alpha > 10)
          if (alpha > 10) {
            minX = (minX == null) ? x : (x < minX ? x : minX);
            minY = (minY == null) ? y : (y < minY ? y : minY);
            maxX = (maxX == null) ? x : (x > maxX ? x : maxX);
            maxY = (maxY == null) ? y : (y > maxY ? y : maxY);
          }
        }
      }

      // 드로잉이 없으면 (모두 투명)
      if (minX == null || minY == null || maxX == null || maxY == null) {
        debugPrint('[DrawingOverlay] 모든 픽셀이 투명함');
        return null;
      }

      // 약간의 패딩 추가 (잘리지 않도록)
      const padding = 2;
      minX = (minX - padding).clamp(0, image.width - 1);
      minY = (minY - padding).clamp(0, image.height - 1);
      maxX = (maxX + padding).clamp(0, image.width - 1);
      maxY = (maxY + padding).clamp(0, image.height - 1);

      final cropWidth = maxX - minX + 1;
      final cropHeight = maxY - minY + 1;

      debugPrint(
        '[DrawingOverlay] 바운딩 박스: x=$minX, y=$minY, w=$cropWidth, h=$cropHeight',
      );

      // 이미지 크롭
      final croppedImage = img.copyCrop(
        image,
        x: minX,
        y: minY,
        width: cropWidth,
        height: cropHeight,
      );

      // PNG로 인코딩 (리사이즈 안 함 = 최고 화질)
      final croppedBytes = img.encodePng(croppedImage, level: 6);

      return {
        'imageData': Uint8List.fromList(croppedBytes),
        'bounds': Rect.fromLTWH(
          minX.toDouble(),
          minY.toDouble(),
          cropWidth.toDouble(),
          cropHeight.toDouble(),
        ),
      };
    } catch (e) {
      debugPrint('[DrawingOverlay] 크롭 에러: $e');
      return null;
    }
  }
}
