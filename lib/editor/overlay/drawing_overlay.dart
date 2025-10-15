import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class DrawingOverlay extends StatefulWidget {
  final void Function(List<Map<String, dynamic>> strokes, Offset position)
  onSubmitDrawing;
  final List<Map<String, dynamic>>? initialStrokes;

  const DrawingOverlay({required this.onSubmitDrawing, this.initialStrokes});

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

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                _redo.clear();
                _strokes.add(
                  _Stroke(
                    color: _eraser ? Colors.black : _color,
                    width: _width,
                    erase: _eraser,
                  )..points.add(d.globalPosition),
                );
                setState(() {});
              },
              onPanUpdate: (d) {
                if (_strokes.isEmpty) return;
                _strokes.last.points.add(d.globalPosition);
                setState(() {});
              },
              child: RepaintBoundary(
                key: _canvasKey,
                child: CustomPaint(
                  painter: _DrawingPainter(
                    strokes: _strokes,
                    scale: 1.0,
                    pan: Offset.zero,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),

          // 상단 툴바
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Container(
              height: 50,
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
                        color: Colors.white.withOpacity(0.9),
                        size: 22,
                      ),
                      style: IconButton.styleFrom(),
                    ),
                    const SizedBox(width: 20),

                    GestureDetector(
                      onTap: _strokes.isNotEmpty ? _undo : null,
                      child: SvgPicture.asset(
                        'assets/icons/editor_undo.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          _strokes.isNotEmpty
                              ? Colors.white.withOpacity(0.9)
                              : Colors.white.withOpacity(0.3),
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
                              ? Colors.white.withOpacity(0.9)
                              : Colors.white.withOpacity(0.3),
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
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
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

          // 왼쪽 펜 두께 슬라이더
          Positioned(
            left: 0,
            top: MediaQuery.of(context).padding.top + 80,
            bottom: MediaQuery.of(context).padding.bottom + 100,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                width: 40,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.background.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    // 두께 표시
                    Container(
                      width: 28,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle),
                      child: Text(
                        '${_width.toInt()}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // 세로 슬라이더
                    Expanded(
                      flex: 2,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 6,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                            activeTrackColor: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(1),
                            inactiveTrackColor: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.1),
                            thumbColor: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(1),
                          ),
                          child: Slider(
                            value: _width,
                            min: 1,
                            max: 30,
                            onChanged: (value) {
                              setState(() => _width = value);
                            },
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

          // 하단 툴바 - SingleChildScrollView로 오버플로우 방지
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 8,
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
                  ? Colors.white.withOpacity(0.22)
                  : Colors.white.withOpacity(0.10),
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
            color: sel ? Colors.white : Colors.white24,
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
    final position = Offset(bounds.left, bounds.top);
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
  _DrawingPainter({
    required this.strokes,
    required this.scale,
    required this.pan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 지우개 영역을 계산하기 위한 Path
    Path erasePath = Path();

    // 모든 지우개 스트로크를 하나의 Path로 합치기
    for (final s in strokes) {
      if (s.erase && s.points.isNotEmpty) {
        if (s.points.length > 1) {
          erasePath.moveTo(s.points.first.dx, s.points.first.dy);
          for (int i = 1; i < s.points.length; i++) {
            erasePath.lineTo(s.points[i].dx, s.points[i].dy);
          }
        } else {
          erasePath.addOval(
            Rect.fromCircle(center: s.points.first, radius: s.width / 2),
          );
        }
      }
    }

    // 일반 펜 스트로크를 그리되, 지우개 영역은 제외
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
        path.moveTo(s.points.first.dx, s.points.first.dy);
        for (int i = 1; i < s.points.length; i++) {
          path.lineTo(s.points[i].dx, s.points[i].dy);
        }

        // 지우개 영역이 있으면 차감
        if (!erasePath.getBounds().isEmpty) {
          final newPath = Path.combine(
            PathOperation.difference,
            path,
            erasePath,
          );
          canvas.drawPath(newPath, paint);
        }

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    // 포인트가 같은 리스트 내부에서 변하므로 항상 리페인트
    return true;
  }
}
