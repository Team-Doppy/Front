import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:flutter_drawing_board/paint_contents.dart';

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

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // flutter_drawing_board
  final DrawingController _drawingController = DrawingController();

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
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // 초기 도구/스타일 세팅 (펜)
    _eraser = false;
    try {
      _drawingController.setPaintContent(SimpleLine());
    } catch (_) {}
    _applyStyle();

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _drawingController.dispose();
    super.dispose();
  }

  void _applyStyle() {
    _drawingController.setStyle(
      color: _color,
      strokeWidth: _width,
      isAntiAlias: true,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
      style: PaintingStyle.stroke,
      blendMode: _eraser ? BlendMode.clear : BlendMode.srcOver,
    );
  }

  void _applyPenTool() {
    _eraser = false;
    try {
      _drawingController.setPaintContent(SimpleLine());
    } catch (_) {}
  }

  void _applyEraserTool() {
    _eraser = true;
    try {
      _drawingController.setPaintContent(Eraser());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 하단 툴바를 가리기 위해 불투명한 배경 사용
    final bgColor =
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF121212)
            : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bgColor,

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
                    background: Container(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      color: bgColor, // Scaffold와 같은 배경색
                    ),
                    showDefaultActions: false,
                    showDefaultTools: false,
                  );
                },
              ),
            ),
          ),

          // 상단 툴바
          Positioned(
            top: 45,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.background,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.4),
                        size: 23,
                      ),
                      style: IconButton.styleFrom(),
                    ),
                    const SizedBox(width: 5),

                    GestureDetector(
                      onTap: _undo,
                      child: SvgPicture.asset(
                        'assets/icons/editor_undo.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    GestureDetector(
                      onTap: _redo,
                      child: SvgPicture.asset(
                        'assets/icons/editor_redo.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _export,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        '완료',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
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
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _svgToolButton(
                            'assets/icons/pen.svg',
                            active: !_eraser, // 지우개가 아니면 펜 모드
                            onTap: () {
                              setState(() {
                                _applyPenTool();
                                _applyStyle();
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
                                _applyEraserTool();
                                _applyStyle();
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
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedRow() {
    switch (_menu) {
      case _Menu.color:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: _palette
              .map((c) {
                final isSelected = _color == c && !_eraser;
                // 밝은 색상인지 판단 (체크 표시 색상 결정용)
                final isLightColor = c.computeLuminance() > 0.5;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _color = c;
                      _eraser = false;
                      _applyStyle();
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
                  _applyPenTool();
                  try {
                    _drawingController.setPaintContent(SimpleLine());
                  } catch (_) {}
                  _applyStyle();
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
                  _applyPenTool();
                  try {
                    _drawingController.setPaintContent(SmoothLine());
                  } catch (_) {}
                  _applyStyle();
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
                  _applyPenTool();
                  try {
                    _drawingController.setPaintContent(StraightLine());
                  } catch (_) {}
                  _applyStyle();
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

  void _undo() => _drawingController.undo();
  void _redo() => _drawingController.redo();

  // 색상 버튼 (선택된 색상을 표시)
  Widget _buildColorButton() {
    final active = _menu == _Menu.color;
    return GestureDetector(
      onTap: () => _toggleMenu(_Menu.color),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              active
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.22)
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              active
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.22)
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
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
    // 1) JSON 추출 (벡터)
    final jsonList = _drawingController.getJsonList();
    final strokesData = _convertJsonToStrokes(jsonList);
    debugPrint(
      '[DrawingOverlay] export: json=${jsonList.length}, strokes=${strokesData.length}',
    );

    // 2) 바운딩 박스 계산
    Rect? bounds = _computeStrokeBoundsFromStrokes(strokesData);

    // 3) 바운드가 없으면 PNG로 폴백
    if (bounds == null) {
      try {
        final data = await _drawingController.getImageData();
        if (data != null) {
          // 보드 전체를 하나의 이미지 스티커로 등록 (좌표는 (0,0) 가정)
          bounds = Rect.fromLTWH(
            0,
            0,
            MediaQuery.of(context).size.width,
            MediaQuery.of(context).size.height,
          );
        }
      } catch (_) {}
    }

    if (bounds == null) return;

    final double scrollY = widget.scrollController?.offset ?? 0.0;
    final position = Offset(bounds.left, bounds.top + scrollY);
    debugPrint(
      '[DrawingOverlay] export: bounds=$bounds, scrollY=$scrollY, docPos=$position',
    );
    if (strokesData.isEmpty) {
      debugPrint('[DrawingOverlay] export: skip (empty strokes)');
      return;
    }

    // 스트로크를 공간적으로 그룹화 (떨어진 그림을 각각 스티커로)
    final groups = _groupStrokesByProximity(strokesData);
    debugPrint('[DrawingOverlay] export: ${groups.length} groups created');

    // 각 그룹을 개별 스티커로 생성
    for (int idx = 0; idx < groups.length; idx++) {
      final group = groups[idx];
      final groupBounds = _computeStrokeBoundsFromStrokes(group);
      if (groupBounds != null) {
        final groupPos = Offset(groupBounds.left, groupBounds.top + scrollY);
        // groupIndex 전달하여 고유 ID 보장
        widget.onSubmitDrawing(group, groupPos, groupIndex: idx);
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  // 스트로크를 공간적 근접도로 그룹화
  List<List<Map<String, dynamic>>> _groupStrokesByProximity(
    List<Map<String, dynamic>> strokes,
  ) {
    if (strokes.isEmpty) return [];
    if (strokes.length == 1) return [strokes];

    final List<List<Map<String, dynamic>>> groups = [];
    final List<bool> assigned = List.filled(strokes.length, false);

    for (int i = 0; i < strokes.length; i++) {
      if (assigned[i]) continue;

      final group = <Map<String, dynamic>>[strokes[i]];
      assigned[i] = true;

      // 이 스트로크와 가까운 다른 스트로크들을 찾기
      final bounds1 = _getStrokeBounds(strokes[i]);
      if (bounds1 == null) continue;

      for (int j = i + 1; j < strokes.length; j++) {
        if (assigned[j]) continue;

        final bounds2 = _getStrokeBounds(strokes[j]);
        if (bounds2 == null) continue;

        // 두 스트로크의 거리 계산 (바운딩 박스 중심 기준)
        final dist = (bounds1.center - bounds2.center).distance;

        // 100px 이내면 같은 그룹으로 간주
        if (dist < 100) {
          group.add(strokes[j]);
          assigned[j] = true;
        }
      }

      groups.add(group);
    }

    return groups;
  }

  Rect? _getStrokeBounds(Map<String, dynamic> stroke) {
    final points = stroke['points'] as List?;
    if (points == null || points.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final p in points) {
      if (p is! Map) continue;
      final x = (p['x'] as num?)?.toDouble();
      final y = (p['y'] as num?)?.toDouble();
      if (x == null || y == null) continue;

      minX = minX < x ? minX : x;
      minY = minY < y ? minY : y;
      maxX = maxX > x ? maxX : x;
      maxY = maxY > y ? maxY : y;
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  List<Map<String, dynamic>> _convertJsonToStrokes(List<dynamic> jsonList) {
    final List<Map<String, dynamic>> out = [];
    for (final item in jsonList) {
      try {
        final map = (item as Map).cast<String, dynamic>();
        final type = (map['type'] ?? '').toString();
        final paint = (map['paint'] as Map?)?.cast<String, dynamic>() ?? {};
        final double width = (paint['strokeWidth'] as num?)?.toDouble() ?? 8.0;
        final int colorVal = (paint['color'] as int?) ?? 0xFFFFFFFF;
        final String colorHex =
            '#${colorVal.toRadixString(16).padLeft(8, '0').toUpperCase()}';
        final bool isEraser =
            type == 'Eraser' ||
            (paint['blendMode'] != null &&
                paint['blendMode'] == BlendMode.clear.index);

        List<Offset> points = [];
        // 1) flutter_drawing_board 포맷: path(List|Map) 우선 파싱
        final dynamic pathData = map['path'];
        if (pathData is List) {
          for (final p in pathData) {
            if (p is Map) {
              final mp = p.cast<String, dynamic>();
              final double? dx =
                  (mp['dx'] as num?)?.toDouble() ??
                  (mp['x'] as num?)?.toDouble();
              final double? dy =
                  (mp['dy'] as num?)?.toDouble() ??
                  (mp['y'] as num?)?.toDouble();
              if (dx != null && dy != null) points.add(Offset(dx, dy));
            } else if (p is List) {
              if (p.length >= 2 && p[0] is num && p[1] is num) {
                points.add(
                  Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
                );
              }
            }
          }
        } else if (pathData is Map && pathData['points'] is List) {
          for (final p in (pathData['points'] as List)) {
            if (p is Map) {
              final mp = p.cast<String, dynamic>();
              final double? dx =
                  (mp['dx'] as num?)?.toDouble() ??
                  (mp['x'] as num?)?.toDouble();
              final double? dy =
                  (mp['dy'] as num?)?.toDouble() ??
                  (mp['y'] as num?)?.toDouble();
              if (dx != null && dy != null) points.add(Offset(dx, dy));
            }
          }
        } else if (pathData is Map && pathData['steps'] is List) {
          // flutter_drawing_board Path 직렬화: steps 기반 (moveTo/lineTo/relative*)
          Offset current = Offset.zero;
          bool hasCurrent = false;
          for (final step in (pathData['steps'] as List)) {
            if (step is! Map) continue;
            final m = step.cast<String, dynamic>();
            final String op =
                (m['type'] ?? m['op'] ?? m['name'] ?? '').toString();
            double? x = (m['x'] as num?)?.toDouble();
            double? y = (m['y'] as num?)?.toDouble();
            final double? dx = (m['dx'] as num?)?.toDouble();
            final double? dy = (m['dy'] as num?)?.toDouble();

            if (op == 'moveTo' || op == 'M') {
              if (x != null && y != null) {
                current = Offset(x, y);
                points.add(current);
                hasCurrent = true;
              }
              continue;
            }
            if (op == 'relativeMoveTo' || op == 'm') {
              if (dx != null && dy != null) {
                current =
                    hasCurrent ? current + Offset(dx, dy) : Offset(dx, dy);
                points.add(current);
                hasCurrent = true;
              }
              continue;
            }
            if (op == 'lineTo' || op == 'L') {
              if (x != null && y != null) {
                current = Offset(x, y);
                points.add(current);
                hasCurrent = true;
              }
              continue;
            }
            if (op == 'relativeLineTo' || op == 'l') {
              if (dx != null && dy != null) {
                current =
                    hasCurrent ? current + Offset(dx, dy) : Offset(dx, dy);
                points.add(current);
                hasCurrent = true;
              }
              continue;
            }
            // 기타 곡선류: 종점(x,y) 또는 상대(dx,dy)만 취득
            if (x != null && y != null) {
              current = Offset(x, y);
              points.add(current);
              hasCurrent = true;
            } else if (dx != null && dy != null) {
              current = hasCurrent ? current + Offset(dx, dy) : Offset(dx, dy);
              points.add(current);
              hasCurrent = true;
            }
          }
        }

        // 2) 과거 포맷: points(List)
        if (points.isEmpty && map['points'] is List) {
          for (final p in (map['points'] as List)) {
            final mp = (p as Map).cast<String, dynamic>();
            final double? dx =
                (mp['dx'] as num?)?.toDouble() ?? (mp['x'] as num?)?.toDouble();
            final double? dy =
                (mp['dy'] as num?)?.toDouble() ?? (mp['y'] as num?)?.toDouble();
            if (dx != null && dy != null) points.add(Offset(dx, dy));
          }
        }

        // 3) 도형 계열 호환 (startPoint/endPoint, A/B/C 등)
        if (points.isEmpty &&
            map['startPoint'] != null &&
            map['endPoint'] != null) {
          final sp = (map['startPoint'] as Map).cast<String, dynamic>();
          final ep = (map['endPoint'] as Map).cast<String, dynamic>();
          points.add(
            Offset((sp['dx'] as num).toDouble(), (sp['dy'] as num).toDouble()),
          );
          points.add(
            Offset((ep['dx'] as num).toDouble(), (ep['dy'] as num).toDouble()),
          );
        } else if (points.isEmpty &&
            map.containsKey('A') &&
            map.containsKey('B') &&
            map.containsKey('C')) {
          final a = (map['A'] as Map).cast<String, dynamic>();
          final b = (map['B'] as Map).cast<String, dynamic>();
          final c = (map['C'] as Map).cast<String, dynamic>();
          points.add(
            Offset((a['dx'] as num).toDouble(), (a['dy'] as num).toDouble()),
          );
          points.add(
            Offset((b['dx'] as num).toDouble(), (b['dy'] as num).toDouble()),
          );
          points.add(
            Offset((c['dx'] as num).toDouble(), (c['dy'] as num).toDouble()),
          );
        }

        if (points.isEmpty) {
          try {
            final pd = map['path'];
            debugPrint(
              '[DrawingOverlay] points 파싱 실패: type=$type, path.runtimeType=${pd.runtimeType}, sample=${pd is String
                  ? (pd.length > 120 ? pd.substring(0, 120) + '...' : pd)
                  : pd is Map
                  ? (pd.keys.toList())
                  : pd is List
                  ? (pd.isNotEmpty ? pd.first.runtimeType : '[]')
                  : 'null'}',
            );
          } catch (_) {}
          continue;
        }

        out.add({
          'points': points
              .map((p) => {'x': p.dx, 'y': p.dy})
              .toList(growable: false),
          'color': colorHex,
          'width': width,
          'erase': isEraser,
        });
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  Rect? _computeStrokeBoundsFromStrokes(List<Map<String, dynamic>> strokes) {
    if (strokes.isEmpty) return null;
    double? minX, minY, maxX, maxY;
    for (final s in strokes) {
      final pts = (s['points'] as List).cast<Map<String, dynamic>>();
      final w = (s['width'] as num?)?.toDouble() ?? 8.0;
      final half = w / 2;
      for (final p in pts) {
        final x = (p['x'] as num).toDouble();
        final y = (p['y'] as num).toDouble();
        final x1 = x - half;
        final y1 = y - half;
        final x2 = x + half;
        final y2 = y + half;
        minX = (minX == null) ? x1 : (x1 < minX ? x1 : minX);
        minY = (minY == null) ? y1 : (y1 < minY ? y1 : minY);
        maxX = (maxX == null) ? x2 : (x2 > maxX ? x2 : maxX);
        maxY = (maxY == null) ? y2 : (y2 > maxY ? y2 : maxY);
      }
    }
    if (minX == null || minY == null || maxX == null || maxY == null)
      return null;
    const double pad = 0.5;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }
}
