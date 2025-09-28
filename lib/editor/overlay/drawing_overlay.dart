import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class DrawingOverlay extends StatefulWidget {
  final void Function(Uint8List png) onSubmitImage;
  const DrawingOverlay({required this.onSubmitImage});

  @override
  State<DrawingOverlay> createState() => _DrawingOverlayState();
}

class _DrawingOverlayState extends State<DrawingOverlay> {
  final GlobalKey _canvasKey = GlobalKey();
  final List<_Stroke> _strokes = <_Stroke>[];
  final List<_Stroke> _redo = <_Stroke>[];
  Color _color = Colors.white;
  double _width = 8;
  bool _eraser = false;
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // 배경 블러
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                    child: Container(
                      color: const ui.Color.fromARGB(182, 144, 144, 144),
                    ),
                  ),
                ),

                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 106, 106, 106),
                    ),
                  ),
                ),

                // 캔버스
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (d) {
                      _redo.clear();
                      _strokes.add(
                        _Stroke(
                          color: _eraser ? Colors.transparent : _color,
                          width: _width,
                          erase: _eraser,
                        )..points.add(_toCanvas(d.localFocalPoint)),
                      );
                      setState(() {});
                    },
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2) {
                        setState(() {
                          _scale = (_scale * d.scale).clamp(0.5, 3.0);
                          _pan += d.focalPointDelta;
                        });
                        return;
                      }
                      if (_strokes.isEmpty) return;
                      _strokes.last.points.add(_toCanvas(d.localFocalPoint));
                      setState(() {});
                    },
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: CustomPaint(
                        painter: _DrawingPainter(
                          strokes: _strokes,
                          scale: _scale,
                          pan: _pan,
                        ),
                        size: Size(
                          MediaQuery.of(context).size.width * 0.86,
                          MediaQuery.of(context).size.height * 0.6,
                        ),
                      ),
                    ),
                  ),
                ),

                // 상단 바
                Positioned(
                  top: 60,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _undo,
                        icon: const Icon(
                          Icons.undo_outlined,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: _redoAct,
                        icon: const Icon(
                          Icons.redo_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _export,
                        child: const Text(
                          '완료',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.black),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _toolButton(
                    Icons.brush,
                    active: !_eraser,
                    onTap: () => setState(() => _eraser = false),
                  ),
                  const SizedBox(width: 10),
                  _toolButton(
                    Icons.auto_fix_high,
                    active: _eraser,
                    onTap: () => setState(() => _eraser = true),
                  ),
                  const SizedBox(width: 16),
                  _colorDot(Colors.white),
                  _colorDot(Colors.yellow),
                  _colorDot(Colors.cyanAccent),
                  _colorDot(Colors.pinkAccent),
                  _colorDot(Colors.limeAccent),
                  const SizedBox(width: 16),
                  _thickness(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Offset _toCanvas(Offset p) => (p - _pan) / _scale;

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
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: sel ? Colors.white : Colors.white24,
            width: sel ? 2 : 1,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _thickness() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _width = (_width - 2).clamp(2, 40)),
          child: const Icon(Icons.remove, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Container(
          width: 40,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            '${_width.toInt()}px',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _width = (_width + 2).clamp(2, 40)),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ],
    );
  }

  Future<void> _export() async {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    // 1) 스트로크 경계 계산 (선 두께 반영 + 패딩)
    final Rect? bounds = _computeStrokeBounds();
    if (bounds == null || bounds.width <= 1 || bounds.height <= 1) return;
    final double w = bounds.width.ceilToDouble();
    final double h = bounds.height.ceilToDouble();

    // 2) 경계만큼 크롭해서 렌더
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    // 경계 좌측 상단을 원점으로 옮겨 그림
    canvas.save();
    canvas.translate(-bounds.left, -bounds.top);
    // 저장된 포인트는 이미 캔버스 좌표계이므로 추가 스케일/팬 불필요
    _DrawingPainter(
      strokes: _strokes,
      scale: 1.0,
      pan: Offset.zero,
    ).paint(canvas, Size(w, h));
    canvas.restore();
    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    widget.onSubmitImage(byteData.buffer.asUint8List());
    if (mounted) Navigator.of(context).pop();
  }

  Rect? _computeStrokeBounds() {
    if (_strokes.isEmpty) return null;
    double? minX, minY, maxX, maxY;
    for (final s in _strokes) {
      if (s.points.isEmpty) continue;
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
    if (minX == null || minY == null || maxX == null || maxY == null)
      return null;
    const double pad = 8.0;
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
    // 보기 변환(패닝/스케일)
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale, scale);
    for (final s in strokes) {
      final paint =
          Paint()
            ..color = s.erase ? Colors.transparent : s.color
            ..blendMode = s.erase ? BlendMode.clear : BlendMode.srcOver
            ..strokeWidth = s.width
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;
      final path = Path();
      if (s.points.isEmpty) continue;
      path.moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    // 포인트가 같은 리스트 내부에서 변하므로 항상 리페인트
    return true;
  }
}
