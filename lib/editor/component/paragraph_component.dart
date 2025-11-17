import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:math';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';

/// 패키지 기본 ParagraphComponent를 사용하고,
/// 드래그 드롭 라인만 오버레이로 추가하는 경량 커스텀 빌더
class CustomParagraphComponentBuilder implements ComponentBuilder {
  const CustomParagraphComponentBuilder({
    required this.dragService,
    required this.editorService,
    this.isEditing = true,
    this.onMentionTap,
  });

  final DragService dragService;
  final EditorService editorService;
  final bool isEditing;
  final void Function(List<String> usernames)? onMentionTap;
  static const ParagraphComponentBuilder _defaultBuilder =
      ParagraphComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    // 기본 빌더에 위임 (패키지 ParagraphNode만 대상)
    final result = _defaultBuilder.createViewModel(document, node);
    return result;
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    // 문단이 아닌 경우 래핑 불필요
    if (componentViewModel is! ParagraphComponentViewModel) {
      return _defaultBuilder.createComponent(
        componentContext,
        componentViewModel,
      );
    }

    // 구분선 문단은 전용 DocumentComponent로 교체 (DocumentComponent 필요)
    try {
      final node = editorService.editor.document.getNodeById(
        componentViewModel.nodeId,
      );
      if (node is ParagraphNode && node.metadata['isDivider'] == true) {
        return _DividerDocumentComponent(
          nodeId: componentViewModel.nodeId,
          componentKey: componentContext.componentKey,
        );
      }
    } catch (_) {}

    // 기본 컴포넌트 생성
    final child = _defaultBuilder.createComponent(
      componentContext,
      componentViewModel,
    );
    if (child == null) return null;

    // 드래그 라인만 덧씌우는 얇은 래퍼
    return _ParagraphWithDropLines(
      nodeId: componentViewModel.nodeId,
      dragService: dragService,
      editorService: editorService,
      isEditing: isEditing,
      onMentionTap: onMentionTap,
      child: child,
    );
  }
}

class _ParagraphWithDropLines extends StatefulWidget {
  const _ParagraphWithDropLines({
    required this.nodeId,
    required this.dragService,
    required this.editorService,
    required this.isEditing,
    required this.child,
    this.onMentionTap,
  });

  final String nodeId;
  final DragService dragService;
  final EditorService editorService;
  final bool isEditing;
  final Widget child;
  final void Function(List<String> usernames)? onMentionTap;

  @override
  State<_ParagraphWithDropLines> createState() =>
      _ParagraphWithDropLinesState();
}

class _ParagraphWithDropLinesState extends State<_ParagraphWithDropLines>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _subtreeKey = GlobalKey();
  // 캐시 사용 제거: attribution 변경에 즉시 반응하도록 항상 재계산
  // 스포일러 해제(리빌) 파티클 이펙트
  late final AnimationController _scatterCtrl;
  bool _scatterActive = false;
  List<Rect> _scatterBoxes = const [];
  bool _wasMaskVisible = false;
  List<Rect> _prevBoxes = const [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 1500));
    _scatterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (mounted) setState(() => _scatterActive = false);
      }
    });

    // 🎯 읽기 모드에서 스포일러 블러 렌더링을 위한 초기 리빌드
    // 첫 프레임에서는 RenderBox가 아직 레이아웃되지 않아 _collectSpoilerBoxes가 빈 리스트 반환
    // 두 번째 프레임에서 레이아웃 완료 후 정확한 박스 계산
    if (!widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scatterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NodeComponentService를 Listenable로 추가하여 변경사항 감지
    final nodeService = Provider.of<NodeComponentService>(
      context,
      listen: false,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.dragService,
        widget.editorService,
        widget
            .editorService
            .editor
            .composer, // Composer 변경사항 즉시 감지 (텍스트/attribution 변경)
        nodeService, // NodeComponentService 변경사항 감지 (ChangeNotifier는 Listenable)
      ]),
      builder: (context, _) {
        final currentIndex = widget.dragService.getNodeIndex(widget.nodeId);
        final dropIndex = widget.dragService.dropIndex;
        final isSelf = widget.dragService.draggingNodeId == widget.nodeId;
        final documentLength = widget.editorService.document.length;
        final isLastNode = currentIndex == documentLength - 1;

        bool showTop =
            dropIndex != null &&
            !isSelf &&
            currentIndex != -1 &&
            dropIndex == currentIndex;

        bool showBottom = false;
        if (isLastNode && dropIndex != null && !isSelf && currentIndex != -1) {
          showBottom = dropIndex == documentLength;
        }

        if (showTop) {
          try {
            final doc = widget.editorService.document;
            if (currentIndex - 1 >= 0) {
              final prev = doc.getNodeAt(currentIndex - 1);
              if (prev is ImageNode ||
                  prev is ImageRowNode ||
                  prev is ClipNode ||
                  prev is LinkNode) {
                showTop = false;
              }
            }
          } catch (_) {}
        }

        Widget content = DefaultTextStyle.merge(
          textAlign: _resolveTextAlign(),
          child: KeyedSubtree(key: _subtreeKey, child: widget.child),
        );

        Widget stack = Stack(
          children: [
            // 본문 내용 마진 제거
            Padding(
              padding: EdgeInsets.only(top: 6, bottom: showBottom ? 4 : 0),
              child: content,
            ),
            // 형광펜 오버레이 (스포일러처럼 그리기)
            Builder(
              builder: (context) {
                final hi = _collectHighlightBoxes(context);
                if (hi.isEmpty) return const SizedBox.shrink();
                return Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: CustomPaint(
                      painter: _ParagraphHighlightPainter(highlights: hi),
                    ),
                  ),
                );
              },
            ),
            // 문단 위에 직접 글리터 렌더링 (로컬 좌표기준이라 오프셋 불필요)
            // 읽기 모드이고 스포일러가 있을 때는 탭 이벤트를 통과시켜야 함
            Builder(
              builder: (context) {
                // 스포일러 박스를 매번 재계산
                final boxes = _collectSpoilerBoxes(context, nodeService);
                final bool maskVisible = boxes.isNotEmpty;

                // 현재 마스크가 보이는 동안엔 다음 전환을 대비해 최근 박스를 보관
                if (maskVisible) {
                  _prevBoxes = boxes;
                }
                // 방금 해제되면 일회성 스캐터 실행 (이전 프레임 박스를 사용)
                if (_wasMaskVisible &&
                    !maskVisible &&
                    _scatterCtrl.status != AnimationStatus.forward) {
                  _scatterBoxes = _prevBoxes;
                  if (_scatterBoxes.isNotEmpty) {
                    // ✅ WidgetsBinding으로 다음 프레임에 setState 호출
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _scatterActive = true;
                        });
                        _scatterCtrl
                          ..reset()
                          ..forward();
                      }
                    });
                  }
                }
                _wasMaskVisible = maskVisible;

                if (boxes.isEmpty) return const SizedBox.shrink();

                final theme = Theme.of(context).colorScheme;
                final brightness = Theme.of(context).brightness;
                final isLightTheme = brightness == Brightness.light;
                // 다크 모드의 편집 화면에서는 박스 배경을 투명 처리하여
                // 회색 박스가 깔리는 현상을 방지한다.
                final bgColor =
                    (!isLightTheme && widget.isEditing)
                        ? Colors.transparent
                        : theme.background;
                final dotColor = theme.onSurface;
                return Positioned.fill(
                  child: IgnorePointer(
                    ignoring: widget.isEditing, // 편집 모드에서는 탭 무시, 읽기 모드에서는 탭 통과
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, __) {
                        return CustomPaint(
                          painter: _ParagraphSpoilerPainter(
                            boxes: boxes,
                            phase: _controller.value,
                            isEditing: widget.isEditing,
                            backgroundColor: bgColor,
                            dotColor: dotColor,
                            isLightTheme: isLightTheme,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            // 해제 시 점들이 흩어지는 스캐터 이펙트 (일회성)
            if (_scatterActive)
              Builder(
                builder: (context) {
                  final theme = Theme.of(context).colorScheme;
                  final brightness = Theme.of(context).brightness;
                  final dotColor = theme.onSurface;
                  final isLightTheme = brightness == Brightness.light;
                  return Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: AnimatedBuilder(
                        animation: _scatterCtrl,
                        builder: (context, __) {
                          return CustomPaint(
                            painter: _ParagraphSpoilerScatterPainter(
                              boxes: _scatterBoxes,
                              t: _scatterCtrl.value,
                              dotColor: dotColor,
                              isLightTheme: isLightTheme,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            if (showTop)
              const Positioned(
                top: 0,
                left: 20,
                right: 20,
                child: SizedBox(
                  height: 5,
                  child: ColoredBox(color: AppColors.primary),
                ),
              ),
            if (showBottom)
              const Positioned(
                bottom: 0,
                left: 20,
                right: 20,
                child: SizedBox(
                  height: 5,
                  child: ColoredBox(color: AppColors.primary),
                ),
              ),
          ],
        );

        // 읽기 모드에서 멘션 문단이면 탭 콜백 연결
        try {
          final node = widget.editorService.editor.document.getNodeById(
            widget.nodeId,
          );
          if (!widget.isEditing &&
              node is ParagraphNode &&
              node.metadata['mention'] == true &&
              widget.onMentionTap != null) {
            final List<String> names =
                ((node.metadata['usernames'] as List?)
                    ?.map((e) => e.toString())
                    .toList()) ??
                _extractUsernamesFromText(node.text.text);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onMentionTap!(names),
              child: stack,
            );
          }
        } catch (_) {}

        return stack;
      },
    );
  }

  TextAlign _resolveTextAlign() {
    TextAlign resolvedAlign = TextAlign.left;
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is ParagraphNode) {
        final alignName = node.metadata['textAlign'] as String?;
        if (alignName == 'center') {
          resolvedAlign = TextAlign.center;
        } else if (alignName == 'right') {
          resolvedAlign = TextAlign.right;
        } else if (alignName == 'left') {
          resolvedAlign = TextAlign.left;
        }
      }
    } catch (_) {}
    return resolvedAlign;
  }

  List<Rect> _collectSpoilerBoxes(
    BuildContext context,
    NodeComponentService nodeService,
  ) {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return const [];
      final text = node.text;

      // NodeComponentService에서 스포일러가 명시적으로 해제되었는지 먼저 확인
      // false가 저장되어 있으면 스포일러를 표시하지 않음
      final isDisabled = nodeService.isSpoilerDisabled(widget.nodeId);

      if (isDisabled) {
        return const []; // 스포일러가 해제되었으므로 표시하지 않음
      }

      // 스포일러 구간 수집: 텍스트는 같아도 attribution 변경에 즉시 반응해야 하므로 항상 재계산
      final calc = <TextRange>[];
      bool inSpoiler = false;
      int start = 0;
      for (int i = 0; i <= text.text.length; i++) {
        final attrs =
            i < text.text.length
                ? text.getAllAttributionsAt(i)
                : const <Attribution>{};
        final has = attrs.any(
          (a) => a is NamedAttribution && a.id == 'spoiler',
        );
        if (has && !inSpoiler) {
          inSpoiler = true;
          start = i;
        } else if (!has && inSpoiler) {
          inSpoiler = false;
          calc.add(TextRange(start: start, end: i));
        }
      }
      final List<TextRange> spans = calc;

      if (spans.isEmpty) {
        return const [];
      }

      // RenderParagraph 찾기
      final ctx = _subtreeKey.currentContext;
      if (ctx == null) return const [];
      final RenderObject? ro = ctx.findRenderObject();
      final rp = _findRenderParagraph(ro);
      if (rp == null) return const [];

      final paraOffset = (rp as RenderBox).localToGlobal(Offset.zero);
      final hostOffset =
          (context.findRenderObject() as RenderBox?)?.localToGlobal(
            Offset.zero,
          ) ??
          Offset.zero;

      // 새로운 방식: TextPainter 기반 라인 밴드로 안정적인 박스 계산
      final boxes = <Rect>[];
      const double vPad = 0.5;
      for (final r in spans) {
        boxes.addAll(
          _measureLineRectsForRange(
            rp,
            r.start,
            r.end,
            paraOffset,
            hostOffset,
            vPad: vPad,
          ),
        );
      }
      return boxes;
    } catch (_) {
      return const [];
    }
  }

  // 형광펜 구간을 수집하여 색상과 함께 반환
  List<_ColoredRect> _collectHighlightBoxes(BuildContext context) {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return const [];
      final text = node.text;

      // RenderParagraph
      final ctx = _subtreeKey.currentContext;
      if (ctx == null) return const [];
      final rp = _findRenderParagraph(ctx.findRenderObject());
      if (rp == null) return const [];
      final paraOffset = (rp as RenderBox).localToGlobal(Offset.zero);
      final hostOffset =
          (context.findRenderObject() as RenderBox?)?.localToGlobal(
            Offset.zero,
          ) ??
          Offset.zero;

      final List<_ColoredRect> out = [];

      Color? currentColor;
      int runStart = -1;
      for (int i = 0; i <= text.text.length; i++) {
        Color? colorAtI;
        if (i < text.text.length) {
          final atts = text.getAllAttributionsAt(i);
          for (final a in atts) {
            if (a is HighlightAttribution) {
              colorAtI = a.color;
              break;
            }
          }
        }

        final changed = (colorAtI?.value != currentColor?.value);
        if (changed) {
          if (runStart >= 0 && currentColor != null) {
            final rects = _measureLineRectsForRange(
              rp,
              runStart,
              i,
              paraOffset,
              hostOffset,
              vPad: 0.5,
            );
            for (final r in rects) {
              out.add(_ColoredRect(rect: r, color: currentColor));
            }
          }
          runStart = i;
          currentColor = colorAtI;
        }
      }

      return out;
    } catch (_) {
      return const [];
    }
  }

  List<String> _extractUsernamesFromText(String text) {
    if (text.isEmpty) return const [];
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.startsWith('@') && e.length > 1)
        .map((e) => e.substring(1))
        .toList();
  }
}

RenderParagraph? _findRenderParagraph(RenderObject? root) {
  if (root == null) return null;
  if (root is RenderParagraph) return root;
  RenderParagraph? found;
  root.visitChildren((child) {
    found ??= _findRenderParagraph(child);
  });
  return found;
}

// TextPainter로 [start,end) 범위를 라인 단위 직사각형으로 계산
List<Rect> _measureLineRectsForRange(
  RenderParagraph rp,
  int start,
  int end,
  Offset paraOffset,
  Offset hostOffset, {
  double vPad = 0.5,
}) {
  final renderBox = rp as RenderBox;
  final tp = TextPainter(
    text: rp.text,
    textAlign: rp.textAlign,
    textDirection: rp.textDirection,
    strutStyle: rp.strutStyle,
    textScaleFactor: rp.textScaleFactor,
    maxLines: rp.maxLines,
  );
  tp.layout(maxWidth: renderBox.size.width);
  final String fullText = rp.text.toPlainText();
  final List<TextRange> lineRanges = [];
  int cursor = 0;
  while (cursor < fullText.length) {
    final range = tp.getLineBoundary(TextPosition(offset: cursor));
    if (!range.isValid) break;
    lineRanges.add(range);
    if (range.end <= cursor) {
      cursor += 1; // 무한루프 방지 안전 증가
    } else {
      cursor = range.end;
    }
  }
  final List<Rect> rects = [];
  for (final lr in lineRanges) {
    final int lineStart = lr.start;
    final int lineEnd = lr.end;
    final int from = start < lineStart ? lineStart : start;
    final int to = end > lineEnd ? lineEnd : end;
    if (from >= to) continue;

    // 이 라인 구간의 selection 박스를 사용해 상하좌우 모두 안정적으로 계산
    final sel = TextSelection(baseOffset: from, extentOffset: to);
    final tboxes = rp.getBoxesForSelection(sel);
    if (tboxes.isEmpty) continue;

    double lineTopLocal = tboxes.map((b) => b.top).reduce(min) + vPad;
    double lineBottomLocal = tboxes.map((b) => b.bottom).reduce(max) - vPad;
    double lineLeftLocal = tboxes.map((b) => b.left).reduce(min);
    double lineRightLocal = tboxes.map((b) => b.right).reduce(max);

    // 좌표계 변환 (문단 → 호스트)
    final double dy = paraOffset.dy - hostOffset.dy;
    final double dx = paraOffset.dx - hostOffset.dx;
    rects.add(
      Rect.fromLTRB(
        dx + lineLeftLocal,
        dy + lineTopLocal,
        dx + lineRightLocal,
        dy + lineBottomLocal,
      ),
    );
  }
  return rects;
}

class _ParagraphSpoilerPainter extends CustomPainter {
  final List<Rect> boxes;
  final double phase; // 0..1
  final bool isEditing;
  final Color backgroundColor;
  final Color dotColor;
  final bool isLightTheme;
  _ParagraphSpoilerPainter({
    required this.boxes,
    required this.phase,
    required this.isEditing,
    required this.backgroundColor,
    required this.dotColor,
    required this.isLightTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (boxes.isEmpty) return;
    final mask = Paint()..style = PaintingStyle.fill;
    // 라이트/다크 기본 점 불투명도
    final baseDotOpacity = isLightTheme ? 0.6 : 0.85;
    final dot = Paint()..style = PaintingStyle.fill;

    // 박스 병합: 같은 줄(top/bottom 유사)에서 인접/겹치는 영역을 하나로 합쳐서
    // 공백 단위로 중복 렌더링되어 밝아지는 현상을 제거한다.
    final List<Rect> merged = _mergeBoxes(boxes);

    for (final rect in merged) {
      // 편집 모드: 반투명 배경으로 텍스트 가림
      // 읽기 모드: 완전 불투명 배경으로 텍스트 완전히 가림
      final double fillAlpha = isEditing ? 0.5 : 1.0;
      if (backgroundColor.alpha != 0 && fillAlpha > 0) {
        mask.color = backgroundColor.withOpacity(fillAlpha);
        canvas.drawRect(rect, mask);
      }
      // 점들 그리기
      final area = rect.width * rect.height;
      // 밀도는 모드에 관계없이 일관되게 유지
      final count =
          isEditing
              ? max(40, (area / 200).floor())
              : max(70, (area / 150).floor());
      final double t = phase * (2 * pi) * 0.85; // 텍스트는 느리게

      // 안쪽 인셋으로 에지 밴딩 방지
      final double inset = min(3.0, min(rect.width, rect.height) * 0.15);
      final double w = max(1.0, rect.width - inset * 2);
      final double h = max(1.0, rect.height - inset * 2);
      for (int i = 0; i < count; i++) {
        final seed = rect.hashCode ^ (i * 486187739);
        final r = Random(seed);
        final baseX = inset + r.nextDouble() * w;
        final baseY = inset + r.nextDouble() * h;
        // 개별 위상/진폭으로 패턴 정렬 방지
        final ampX = 1.0 + r.nextDouble() * 1.4;
        final ampY = 1.0 + r.nextDouble() * 1.4;
        final phaseShift = r.nextDouble() * 2 * pi;
        final ox =
            sin(t * (0.85 + r.nextDouble() * 0.5) + i * 0.13 + phaseShift) *
            ampX;
        final oy =
            cos(t * (0.9 + r.nextDouble() * 0.5) + i * 0.11 + phaseShift) *
            ampY;
        double x = baseX + ox;
        double y = baseY + oy;
        x = x % rect.width;
        y = y % rect.height;
        if (x < 0) x += rect.width;
        if (y < 0) y += rect.height;
        // 점 크기와 불투명도는 모드에 관계없이 일관되게
        final size = 1.0 + r.nextDouble() * 0.8;
        final opacity = (0.85 + r.nextDouble() * 0.15) * baseDotOpacity;
        final effectiveColor =
            (!isLightTheme && isEditing) ? Colors.white : dotColor;
        dot.color = effectiveColor.withOpacity(opacity.clamp(0.0, 1.0));
        canvas.drawRect(
          Rect.fromLTWH(rect.left + x, rect.top + y, size, size),
          dot,
        );
      }
    }
  }

  // 같은 줄에서 인접/겹치는 TextBox들을 묶어서 중복 렌더링을 제거
  List<Rect> _mergeBoxes(List<Rect> src) {
    if (src.length <= 1) return src;
    const double vTol = 1.0; // 상하 허용 오차
    const double hJoin = 1.5; // 수평 결합 간격 허용

    // 줄 그룹화: top/bottom이 비슷하면 같은 줄로 본다
    final List<List<Rect>> lines = [];
    for (final r in src..sort((a, b) => a.top.compareTo(b.top))) {
      bool placed = false;
      for (final line in lines) {
        final Rect ref = line.first;
        if ((r.top - ref.top).abs() < vTol &&
            (r.bottom - ref.bottom).abs() < vTol) {
          line.add(r);
          placed = true;
          break;
        }
      }
      if (!placed) lines.add([r]);
    }

    // 각 줄에서 좌우로 병합
    final List<Rect> merged = [];
    for (final line in lines) {
      line.sort((a, b) => a.left.compareTo(b.left));
      Rect? cur;
      for (final r in line) {
        if (cur == null) {
          cur = r;
          continue;
        }
        if (r.left <= cur.right + hJoin) {
          cur = Rect.fromLTRB(
            cur.left,
            min(cur.top, r.top),
            max(cur.right, r.right),
            max(cur.bottom, r.bottom),
          );
        } else {
          merged.add(cur);
          cur = r;
        }
      }
      if (cur != null) merged.add(cur);
    }
    return merged;
  }

  @override
  bool shouldRepaint(covariant _ParagraphSpoilerPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.boxes != boxes ||
        oldDelegate.isEditing != isEditing;
  }
}

// 스포일러 해제 시 파티클 흩어짐 이펙트
class _ParagraphSpoilerScatterPainter extends CustomPainter {
  final List<Rect> boxes;
  final double t; // 0..1 진행도
  final Color dotColor;
  final bool isLightTheme;
  _ParagraphSpoilerScatterPainter({
    required this.boxes,
    required this.t,
    required this.dotColor,
    required this.isLightTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (boxes.isEmpty) return;
    final baseOpacity = isLightTheme ? 0.5 : 0.7;
    final fade = (1.0 - Curves.easeOut.transform(t)).clamp(0.0, 1.0);
    final paint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = dotColor.withOpacity(baseOpacity * fade);

    for (final rect in boxes) {
      // 박스당 점 개수: 면적 기준 적당히
      final area = rect.width * rect.height;
      final count = max(50, (area / 220).floor());
      final cx = rect.center.dx;
      final cy = rect.center.dy;
      for (int i = 0; i < count; i++) {
        final seed = rect.hashCode ^ (i * 1009);
        final r = Random(seed);
        final rx = r.nextDouble() * rect.width;
        final ry = r.nextDouble() * rect.height;
        final startX = rect.left + rx;
        final startY = rect.top + ry;
        // 중심에서 방사형으로 퍼지는 속도/방향
        final dirX = (startX - cx);
        final dirY = (startY - cy);
        final dirLen = sqrt(dirX * dirX + dirY * dirY) + 0.001;
        final nx = dirX / dirLen;
        final ny = dirY / dirLen;
        final speed = 24 + r.nextDouble() * 36; // px
        final move = Curves.easeOutQuad.transform(t) * speed;
        final x = startX + nx * move;
        final y = startY + ny * move;
        // 크기/회전 랜덤, 점 크기 약간 확대 후 축소
        final sz = 1.0 + (1.6 * (1.0 - t));
        canvas.drawRect(Rect.fromLTWH(x, y, sz, sz), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParagraphSpoilerScatterPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.boxes != boxes;
  }
}

class _ColoredRect {
  final Rect rect;
  final Color color;
  const _ColoredRect({required this.rect, required this.color});
}

class _ParagraphHighlightPainter extends CustomPainter {
  final List<_ColoredRect> highlights;
  const _ParagraphHighlightPainter({required this.highlights});

  @override
  void paint(Canvas canvas, Size size) {
    if (highlights.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final h in highlights) {
      paint.color = h.color.withOpacity(0.35);
      canvas.drawRect(h.rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParagraphHighlightPainter oldDelegate) {
    return oldDelegate.highlights != highlights;
  }
}

/// 구분선 전용 DocumentComponent
class _DividerDocumentComponent extends StatefulWidget {
  const _DividerDocumentComponent({
    required this.nodeId,
    required GlobalKey componentKey,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final GlobalKey _componentKey;

  @override
  State<_DividerDocumentComponent> createState() =>
      _DividerDocumentComponentState();
}

class _DividerDocumentComponentState extends State<_DividerDocumentComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: double.infinity,
        height: 1.5,
        color: const Color(0xFFE5E5EA),
      ),
    );
  }

  // Minimal DocumentComponent implementation
  @override
  NodePosition getBeginningPosition() =>
      UpstreamDownstreamNodePosition.upstream();

  @override
  NodePosition getEndPosition() => UpstreamDownstreamNodePosition.downstream();

  @override
  NodePosition? getPositionAtOffset(Offset localOffset) =>
      UpstreamDownstreamNodePosition.upstream();

  @override
  Offset getOffsetForPosition(NodePosition nodePosition) => Offset.zero;

  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return Rect.zero;
    return Offset.zero & renderBox.size;
  }

  @override
  Rect getRectForSelection(
    NodePosition baseNodePosition,
    NodePosition extentNodePosition,
  ) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return Rect.zero;
    return Offset.zero & renderBox.size;
  }

  @override
  NodeSelection getCollapsedSelectionAt(NodePosition nodePosition) =>
      UpstreamDownstreamNodeSelection(
        base: UpstreamDownstreamNodePosition.upstream(),
        extent: UpstreamDownstreamNodePosition.upstream(),
      );

  @override
  NodeSelection getSelectionBetween({
    required NodePosition basePosition,
    required NodePosition extentPosition,
  }) => UpstreamDownstreamNodeSelection(
    base: UpstreamDownstreamNodePosition.upstream(),
    extent: UpstreamDownstreamNodePosition.downstream(),
  );

  @override
  NodeSelection? getSelectionInRange(
    Offset localBaseOffset,
    Offset localExtentOffset,
  ) => null;

  @override
  NodeSelection getSelectionOfEverything() => UpstreamDownstreamNodeSelection(
    base: UpstreamDownstreamNodePosition.upstream(),
    extent: UpstreamDownstreamNodePosition.downstream(),
  );

  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return Rect.zero;
    return Offset.zero & renderBox.size;
  }

  @override
  bool isVisualSelectionSupported() => false;

  @override
  NodePosition? movePositionLeft(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) => null;

  @override
  NodePosition? movePositionRight(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) => null;

  @override
  NodePosition? movePositionUp(NodePosition currentPosition) => null;

  @override
  NodePosition? movePositionDown(NodePosition currentPosition) => null;

  @override
  NodePosition getBeginningPositionNearX(double x) =>
      UpstreamDownstreamNodePosition.upstream();

  @override
  NodePosition getEndPositionNearX(double x) =>
      UpstreamDownstreamNodePosition.downstream();

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;
}
