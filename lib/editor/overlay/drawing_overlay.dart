import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class DrawingOverlay extends StatefulWidget {
  final void Function(List<Map<String, dynamic>> strokes, Offset position)
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
  final List<_Stroke> _strokes = <_Stroke>[];
  final List<_Stroke> _redo = <_Stroke>[];
  Color _color = Colors.white;
  double _width = 8;
  bool _eraser = false;
  bool _isAdjustingWidth = false; // 펜 두께 조절 중 여부

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 애니메이션 컨트롤러 초기화
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // 초기 스트로크 데이터가 있으면 로드
    if (widget.initialStrokes != null && widget.initialStrokes!.isNotEmpty) {
      _loadInitialStrokes(widget.initialStrokes!);
    }

    // 애니메이션 시작
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _loadInitialStrokes(List<Map<String, dynamic>> strokesData) {
    for (final strokeData in strokesData) {
      final points =
          (strokeData['points'] as List).cast<Map<String, dynamic>>();
      final colorHex = strokeData['color'] as String? ?? '#FFFFFFFF';
      final width = (strokeData['width'] as num?)?.toDouble() ?? 8.0;
      final erase = strokeData['erase'] as bool? ?? false;

      // Hex 색상 파싱
      final colorValue = int.parse(colorHex.replaceAll('#', ''), radix: 16);
      final color = Color(colorValue);

      final stroke = _Stroke(color: color, width: width, erase: erase);

      // 포인트를 글로벌 좌표로 변환 (상대 좌표 → 절대 좌표)
      for (final p in points) {
        final x = (p['x'] as num).toDouble();
        final y = (p['y'] as num).toDouble();
        stroke.points.add(Offset(x, y));
      }

      _strokes.add(stroke);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      body: Stack(
        children: [
          // 전체 화면 투명 캔버스
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (d) {
                _redo.clear();

                // 스크롤 오프셋 계산
                final scrollY =
                    widget.scrollController?.hasClients == true
                        ? widget.scrollController!.offset
                        : 0.0;

                // 앱바 높이 (50px) 제거 후 스크롤 오프셋 추가
                final adjustedPos = Offset(
                  d.position.dx,
                  d.position.dy - 50 + scrollY,
                );

                setState(() {
                  _strokes.add(
                    _Stroke(
                      color: _eraser ? Colors.black : _color,
                      width: _width,
                      erase: _eraser,
                    )..points.add(adjustedPos),
                  );
                });
              },
              onPointerMove: (d) {
                if (_strokes.isEmpty) return;

                // 스크롤 오프셋 계산
                final scrollY =
                    widget.scrollController?.hasClients == true
                        ? widget.scrollController!.offset
                        : 0.0;

                // 앱바 높이 (50px) 제거 후 스크롤 오프셋 추가
                final adjustedPos = Offset(
                  d.position.dx,
                  d.position.dy - 50 + scrollY,
                );

                setState(() {
                  _strokes.last.points.add(adjustedPos);
                });
              },
              child: RepaintBoundary(
                key: _canvasKey,
                child: CustomPaint(
                  painter: _DrawingPainter(
                    strokes: _strokes,
                    scale: 1.0,
                    pan: Offset.zero,
                    scrollY:
                        widget.scrollController?.hasClients == true
                            ? widget.scrollController!.offset
                            : 0.0,
                    appBarHeight: 50,
                  ),
                  size: Size.infinite,
                ),
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
                      onTap: _strokes.isNotEmpty ? _undo : null,
                      child: SvgPicture.asset(
                        'assets/icons/editor_undo.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          _strokes.isNotEmpty
                              ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.9)
                              : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.4),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    GestureDetector(
                      onTap: _redo.isNotEmpty ? _redoAct : null,
                      child: SvgPicture.asset(
                        'assets/icons/editor_redo.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          _redo.isNotEmpty
                              ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.9)
                              : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.3),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _hasValidContent() ? _export : null,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        '완료',
                        style: TextStyle(
                          color:
                              _hasValidContent()
                                  ? Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.9)
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.3),
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

          // 좌측 세로 펜 두께 슬라이더 (약간 보이다가 터치 시 완전히 튀어나옴)
          Positioned(
            left: 0,
            top: MediaQuery.of(context).size.height * 0.25,
            bottom: MediaQuery.of(context).size.height * 0.25, // 키보드 높이 고려
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
                  // 슬라이더 영역
                  SizedBox(
                    width: _isAdjustingWidth ? 60 : 54,

                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 현재 펜 두께 표시
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
                        // 세로 슬라이더
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
                                  });
                                },
                                onChangeEnd: (v) {
                                  setState(() {
                                    _width = v.clamp(1.0, 30.0);
                                    _isAdjustingWidth = false;
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 80,
              width: double.infinity,
              color: Theme.of(context).colorScheme.background,
            ),
          ),
          // 하단 툴바 - SingleChildScrollView로 오버플로우 방지
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _toolButton(
                        Icons.brush,
                        active: !_eraser,
                        onTap: () => setState(() => _eraser = false),
                      ),
                      const SizedBox(width: 10),
                      _toolButton(
                        Icons.cleaning_services_outlined,
                        active: _eraser,
                        onTap: () => setState(() => _eraser = true),
                      ),
                      const SizedBox(width: 16),
                      _colorDot(Colors.white),
                      _colorDot(Colors.black),
                      _colorDot(const Color(0xFFFF6B6B)), // 빨강
                      _colorDot(const Color(0xFFFFD93D)), // 노랑
                      _colorDot(const Color(0xFF6BCB77)), // 초록
                      _colorDot(const Color(0xFF4D96FF)), // 파랑
                      _colorDot(const Color(0xFFB565D8)), // 보라
                      _colorDot(const Color(0xFFFF8ED4)), // 핑크
                      _colorDot(const Color(0xFFFF9F45)), // 주황
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

  void _undo() {
    if (_strokes.isEmpty) return;
    _redo.add(_strokes.removeLast());
    setState(() {});
  }

  void _redoAct() {
    if (_redo.isEmpty) return;
    _strokes.add(_redo.removeLast());
    setState(() {});
  }

  Widget _toolButton(
    IconData icon, {
    required bool active,
    required VoidCallback onTap,
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _colorDot(Color c) {
    final bool sel = _color.value == c.value;
    return GestureDetector(
      onTap: () => setState(() => _color = c),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color:
                sel
                    ? Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
            width: sel ? 3 : 1,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
      ),
    );
  }

  bool _hasValidContent() {
    // 지우개가 아닌 실제 그린 스트로크가 있는지 확인
    for (final stroke in _strokes) {
      if (!stroke.erase && stroke.points.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<void> _export() async {
    if (_strokes.isEmpty) return;

    // 1) 스트로크 경계 계산 (글로벌 좌표계)
    final Rect? bounds = _computeStrokeBounds();
    if (bounds == null || bounds.width <= 1 || bounds.height <= 1) return;

    // 2) 스트로크 데이터를 JSON으로 직렬화 (bounds 좌상단을 원점으로 한 상대 좌표)
    final List<Map<String, dynamic>> strokesData = [];
    for (final stroke in _strokes) {
      if (stroke.points.isEmpty) continue;

      // bounds.left, bounds.top을 빼서 (0,0) 기준 상대 좌표로 변환
      final List<Map<String, double>> relativePoints =
          stroke.points.map((p) {
            return {'x': p.dx - bounds.left, 'y': p.dy - bounds.top};
          }).toList();

      strokesData.add({
        'points': relativePoints,
        'color': '#${stroke.color.value.toRadixString(16).padLeft(8, '0')}',
        'width': stroke.width,
        'erase': stroke.erase,
      });
    }

    // 3) 경계의 좌상단 위치를 전달 (스티커가 이 위치에 배치됨)
    // bounds는 문서 좌표이므로, 스티커 배치를 위해 앱바 높이를 다시 더해줌
    final position = Offset(bounds.left, bounds.top + 50);
    widget.onSubmitDrawing(strokesData, position);

    if (mounted) Navigator.of(context).pop();
  }

  Rect? _computeStrokeBounds() {
    if (_strokes.isEmpty) return null;
    double? minX, minY, maxX, maxY;

    for (final s in _strokes) {
      if (s.points.isEmpty || s.erase) continue; // 지우개 스트로크는 경계 계산에서 제외
      final double half = s.width / 2;
      for (final p in s.points) {
        final double x1 = p.dx - half;
        final double y1 = p.dy - half;
        final double x2 = p.dx + half;
        final double y2 = p.dy + half;
        minX = (minX == null) ? x1 : (x1 < minX ? x1 : minX);
        minY = (minY == null) ? y1 : (y1 < minY ? y1 : minY);
        maxX = (maxX == null) ? x2 : (x2 > maxX ? x2 : maxX);
        maxY = (maxY == null) ? y2 : (y2 > maxY ? y2 : maxY);
      }
    }

    if (minX == null || minY == null || maxX == null || maxY == null) {
      return null;
    }

    // 패딩 최소화 (선 두께가 이미 반영되어 있음)
    const double pad = 0.5;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }
}

class _Stroke {
  final List<Offset> points = <Offset>[];
  final Color color;
  final double width;
  final bool erase;
  _Stroke({required this.color, required this.width, this.erase = false});
}

class _DrawingPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final double scale;
  final Offset pan;
  final double scrollY;
  final double appBarHeight;

  _DrawingPainter({
    required this.strokes,
    required this.scale,
    required this.pan,
    required this.scrollY,
    required this.appBarHeight,
  });

  /// 문서 좌표를 화면 좌표로 변환
  Offset _toScreenCoord(Offset docPos) {
    return Offset(docPos.dx, docPos.dy + appBarHeight - scrollY);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 레이어를 열어 지우개(BlendMode.clear)가 하위 드로잉을 깔끔히 지우도록 함
    canvas.saveLayer(Offset.zero & size, Paint());

    // 1) 일반 펜 스트로크 먼저 그리기
    for (final s in strokes) {
      if (!s.erase && s.points.isNotEmpty) {
        final paint =
            Paint()
              ..color = s.color
              ..strokeWidth = s.width
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..isAntiAlias = true;

        final path = Path();
        final first = _toScreenCoord(s.points.first);
        path.moveTo(first.dx, first.dy);
        for (int i = 1; i < s.points.length; i++) {
          final p = _toScreenCoord(s.points[i]);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    // 2) 지우개 스트로크는 Clear 블렌드모드로 덮어서 삭제
    for (final s in strokes) {
      if (s.erase && s.points.isNotEmpty) {
        final erasePaint =
            Paint()
              ..blendMode = BlendMode.clear
              ..strokeWidth = s.width
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..isAntiAlias = true;

        final path = Path();
        final first = _toScreenCoord(s.points.first);
        path.moveTo(first.dx, first.dy);
        for (int i = 1; i < s.points.length; i++) {
          final p = _toScreenCoord(s.points[i]);
          path.lineTo(p.dx, p.dy);
        }
        // 단일 점일 때도 원형으로 지우도록 처리
        if (s.points.length == 1) {
          final c = _toScreenCoord(s.points.first);
          path.addOval(Rect.fromCircle(center: c, radius: s.width / 2));
        }

        canvas.drawPath(path, erasePaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    // 스트로크 개수가 변경되었거나 스크롤 위치가 변경되었을 때만 리페인트
    return strokes.length != oldDelegate.strokes.length ||
        scrollY != oldDelegate.scrollY ||
        strokes.isNotEmpty; // 현재 그리는 중이면 항상 리페인트
  }
}
