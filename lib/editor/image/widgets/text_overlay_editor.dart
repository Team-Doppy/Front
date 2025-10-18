import 'package:doppy/theme/app_colors.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:doppy/editor/image/models/text_overlay_model.dart';
import 'dart:math' as math;
import 'package:doppy/editor/style/font_catalog.dart';

enum _ToolbarPanel { none, color, font }

class TextOverlayEditor extends StatefulWidget {
  final List<TextOverlayData> textOverlays;
  final ValueChanged<List<TextOverlayData>> onTextOverlaysChanged;
  final VoidCallback? onFinish; // 완료 시 콜백
  final double? maxTextWidth;
  final double? maxTextHeight;
  final Uint8List imageBytes; // 배경 이미지 (비율 유지용)
  final Size? imageSize; // 부모에서 전달된 이미지 원본 사이즈(있으면 깜빡임 방지)

  const TextOverlayEditor({
    super.key,
    required this.textOverlays,
    required this.onTextOverlaysChanged,
    required this.imageBytes,
    this.imageSize,
    this.onFinish,
    this.maxTextWidth,
    this.maxTextHeight,
  });

  @override
  State<TextOverlayEditor> createState() => _TextOverlayEditorState();
}

class _TextOverlayEditorState extends State<TextOverlayEditor> {
  // 상태
  bool _isEditing = false;
  String? _editingId;

  // 입력 컨트롤
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // 스타일 상태
  Color _textColor = AppColors.darkTextPrimary;
  double _fontSize = 20.0;
  FontWeight _fontWeight = FontWeight.bold;
  TextAlign _textAlign = TextAlign.center;
  bool _hasBackground = false; // 텍스트 배경
  String? _fontIdentifier; // FontCatalog identifier
  _ToolbarPanel _activePanel = _ToolbarPanel.none;
  bool _isAdjustingFontSize = false; // 슬라이더 조작 중 여부

  @override
  void initState() {
    super.initState();
    // 화면 진입 시 바로 편집 시작 (새 텍스트 추가 플로우)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startEditing();
    });
    _textController.addListener(_onTextChanged);
  }

  Future<Size> _decodeImageSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  }

  Future<Size> _getImageSize() async {
    if (widget.imageSize != null) return widget.imageSize!;
    return _decodeImageSize(widget.imageBytes);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing({String? id}) {
    setState(() {
      _isEditing = true;
      _editingId = id;

      if (id != null) {
        final overlay = widget.textOverlays.firstWhere((o) => o.id == id);
        _textController.text = overlay.text;
        _textColor = overlay.textColor;
        _fontSize = overlay.fontSize;
        _fontWeight = overlay.fontWeight;
        _textAlign = overlay.textAlign;
        _hasBackground = overlay.backgroundColor != null;
        _fontIdentifier = overlay.fontIdentifier;
      } else {
        _textController.clear();
        _textColor = Colors.white;
        _fontSize = 24.0;
        _fontWeight = FontWeight.w600;
        _textAlign = TextAlign.center;
        _hasBackground = false;
        _fontIdentifier = null;
      }
    });

    // 포커스 요청 (키보드 표시)
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _finishEditing() {
    // 키보드 먼저 내리기
    _focusNode.unfocus();

    final text = _textController.text.trim();
    print('텍스트 입력: "$text"');

    if (text.isEmpty) {
      print('텍스트가 비어있음');
      setState(() {
        _isEditing = false;
        _editingId = null;
      });
      return;
    }

    // 중복 추가 방지: 이미 편집 중인 텍스트가 있으면 업데이트만
    // 1차 안전장치: 완료 직전에 폰트가 영역을 넘지 않도록 자동 축소
    final double maxW =
        (widget.maxTextWidth ?? MediaQuery.of(context).size.width) * 0.98;
    final double maxH =
        (widget.maxTextHeight ?? MediaQuery.of(context).size.height * 0.8) *
        0.98;
    final fittedSize = _fitFontSizeToBounds(text, _fontSize, maxW, maxH);
    if (fittedSize != _fontSize) {
      setState(() => _fontSize = fittedSize);
    }

    if (_editingId != null) {
      final newData = TextOverlayData(
        id: _editingId!,
        text: text,
        position: const Offset(0.5, 0.5),
        textColor: _textColor,
        fontSize: _fontSize,
        fontWeight: _fontWeight,
        textAlign: _textAlign,
        backgroundColor: _hasBackground ? Colors.black54 : null,
        fontIdentifier: _fontIdentifier,
      );

      final List<TextOverlayData> updated = List.of(widget.textOverlays);
      final idx = updated.indexWhere((e) => e.id == _editingId);
      if (idx != -1) {
        updated[idx] = newData;
        widget.onTextOverlaysChanged(updated);
      }
    } else {
      // 새 텍스트 추가 (한 번만)
      print('새 텍스트 추가 중...');
      final newData = TextOverlayData(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        position: const Offset(0.5, 0.5),
        textColor: _textColor,
        fontSize: _fontSize,
        fontWeight: _fontWeight,
        textAlign: _textAlign,
        backgroundColor: _hasBackground ? Colors.black54 : null,
        fontIdentifier: _fontIdentifier,
      );

      final List<TextOverlayData> updated = List.of(widget.textOverlays);
      updated.add(newData);
      widget.onTextOverlaysChanged(updated);
    }

    setState(() {
      _isEditing = false;
      _editingId = null;
    });

    // 텍스트 추가 후에는 오버레이를 닫지 않음 (계속 텍스트 편집 가능)
    // widget.onFinish?.call();

    // 텍스트 추가 완료 후 입력 필드 초기화
    _textController.clear();
  }

  // 텍스트가 이미지 허용 영역을 넘으면 폰트 크기를 자동 축소
  void _onTextChanged() {
    if (widget.maxTextWidth == null || widget.maxTextHeight == null) return;
    final text = _textController.text;
    if (text.isEmpty) return;

    final double maxW = widget.maxTextWidth! * 0.98; // 여유 버퍼
    final double maxH = widget.maxTextHeight! * 0.98;

    Size measure(double fs) {
      final style =
          (() {
            if (_fontIdentifier != null) {
              final item = FontCatalog.findByIdentifier(_fontIdentifier!);
              if (item != null) {
                return item.getTextStyle(
                  fontWeight: _fontWeight,
                  fontSize: fs,
                  color: _textColor,
                );
              }
            }
            return TextStyle(
              color: _textColor,
              fontSize: fs,
              fontWeight: _fontWeight,
            );
          })();

      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: null,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      )..layout(maxWidth: maxW);
      return Size(tp.width, tp.height);
    }

    final Size cur = measure(_fontSize);
    if (cur.width <= maxW && cur.height <= maxH) return;

    double low = 8.0;
    double high = _fontSize;
    double best = _fontSize;
    for (int i = 0; i < 14; i++) {
      final mid = (low + high) / 2;
      final s = measure(mid);
      if (s.width > maxW || s.height > maxH) {
        high = mid;
      } else {
        best = mid;
        low = mid;
      }
    }
    if (best != _fontSize) {
      setState(() => _fontSize = best);
    }
  }

  // 중복 구현 제거됨 (상단에 통합 구현 존재)

  void _updatePosition(String id, Offset delta, Size containerSize) {
    final updated = List<TextOverlayData>.from(widget.textOverlays);
    final index = updated.indexWhere((e) => e.id == id);
    if (index == -1) return;

    final overlay = updated[index];
    // 텍스트 실제 크기 측정
    TextStyle style;
    if (overlay.fontIdentifier != null) {
      final item = FontCatalog.findByIdentifier(overlay.fontIdentifier!);
      style =
          item != null
              ? item.getTextStyle(
                fontWeight: overlay.fontWeight,
                fontSize: overlay.fontSize,
                color: overlay.textColor,
              )
              : TextStyle(
                color: overlay.textColor,
                fontSize: overlay.fontSize,
                fontWeight: overlay.fontWeight,
              );
    } else {
      style = TextStyle(
        color: overlay.textColor,
        fontSize: overlay.fontSize,
        fontWeight: overlay.fontWeight,
      );
    }
    final tp = TextPainter(
      text: TextSpan(text: overlay.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout();

    final padH = overlay.backgroundColor != null ? 16.0 : 0.0;
    final padV = overlay.backgroundColor != null ? 8.0 : 0.0;
    double w = tp.width + padH * 2;
    double h = tp.height + padV * 2;

    // 2차 안전장치: 텍스트가 컨테이너보다 크면 자동 축소
    if (w > containerSize.width || h > containerSize.height) {
      final widthScale = containerSize.width / w;
      final heightScale = containerSize.height / h;
      final safeScale = math.min(widthScale, heightScale).clamp(0.1, 1.0);
      final newFont = (overlay.fontSize * safeScale).clamp(8.0, 300.0);
      updated[index] = overlay.copyWith(fontSize: newFont);
      widget.onTextOverlaysChanged(updated);
      // 새 크기로 재측정
      final tp2 = TextPainter(
        text: TextSpan(
          text: overlay.text,
          style: style.copyWith(fontSize: newFont),
        ),
        textDirection: TextDirection.ltr,
        maxLines: null,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      )..layout();
      w = tp2.width + padH * 2;
      h = tp2.height + padV * 2;
    }

    final maxRelXRaw = (containerSize.width - w) / containerSize.width;
    final maxRelYRaw = (containerSize.height - h) / containerSize.height;
    final maxRelX =
        maxRelXRaw < 0.0 ? 0.0 : (maxRelXRaw > 1.0 ? 1.0 : maxRelXRaw);
    final maxRelY =
        maxRelYRaw < 0.0 ? 0.0 : (maxRelYRaw > 1.0 ? 1.0 : maxRelYRaw);

    final current = overlay.position;
    final next = Offset(
      (current.dx + delta.dx / containerSize.width).clamp(0.0, maxRelX),
      (current.dy + delta.dy / containerSize.height).clamp(0.0, maxRelY),
    );
    updated[index] = updated[index].copyWith(position: next);
    widget.onTextOverlaysChanged(updated);
  }

  double _fitFontSizeToBounds(
    String text,
    double fontSize,
    double maxW,
    double maxH,
  ) {
    double low = 8.0;
    double high = fontSize;
    double best = fontSize;
    Size measure(double fs) {
      TextStyle style;
      if (_fontIdentifier != null) {
        final item = FontCatalog.findByIdentifier(_fontIdentifier!);
        if (item != null) {
          style = item.getTextStyle(
            fontWeight: _fontWeight,
            fontSize: fs,
            color: _textColor,
          );
        } else {
          style = TextStyle(
            color: _textColor,
            fontSize: fs,
            fontWeight: _fontWeight,
          );
        }
      } else {
        style = TextStyle(
          color: _textColor,
          fontSize: fs,
          fontWeight: _fontWeight,
        );
      }
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: null,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      )..layout(maxWidth: maxW);
      return Size(tp.width, tp.height);
    }

    final Size cur = measure(fontSize);
    if (cur.width <= maxW && cur.height <= maxH) return fontSize;
    for (int i = 0; i < 14; i++) {
      final mid = (low + high) / 2;
      final s = measure(mid);
      if (s.width > maxW || s.height > maxH) {
        high = mid;
      } else {
        best = mid;
        low = mid;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background.withOpacity(1),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 보기/이동 레이어 (편집 중에는 포인터 차단) + 배경 이미지 비율 일치
          IgnorePointer(
            ignoring: _isEditing,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final container = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return FutureBuilder<Size>(
                  future: _getImageSize(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final imgSize = snap.data!;
                    final imgAR = imgSize.width / imgSize.height;
                    final contAR = container.width / container.height;
                    late Size displaySize;
                    late Offset offset;
                    if (imgAR > contAR) {
                      displaySize = Size(
                        container.width,
                        container.width / imgAR,
                      );
                      offset = Offset(
                        0,
                        (container.height - displaySize.height) / 2,
                      );
                    } else {
                      displaySize = Size(
                        container.height * imgAR,
                        container.height,
                      );
                      offset = Offset(
                        (container.width - displaySize.width) / 2,
                        0,
                      );
                    }
                    return Stack(
                      children: [
                        // 배경 이미지 (비율 동일하게 표시)
                        Positioned(
                          left: offset.dx,
                          top: 0,
                          width: displaySize.width,
                          height: displaySize.height,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.contain,
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ),
                        // 텍스트 오버레이
                        ...widget.textOverlays.map((overlay) {
                          final left =
                              offset.dx +
                              overlay.position.dx * displaySize.width;
                          final top =
                              offset.dy +
                              overlay.position.dy * displaySize.height;
                          return Positioned(
                            left: left,
                            top: top,
                            child: GestureDetector(
                              onTap: () => _startEditing(id: overlay.id),
                              onPanUpdate:
                                  (d) => _updatePosition(
                                    overlay.id,
                                    d.delta,
                                    displaySize,
                                  ),
                              child: Transform.translate(
                                offset: const Offset(-0.5, -0.5),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal:
                                        overlay.backgroundColor != null
                                            ? 16
                                            : 0,
                                    vertical:
                                        overlay.backgroundColor != null ? 8 : 0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: overlay.backgroundColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    overlay.text,
                                    textAlign: overlay.textAlign,
                                    style:
                                        (() {
                                          final baseColor = overlay.textColor;
                                          final baseSize = overlay.fontSize;
                                          final baseWeight = overlay.fontWeight;
                                          if (overlay.fontIdentifier != null) {
                                            final item =
                                                FontCatalog.findByIdentifier(
                                                  overlay.fontIdentifier!,
                                                );
                                            if (item != null) {
                                              return item.getTextStyle(
                                                fontWeight: baseWeight,
                                                fontSize: baseSize,
                                                color: baseColor,
                                              );
                                            }
                                          }
                                          return TextStyle(
                                            color: baseColor,
                                            fontSize: baseSize,
                                            fontWeight: baseWeight,
                                          );
                                        })(),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // 편집 레이어
          Offstage(
            offstage: !_isEditing,
            child: AnimatedOpacity(
              opacity: _isEditing ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Stack(
                  children: [
                    // 중앙 입력 박스 (이미지 영역 크기 내로 제한)
                    SafeArea(
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: FutureBuilder<Size>(
                                future: _decodeImageSize(widget.imageBytes),
                                builder: (context, snap) {
                                  if (!snap.hasData) {
                                    return const SizedBox.shrink();
                                  }
                                  final imgSize = snap.data!;
                                  final view = Size(
                                    MediaQuery.of(context).size.width,
                                    MediaQuery.of(context).size.height -
                                        bottomInset,
                                  );
                                  final ar = imgSize.width / imgSize.height;
                                  final varr = view.width / view.height;
                                  late Size displaySize;
                                  if (ar > varr) {
                                    displaySize = Size(
                                      view.width,
                                      view.width / ar,
                                    );
                                  } else {
                                    displaySize = Size(
                                      view.height * ar,
                                      view.height,
                                    );
                                  }
                                  return ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          widget.maxTextWidth ??
                                          displaySize.width,
                                      maxHeight:
                                          widget.maxTextHeight ??
                                          displaySize.height * 0.85,
                                    ),
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: _hasBackground ? 20 : 0,
                                        vertical: _hasBackground ? 12 : 0,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            _hasBackground
                                                ? Colors.black54
                                                : null,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: TextField(
                                        cursorColor: AppColors.darkTextPrimary,
                                        controller: _textController,
                                        focusNode: _focusNode,
                                        autofocus: true,
                                        maxLines: null,
                                        scrollPhysics:
                                            const NeverScrollableScrollPhysics(),
                                        textAlign: _textAlign,
                                        style:
                                            (() {
                                              if (_fontIdentifier != null) {
                                                final item =
                                                    FontCatalog.findByIdentifier(
                                                      _fontIdentifier!,
                                                    );
                                                if (item != null) {
                                                  return item.getTextStyle(
                                                    fontWeight: _fontWeight,
                                                    fontSize: _fontSize,
                                                    color: _textColor,
                                                  );
                                                }
                                              }
                                              return TextStyle(
                                                color: _textColor,
                                                fontSize: _fontSize,
                                                fontWeight: _fontWeight,
                                              );
                                            })(),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,

                                          hintText: '텍스트 입력',
                                          hintStyle: TextStyle(
                                            color: AppColors.darkTextPrimary,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          isCollapsed: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (_) => _onTextChanged(),
                                        onSubmitted: (_) => _finishEditing(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                          // 하단 툴바 (폰트/색상 옵션을 키보드 유지 상태에서 펼침)
                          _ExpandableToolbar(
                            onSelectPanel: (panel) {
                              setState(() {
                                _activePanel =
                                    _activePanel == panel
                                        ? _ToolbarPanel.none
                                        : panel;
                              });
                            },
                            onToggleBackground: () {
                              setState(() {
                                _hasBackground = !_hasBackground;
                              });
                            },
                            color: _textColor,
                            onColorChanged:
                                (c) => setState(() => _textColor = c),
                            fontSize: _fontSize,
                            onFontSizeChanged:
                                (v) => setState(
                                  () => _fontSize = v.clamp(8.0, 120.0),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 좌측 세로 폰트 크기 슬라이더 (편집 중에만)
          if (_isEditing)
            Positioned(
              left: 0,
              top: 120,
              bottom: bottomInset + 50, // 키보드 높이 고려
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(
                  _isAdjustingFontSize ? 0 : -20,
                  0,
                  0,
                ),
                child: Row(
                  children: [
                    // 슬라이더 영역
                    Container(
                      width: 60,

                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 8,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 현재 폰트 크기 표시
                          if (_isAdjustingFontSize)
                            Text(
                              '${_fontSize.round()}',
                              style: const TextStyle(
                                color: Colors.white,
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
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16,
                                  ),
                                ),
                                child: Slider(
                                  activeColor: Colors.white.withOpacity(0.8),
                                  inactiveColor: Colors.white.withOpacity(0.2),
                                  min: 8,
                                  max: 120,
                                  value: _fontSize.clamp(8.0, 120.0),
                                  onChangeStart: (v) {
                                    setState(() => _isAdjustingFontSize = true);
                                  },
                                  onChanged: (v) {
                                    setState(() {
                                      _fontSize = v.clamp(8.0, 120.0);
                                    });
                                  },
                                  onChangeEnd: (v) {
                                    setState(() {
                                      _fontSize = v.clamp(8.0, 120.0);
                                      _isAdjustingFontSize = false;
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

          // 상단 완료 버튼 (최상위 레이어)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final text = _textController.text.trim();
                    if (text.isEmpty) {
                      // 입력이 없으면 단순 종료
                      widget.onFinish?.call();
                      return;
                    }
                    // 입력이 있으면 먼저 저장 후 종료
                    _finishEditing();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onFinish?.call();
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),

                    child: const Text(
                      '완료',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color:
              isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

/// 하단 확장형 툴바: 좌측 세로 슬라이더(폰트 크기), 중앙 가로 스크롤 버튼들, 우측 버튼들
class _ExpandableToolbar extends StatelessWidget {
  final void Function(_ToolbarPanel) onSelectPanel;
  final VoidCallback onToggleBackground;
  final Color color;
  final ValueChanged<Color> onColorChanged;
  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;

  const _ExpandableToolbar({
    required this.onSelectPanel,
    required this.onToggleBackground,
    required this.color,
    required this.onColorChanged,
    required this.fontSize,
    required this.onFontSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 중앙: 가로 스크롤 툴 버튼 그룹
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 0),
                children: [
                  // 색상 팔레트 토글 (간단 버전)
                  _ToolbarButton(
                    icon: Icons.color_lens,
                    isSelected: false,
                    onTap: () => onSelectPanel(_ToolbarPanel.color),
                  ),

                  const SizedBox(width: 6),

                  // 폰트 선택 버튼 → 하위 요소 가로 스크롤 (카탈로그 모달로 구현)
                  _ToolbarButton(
                    icon: Icons.font_download,
                    isSelected: false,
                    onTap: () => onSelectPanel(_ToolbarPanel.font),
                  ),

                  const SizedBox(width: 6),

                  // 배경 토글
                  _ToolbarButton(
                    icon: Icons.blur_on,
                    isSelected: false,
                    onTap: onToggleBackground,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
