import 'package:doppy/editor/component/row_image_component.dart';
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

/// 패키지 기본 ParagraphComponent를 사용하고,
/// 드래그 드롭 라인만 오버레이로 추가하는 경량 커스텀 빌더
class CustomParagraphComponentBuilder implements ComponentBuilder {
  const CustomParagraphComponentBuilder({
    required this.dragService,
    required this.editorService,
    this.isEditing = true,
  });

  final DragService dragService;
  final EditorService editorService;
  final bool isEditing;
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
  });

  final String nodeId;
  final DragService dragService;
  final EditorService editorService;
  final bool isEditing;
  final Widget child;

  @override
  State<_ParagraphWithDropLines> createState() =>
      _ParagraphWithDropLinesState();
}

class _ParagraphWithDropLinesState extends State<_ParagraphWithDropLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _subtreeKey = GlobalKey();
  // 스포일러 범위 캐싱 (텍스트가 바뀔 때만 재계산)
  String? _lastTextSnapshot;
  List<TextRange>? _cachedSpoilerRanges;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 1500));
  }

  @override
  void dispose() {
    _controller.dispose();
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
                  prev is LinkNode ||
                  (prev is ParagraphNode && prev.metadata['mention'] == true)) {
                showTop = false;
              }
            }
          } catch (_) {}
        }

        // 문단 내부 스포일러 박스 계산 (문단 로컬 좌표)
        final boxes = _collectSpoilerBoxes(context, nodeService);

        Widget content = DefaultTextStyle.merge(
          textAlign: _resolveTextAlign(),
          child: KeyedSubtree(key: _subtreeKey, child: widget.child),
        );

        return Stack(
          children: [
            Container(margin: const EdgeInsets.only(top: 4), child: content),
            // 문단 위에 직접 글리터 렌더링 (로컬 좌표기준이라 오프셋 불필요)
            // 읽기 모드이고 스포일러가 있을 때는 탭 이벤트를 통과시켜야 함
            if (boxes.isNotEmpty)
              Builder(
                builder: (context) {
                  final theme = Theme.of(context).colorScheme;
                  final brightness = Theme.of(context).brightness;
                  final bgColor = theme.background;
                  final dotColor = theme.onSurface;
                  final isLightTheme = brightness == Brightness.light;
                  return Positioned.fill(
                    child: IgnorePointer(
                      ignoring:
                          widget.isEditing, // 편집 모드에서는 탭 무시, 읽기 모드에서는 탭 통과
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
            if (showTop)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 5,
                  child: ColoredBox(color: AppColors.primary),
                ),
              ),
            if (showBottom)
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 5,
                  child: ColoredBox(color: AppColors.primary),
                ),
              ),
          ],
        );
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
      print(
        '[ParagraphComponent] _collectSpoilerBoxes: nodeId=${widget.nodeId}, isSpoilerDisabled=$isDisabled',
      );
      if (isDisabled) {
        print('[ParagraphComponent] 스포일러 해제됨 - 빈 리스트 반환');
        return const []; // 스포일러가 해제되었으므로 표시하지 않음
      }

      // 스포일러 구간 수집 (텍스트 스냅샷이 변할 때만 재계산)
      List<TextRange> spans;
      final snapshot = text.text;
      if (_lastTextSnapshot != snapshot || _cachedSpoilerRanges == null) {
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
        _lastTextSnapshot = snapshot;
        _cachedSpoilerRanges = calc;
        spans = calc;
      } else {
        spans = _cachedSpoilerRanges!;
      }

      if (spans.isEmpty) {
        // 디버깅: 스포일러가 없는지 확인
        print(
          '[ParagraphComponent] 스포일러 구간 없음: nodeId=${widget.nodeId}, 텍스트 길이=${text.text.length}',
        );
        return const [];
      }
      print(
        '[ParagraphComponent] 스포일러 구간 발견: nodeId=${widget.nodeId}, 구간 수=${spans.length}',
      );

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

      final boxes = <Rect>[];
      for (final r in spans) {
        final sel = TextSelection(baseOffset: r.start, extentOffset: r.end);
        final tb = rp.getBoxesForSelection(sel);
        for (final b in tb) {
          // 글로벌 → 이 컴포넌트(Stack) 로컬 좌표
          final rect = b.toRect().shift(paraOffset - hostOffset);
          boxes.add(rect.inflate(1.0));
        }
      }
      return boxes;
    } catch (_) {
      return const [];
    }
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
    final mask =
        Paint()
          ..style = PaintingStyle.fill
          ..color = backgroundColor.withOpacity(isEditing ? 0.5 : 1.0);
    // 라이트 테마일 때는 점 색상을 더 연하게
    final dotOpacity = isLightTheme ? 0.6 : 0.75;
    final dot =
        Paint()
          ..style = PaintingStyle.fill
          ..color = dotColor.withOpacity(dotOpacity);

    for (final rect in boxes) {
      canvas.drawRect(rect, mask);
      // 밀도 높은 1px 점들
      final area = rect.width * rect.height;
      // 글쓰기 모드(isEditing=true)에서는 밀도 낮춤
      final count =
          isEditing
              ? max(40, (area / 200).floor())
              : max(60, (area / 150).floor());
      final double t = phase * (2 * pi) * 0.9; // 텍스트는 느리게
      for (int i = 0; i < count; i++) {
        final seed = rect.hashCode ^ (i * 486187739);
        final r = Random(seed);
        final baseX = r.nextDouble() * rect.width;
        final baseY = r.nextDouble() * rect.height;
        // 진동 기반 이동 (자글자글 효과)
        final amp = 1.6 + r.nextDouble() * 1; // 1.6~3.2px (덜 요란)
        final ox = sin(t + i * 0.17) * amp;
        final oy = cos(t * 1.1 + i * 0.11) * amp;
        double x = baseX + ox;
        double y = baseY + oy;
        x = x % rect.width;
        y = y % rect.height;
        if (x < 0) x += rect.width;
        if (y < 0) y += rect.height;
        canvas.drawRect(Rect.fromLTWH(rect.left + x, rect.top + y, 1, 1), dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParagraphSpoilerPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.boxes != boxes ||
        oldDelegate.isEditing != isEditing;
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
