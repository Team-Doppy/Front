import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../editor/config/drop_line_config.dart';
import '../../editor/service/drag_service.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/style/text_attributions.dart';
import '../../editor/utils/animated_drop_line.dart';
import '../../editor/utils/list_paragraph_meta.dart';
import '../config/editor_config.dart';
import '../utils/editor_localization.dart';
import 'dart:math';
import 'dart:ui' show BoxHeightStyle, BoxWidthStyle;
import 'package:super_editor/super_editor.dart';
import 'package:provider/provider.dart';

const double _kListPrefixWidth = 28.0;

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
      if (node is ParagraphNode) {
        if (node.metadata['isDivider'] == true) {
          return _DividerDocumentComponent(
            nodeId: componentViewModel.nodeId,
            componentKey: componentContext.componentKey,
          );
        }
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

/// 리스트 문단용 prefix (1. / • / ☐☑)
/// [lineHeightPx] 문단 실제 라인 높이 (텍스트와 베이스라인 맞추기 위해 전달)
class _ListPrefixWidget extends StatelessWidget {
  const _ListPrefixWidget({
    required this.nodeId,
    required this.editorService,
    required this.isEditing,
    required this.lineHeightPx,
  });

  final String nodeId;
  final EditorService editorService;
  final bool isEditing;
  final double lineHeightPx;

  @override
  Widget build(BuildContext context) {
    // 🎯 메타데이터는 build 시점에 문서에서 다시 읽는다.
    // (ReplaceNodeRequest로 prefix on/off 될 때 즉시 UI 갱신되도록)
    ParagraphNode? node;
    try {
      final n = editorService.editor.document.getNodeById(nodeId);
      if (n is ParagraphNode) node = n;
    } catch (_) {}
    if (node == null) return const SizedBox.shrink();

    final listType = ListParagraphMeta.getListType(node.metadata);
    if (listType == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final fontSize = EditorConfig.defaultBodyFontSize;
    final color = theme.colorScheme.onSurface.withOpacity(0.6);

    if (listType == ListParagraphMeta.typeChecklist) {
      final checked = ListParagraphMeta.isChecked(node.metadata);
      return GestureDetector(
        onTap: isEditing
            ? () {
                editorService.toggleParagraphChecklist(nodeId);
              }
            : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: lineHeightPx,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: checked ? theme.colorScheme.primary : color,
            ),
          ),
        ),
      );
    }

    if (listType == ListParagraphMeta.typeNumbered) {
      final prefix = '${ListParagraphMeta.getListIndex(node.metadata)}.';
      return SizedBox(
        height: lineHeightPx,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            prefix,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
              height: EditorConfig.defaultLineHeight,
            ),
          ),
        ),
      );
    }

    if (listType == ListParagraphMeta.typeQuote) {
      // 인용: 세로선(아이콘) 프리픽스
      return SizedBox(
        height: lineHeightPx,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ),
      );
    }

    // 불릿 포인트
    return SizedBox(
      height: lineHeightPx,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Icon(
          Icons.circle,
          size: 12,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
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
  // ✅ 스포일러/형광펜이 실제로 그려지는 Stack의 좌표계를 고정하기 위한 키
  final GlobalKey _paintHostKey = GlobalKey();

  // 스포일러 해제(리빌) 파티클 이펙트
  late final AnimationController _scatterCtrl;
  bool _scatterActive = false;
  List<Rect> _scatterBoxes = const [];
  bool _wasMaskVisible = false;
  List<Rect> _prevBoxes = const [];
  bool _spoilerBoxRetryScheduled = false;
  // 🎯 형광펜도 스포일러처럼 "이전 박스 유지 + 1프레임 재시도"로 깜빡임/끊김 방지
  List<_ColoredRect> _prevHighlightRects = const [];
  bool _highlightBoxRetryScheduled = false;
  // Undo/redo can swap the underlying text layout while reusing the same widget
  // state (same nodeId). Only keep previous boxes when attribution spans are unchanged.
  String _lastSpoilerSpanSig = '';
  String _lastHighlightSpanSig = '';

  double _estimateParagraphFontSize() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return EditorConfig.defaultBodyFontSize;
      final isTitle = node.metadata[EditorConfig.titleNodeMetadataKey] == true;
      final text = node.text;
      if (text.text.isEmpty) {
        return isTitle
            ? EditorConfig.defaultTitleFontSize
            : EditorConfig.defaultBodyFontSize;
      }
      final attrs = text.getAllAttributionsAt(0);
      for (final a in attrs) {
        if (a is FontSizeAttribution) return a.fontSize;
      }
      return isTitle
          ? EditorConfig.defaultTitleFontSize
          : EditorConfig.defaultBodyFontSize;
    } catch (_) {
      return EditorConfig.defaultBodyFontSize;
    }
  }

  bool _isTitleNode() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      return node is ParagraphNode &&
          node.metadata[EditorConfig.titleNodeMetadataKey] == true;
    } catch (_) {
      return false;
    }
  }

  bool _isParagraphEmpty() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      return node is ParagraphNode ? node.text.text.isEmpty : true;
    } catch (_) {
      return true;
    }
  }

  String _computeSpoilerSpanSignature() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return '';
      final text = node.text;

      final parts = <String>[];
      bool inSpoiler = false;
      int start = 0;
      for (int i = 0; i <= text.text.length; i++) {
        final attrs = i < text.text.length
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
          parts.add('$start-$i');
        }
      }
      return parts.join(',');
    } catch (_) {
      return '';
    }
  }

  String _computeHighlightSpanSignature() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return '';
      final text = node.text;

      final parts = <String>[];
      Color? currentColor;
      int runStart = -1;
      for (int i = 0; i <= text.text.length; i++) {
        Color? colorAtI;
        if (i < text.text.length) {
          final attrs = text.getAllAttributionsAt(i);
          for (final a in attrs) {
            if (a is HighlightAttribution) {
              colorAtI = a.color;
              break;
            }
          }
        }

        if (colorAtI != currentColor) {
          if (currentColor != null && runStart != -1) {
            parts.add('$runStart-$i:${currentColor.value}');
          }
          currentColor = colorAtI;
          runStart = currentColor != null ? i : -1;
        }
      }
      return parts.join(',');
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 1500));
    _scatterCtrl =
        AnimationController(
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
    // 🎯 성능 최적화: 편집 모드와 보기 모드에 따라 리스너 최소화
    final nodeService = Provider.of<NodeComponentService>(
      context,
      listen: false,
    );

    // 🎯 보기 모드: 초경량 위젯 트리 (스포일러만 처리)
    if (!widget.isEditing) {
      return _buildReadOnlyView(context, nodeService);
    }

    // 드래그 관련 애니메이션만 필수로 리스닝
    final dragAnimation = Listenable.merge([
      widget.dragService,
      widget.editorService,
      widget.editorService.editor.composer,
    ]);

    // 🎯 스포일러 토글 직후에도 즉시 반영되도록 nodeService는 항상 리스닝하고,
    // hasSpoiler 계산은 builder 내부에서 수행한다.
    final animation = Listenable.merge([dragAnimation, nodeService]);
    final theme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // 🎯 builder 내부에서 계산해야(값 캡처 방지) 토글 직후 바로 반영됨
        final hasSpoiler = _hasSpoilerAttribution();
        // ✅ 드롭라인 표시는 공통 정책(DropLineConfig)으로 통일
        final flags = DropLineConfig.resolve(
          nodeId: widget.nodeId,
          dragService: widget.dragService,
        );
        final bool showTop = flags.top;
        final bool showBottom = flags.bottom;

        Widget content = DefaultTextStyle.merge(
          textAlign: _resolveTextAlign(),
          child: KeyedSubtree(key: _subtreeKey, child: widget.child),
        );

        // 🎯 리스트/인용 prefix는 build 시점에 문서 메타데이터로 결정한다.
        // (ReplaceNodeRequest로 listType on/off 시 즉시 반영되도록)
        try {
          final node = widget.editorService.editor.document.getNodeById(
            widget.nodeId,
          );
          if (node is ParagraphNode) {
            final listType = ListParagraphMeta.getListType(node.metadata);
            if (listType != null) {
              final prefixWidth =
                  listType == ListParagraphMeta.typeChecklist ||
                      listType == ListParagraphMeta.typeQuote
                  ? _kListPrefixWidth + 6
                  : _kListPrefixWidth + 12;
              final lineH =
                  (_estimateParagraphFontSize() *
                          EditorConfig.defaultLineHeight)
                      .clamp(20.0, 999.0);
              content = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (listType != ListParagraphMeta.typeChecklist &&
                      listType != ListParagraphMeta.typeQuote)
                    const SizedBox(width: 6),
                  SizedBox(
                    width: _kListPrefixWidth,
                    child: _ListPrefixWidget(
                      nodeId: widget.nodeId,
                      editorService: widget.editorService,
                      isEditing: widget.isEditing,
                      lineHeightPx: lineH,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: content),
                  SizedBox(width: prefixWidth),
                ],
              );
            }
          }
        } catch (_) {}

        Widget stack = Stack(
          key: _paintHostKey,
          children: [
            // 폰트 사이즈에 따라 문단 상단 여백/최소 높이를 유동적으로 조절하여
            // 작은 폰트일 때 아래 노드들이 자연스럽게 위로 당겨지도록 한다.
            // 타이틀(isTitle 메타데이터)은 일반 문단과 동일한 패딩·스택 구조.
            Padding(
              padding: EdgeInsets.only(
                top: (_estimateParagraphFontSize() * 0.34).clamp(2.0, 5.5),
                bottom: showBottom ? 4 : 0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // 빈 문단은 caret/tap 영역 확보를 위해 최소 높이 유지
                  // 제목 노드 힌트는 폰트가 크므로 minHeight도 폰트에 맞춰야 잘림 방지
                  minHeight: _isParagraphEmpty()
                      ? (_isTitleNode()
                            ? (_estimateParagraphFontSize() *
                                      EditorConfig.defaultLineHeight)
                                  .clamp(22.0, 999)
                            : 22)
                      : (_estimateParagraphFontSize() *
                                EditorConfig.defaultLineHeight)
                            .clamp(0.0, 999),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    content,
                    // 🎯 항상 트리에 유지하고 Opacity로 숨김 → IME 조합 중 리빌드로 한글 깨짐 방지
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: (_isTitleNode() && _isParagraphEmpty())
                              ? 1
                              : 0,
                          child: Align(
                            alignment: _hintAlignmentFromTextAlign(
                              _resolveTextAlign(),
                            ),
                            child: Padding(
                              padding: _hintPaddingFromTextAlign(
                                _resolveTextAlign(),
                              ),
                              child: Text(
                                EditorTranslations.translate(
                                  'editor_title_required',
                                ),
                                textAlign: _resolveTextAlign(),
                                style: TextStyle(
                                  fontSize: _estimateParagraphFontSize(),
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.2),
                                  height: EditorConfig.defaultLineHeight,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 🎯 형광펜 오버레이 (편집 모드에서만)
            Builder(
              builder: (context) {
                // If attribution spans changed (e.g., undo/redo restore), drop cached boxes so
                // we don't render stale geometry until a layout pass completes.
                final hiSig = _computeHighlightSpanSignature();
                if (hiSig != _lastHighlightSpanSig) {
                  _lastHighlightSpanSig = hiSig;
                  _prevHighlightRects = const [];
                }

                final hi = _collectHighlightBoxes(context);
                final hasHighlight = _hasHighlightAttribution();
                // 레이아웃 갱신 타이밍(특히 글자 입력/폰트 사이즈 변경)에는 hi가 잠깐 비는 경우가 있음
                // → 스포일러와 동일하게 1프레임 재시도 + 이전 박스 유지
                if (hasHighlight &&
                    hi.isEmpty &&
                    !_highlightBoxRetryScheduled) {
                  _highlightBoxRetryScheduled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _highlightBoxRetryScheduled = false;
                    if (mounted) setState(() {});
                  });
                }

                final effective = hi.isNotEmpty
                    ? hi
                    : (hasHighlight
                          ? _prevHighlightRects
                          : const <_ColoredRect>[]);

                if (effective.isNotEmpty) {
                  _prevHighlightRects = effective;
                } else if (!hasHighlight && _prevHighlightRects.isNotEmpty) {
                  // 형광펜이 실제로 제거된 경우 캐시도 즉시 비움
                  _prevHighlightRects = const [];
                }

                if (effective.isEmpty) return const SizedBox.shrink();
                return Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _ParagraphHighlightPainter(
                          highlights: effective,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // 🎯 스포일러 오버레이 (스포일러가 있을 때만)
            if (hasSpoiler)
              Builder(
                builder: (context) {
                  final spSig = _computeSpoilerSpanSignature();
                  if (spSig != _lastSpoilerSpanSig) {
                    _lastSpoilerSpanSig = spSig;
                    _prevBoxes = const [];
                  }

                  final boxes = _collectSpoilerBoxes(context, nodeService);
                  // 🎯 토글 직후 첫 프레임에는 RenderParagraph 레이아웃이 아직 반영 전이라
                  // boxes가 비는 경우가 있음 → 다음 프레임에 1회 setState로 재계산
                  final isDisabled = nodeService.isSpoilerDisabled(
                    widget.nodeId,
                  );
                  if (!isDisabled &&
                      boxes.isEmpty &&
                      !_spoilerBoxRetryScheduled) {
                    _spoilerBoxRetryScheduled = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _spoilerBoxRetryScheduled = false;
                      if (mounted) setState(() {});
                    });
                  }
                  // 🎯 형광펜과 동일하게: 레이아웃 갱신 순간 boxes가 잠깐 비면 이전 박스를 유지해서 깜빡임 방지
                  final effectiveBoxes = (!isDisabled && boxes.isEmpty)
                      ? _prevBoxes
                      : boxes;
                  final bool maskVisible = effectiveBoxes.isNotEmpty;

                  if (maskVisible) {
                    _prevBoxes = effectiveBoxes;
                  }

                  if (_wasMaskVisible &&
                      !maskVisible &&
                      _scatterCtrl.status != AnimationStatus.forward) {
                    _scatterBoxes = _prevBoxes;
                    if (_scatterBoxes.isNotEmpty) {
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

                  if (effectiveBoxes.isEmpty) return const SizedBox.shrink();

                  final theme = Theme.of(context).colorScheme;
                  final brightness = Theme.of(context).brightness;
                  final isLightTheme = brightness == Brightness.light;
                  final bgColor = (!isLightTheme && widget.isEditing)
                      ? Colors.transparent
                      : theme.background;
                  final dotColor = theme.onSurface;

                  return Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, __) {
                          return RepaintBoundary(
                            child: CustomPaint(
                              painter: _ParagraphSpoilerPainter(
                                boxes: effectiveBoxes,
                                phase: _controller.value,
                                isEditing: true,
                                backgroundColor: bgColor,
                                dotColor: dotColor,
                                isLightTheme: isLightTheme,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            // 🎯 스캐터 이펙트 (해제 시)
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
                          return RepaintBoundary(
                            child: CustomPaint(
                              painter: _ParagraphSpoilerScatterPainter(
                                boxes: _scatterBoxes,
                                t: _scatterCtrl.value,
                                dotColor: dotColor,
                                isLightTheme: isLightTheme,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            if (showTop)
              Positioned(
                top: 0,
                left: 50,
                right: 50,
                child: AnimatedDropLine(
                  child: SizedBox(
                    height: 5,
                    child: ColoredBox(color: theme.primary),
                  ),
                ),
              ),
            if (showBottom)
              Positioned(
                bottom: 0,
                left: 50,
                right: 50,
                child: AnimatedDropLine(
                  child: SizedBox(
                    height: 5,
                    child: ColoredBox(color: theme.primary),
                  ),
                ),
              ),
          ],
        );

        return stack;
      },
    );
  }

  /// 🎯 보기 모드 전용: 초경량 위젯 트리 (스포일러만 처리)
  Widget _buildReadOnlyView(
    BuildContext context,
    NodeComponentService nodeService,
  ) {
    Widget content = DefaultTextStyle.merge(
      textAlign: _resolveTextAlign(),
      child: KeyedSubtree(key: _subtreeKey, child: widget.child),
    );

    // 🎯 보기 모드에서도 리스트/인용 prefix 반영 (편집 모드와 동일)
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is ParagraphNode) {
        final listType = ListParagraphMeta.getListType(node.metadata);
        if (listType != null) {
          final prefixWidth =
              listType == ListParagraphMeta.typeChecklist ||
                  listType == ListParagraphMeta.typeQuote
              ? _kListPrefixWidth + 6
              : _kListPrefixWidth + 12;
          final lineH =
              (_estimateParagraphFontSize() * EditorConfig.defaultLineHeight)
                  .clamp(20.0, 999.0);
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (listType != ListParagraphMeta.typeChecklist &&
                  listType != ListParagraphMeta.typeQuote)
                const SizedBox(width: 6),
              SizedBox(
                width: _kListPrefixWidth,
                child: _ListPrefixWidget(
                  nodeId: widget.nodeId,
                  editorService: widget.editorService,
                  isEditing: false,
                  lineHeightPx: lineH,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: content),
              SizedBox(width: prefixWidth),
            ],
          );
        }
      }
    } catch (_) {}

    // TODO: MentionNode로 전환 후 탭 처리 예정
    Widget wrappedContent = content;

    // ✅ 보기 모드에서도 형광펜(HighlightAttribution)은 렌더링해야 한다.
    // 기존 구현은 스포일러만 처리해서 형광펜이 "아예" 안 보였음.
    final hasSpoiler = _hasSpoilerAttribution();
    final hasHighlight = _hasHighlightAttribution();

    // ✅ 하이라이트 박스는 레이아웃 타이밍(특히 첫 프레임)에는 잠깐 비는 경우가 있어서
    // 편집 모드와 동일하게 "이전 박스 유지 + 1프레임 재시도"를 적용한다.
    List<_ColoredRect> highlightRects = const [];
    if (hasHighlight) {
      final hi = _collectHighlightBoxes(context);
      if (hi.isEmpty && !_highlightBoxRetryScheduled) {
        _highlightBoxRetryScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _highlightBoxRetryScheduled = false;
          if (mounted) setState(() {});
        });
      }
      highlightRects = hi.isNotEmpty ? hi : _prevHighlightRects;
      if (highlightRects.isNotEmpty) {
        _prevHighlightRects = highlightRects;
      }
    } else if (_prevHighlightRects.isNotEmpty) {
      _prevHighlightRects = const [];
    }

    // 🎯 스포일러가 없으면 "텍스트 + (있다면) 하이라이트"만 그린다.
    if (!hasSpoiler) {
      return RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.only(
            top: (_estimateParagraphFontSize() * 0.34).clamp(2.0, 5.5),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: _isParagraphEmpty()
                  ? 22
                  : (_estimateParagraphFontSize() *
                            EditorConfig.defaultLineHeight)
                        .clamp(0.0, 999),
            ),
            child: Stack(
              key: _paintHostKey,
              children: [
                if (highlightRects.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _ParagraphHighlightPainter(
                            highlights: highlightRects,
                          ),
                        ),
                      ),
                    ),
                  ),
                wrappedContent,
              ],
            ),
          ),
        ),
      );
    }

    // 🎯 스포일러가 있을 때만 복잡한 위젯 트리 구성
    final spoilerWidget = _SpoilerReadOnlyWidget(
      nodeId: widget.nodeId,
      subtreeKey: _subtreeKey,
      controller: _controller,
      scatterCtrl: _scatterCtrl,
      editorService: widget.editorService,
      nodeService: nodeService,
      wrappedContent: wrappedContent,
      onScatterActiveChanged: (active) {
        if (mounted) {
          setState(() => _scatterActive = active);
        }
      },
      scatterActive: _scatterActive,
      wasMaskVisible: _wasMaskVisible,
      prevBoxes: _prevBoxes,
      onStateChanged: (wasMaskVisible, prevBoxes, scatterBoxes) {
        if (mounted) {
          _wasMaskVisible = wasMaskVisible;
          _prevBoxes = prevBoxes;
          _scatterBoxes = scatterBoxes;
        }
      },
    );

    // ✅ 스포일러가 있더라도, 형광펜 배경은 텍스트 아래 레이어로 같이 그린다.
    // (실제로 스포일러 마스크가 덮이면 보이지 않을 수 있지만, 토글/해제 직후 자연스럽게 복원됨)
    if (highlightRects.isEmpty) return spoilerWidget;
    return Stack(
      key: _paintHostKey,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ParagraphHighlightPainter(highlights: highlightRects),
              ),
            ),
          ),
        ),
        spoilerWidget,
      ],
    );
  }

  /// 스포일러 attribution이 있는지 빠르게 체크 (렌더링 없이)
  bool _hasSpoilerAttribution() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return false;
      final text = node.text;

      // 텍스트에 스포일러 attribution이 하나라도 있는지만 체크
      for (int i = 0; i < text.text.length; i++) {
        final attrs = text.getAllAttributionsAt(i);
        if (attrs.any((a) => a is NamedAttribution && a.id == 'spoiler')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 형광펜 attribution이 있는지 빠르게 체크 (렌더링 없이)
  bool _hasHighlightAttribution() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return false;
      final text = node.text;
      for (int i = 0; i < text.text.length; i++) {
        final attrs = text.getAllAttributionsAt(i);
        if (attrs.any((a) => a is HighlightAttribution)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
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

  Alignment _hintAlignmentFromTextAlign(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }

  EdgeInsets _hintPaddingFromTextAlign(TextAlign align) {
    // 커서에 딱 붙게 여백 없이
    const h = EditorConfig.horizontalPadding;
    switch (align) {
      case TextAlign.center:
        return const EdgeInsets.symmetric(horizontal: h);
      case TextAlign.right:
        return EdgeInsets.zero;
      default:
        return EdgeInsets.zero;
    }
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
        final attrs = i < text.text.length
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

      final paraBox = rp as RenderBox;
      final hostBox =
          (_paintHostKey.currentContext?.findRenderObject() as RenderBox?) ??
          (this.context.findRenderObject() as RenderBox?);
      if (hostBox == null) return const [];

      // 🎯 선택 영역(보라색)과 동일한 방식: RenderParagraph.getBoxesForSelection 기반 박스 계산
      final boxes = <Rect>[];
      for (final r in spans) {
        boxes.addAll(
          _measureSelectionRectsForRange(rp, r.start, r.end, paraBox, hostBox),
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
      final paraBox = rp as RenderBox;
      final hostBox =
          (_paintHostKey.currentContext?.findRenderObject() as RenderBox?) ??
          (this.context.findRenderObject() as RenderBox?);
      if (hostBox == null) return const [];

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
            final rects = _measureSelectionRectsForRange(
              rp,
              runStart,
              i,
              paraBox,
              hostBox,
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

  // NOTE: 예전 멘션 처리 로직의 잔재. 현재는 사용하지 않으므로 제거.
}

/// 🎯 스포일러가 있는 읽기 모드 패러그래프 전용 위젯
/// 상태 관리를 독립적으로 수행하여 다른 노드에 영향을 주지 않음
class _SpoilerReadOnlyWidget extends StatefulWidget {
  const _SpoilerReadOnlyWidget({
    required this.nodeId,
    required this.subtreeKey,
    required this.controller,
    required this.scatterCtrl,
    required this.editorService,
    required this.nodeService,
    required this.wrappedContent,
    required this.onScatterActiveChanged,
    required this.scatterActive,
    required this.wasMaskVisible,
    required this.prevBoxes,
    required this.onStateChanged,
  });

  final String nodeId;
  final GlobalKey subtreeKey;
  final AnimationController controller;
  final AnimationController scatterCtrl;
  final EditorService editorService;
  final NodeComponentService nodeService;
  final Widget wrappedContent;
  final void Function(bool) onScatterActiveChanged;
  final bool scatterActive;
  final bool wasMaskVisible;
  final List<Rect> prevBoxes;
  final void Function(
    bool wasMaskVisible,
    List<Rect> prevBoxes,
    List<Rect> scatterBoxes,
  )
  onStateChanged;

  @override
  State<_SpoilerReadOnlyWidget> createState() => _SpoilerReadOnlyWidgetState();
}

class _SpoilerReadOnlyWidgetState extends State<_SpoilerReadOnlyWidget> {
  bool _wasMaskVisible = false;
  List<Rect> _prevBoxes = const [];
  final GlobalKey _paintHostKey = GlobalKey();

  double _estimateParagraphFontSize() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return EditorConfig.defaultBodyFontSize;
      final isTitle = node.metadata[EditorConfig.titleNodeMetadataKey] == true;
      final text = node.text;
      if (text.text.isEmpty) {
        return isTitle
            ? EditorConfig.defaultTitleFontSize
            : EditorConfig.defaultBodyFontSize;
      }
      final attrs = text.getAllAttributionsAt(0);
      for (final a in attrs) {
        if (a is FontSizeAttribution) return a.fontSize;
      }
      return isTitle
          ? EditorConfig.defaultTitleFontSize
          : EditorConfig.defaultBodyFontSize;
    } catch (_) {
      return EditorConfig.defaultBodyFontSize;
    }
  }

  bool _isParagraphEmpty() {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      return node is ParagraphNode ? node.text.text.isEmpty : true;
    } catch (_) {
      return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _wasMaskVisible = widget.wasMaskVisible;
    _prevBoxes = widget.prevBoxes;

    // 초기 렌더링 후 박스 계산을 위한 리빌드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.nodeService,
      builder: (context, _) {
        final spoilerBoxes = _collectSpoilerBoxes(context);
        final bool maskVisible = spoilerBoxes.isNotEmpty;

        // 현재 마스크가 보이면 박스 저장
        if (maskVisible) {
          _prevBoxes = spoilerBoxes;
        }

        // 🎯 스포일러가 해제되었을 때 스캐터 애니메이션 트리거
        if (_wasMaskVisible &&
            !maskVisible &&
            widget.scatterCtrl.status != AnimationStatus.forward) {
          if (_prevBoxes.isNotEmpty) {
            // 상태를 부모에 전달
            widget.onStateChanged(_wasMaskVisible, _prevBoxes, _prevBoxes);

            // 다음 프레임에 스캐터 시작
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                widget.onScatterActiveChanged(true);
                widget.scatterCtrl
                  ..reset()
                  ..forward();
              }
            });
          }
        }
        _wasMaskVisible = maskVisible;

        return Padding(
          padding: EdgeInsets.only(
            top: (_estimateParagraphFontSize() * 0.34).clamp(2.0, 5.5),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: _isParagraphEmpty()
                  ? 22
                  : (_estimateParagraphFontSize() *
                            EditorConfig.defaultLineHeight)
                        .clamp(0.0, 999),
            ),
            child: Stack(
              key: _paintHostKey,
              children: [
                widget.wrappedContent,
                // 스포일러 마스크
                if (spoilerBoxes.isNotEmpty)
                  Builder(
                    builder: (context) {
                      final theme = Theme.of(context).colorScheme;
                      final brightness = Theme.of(context).brightness;
                      final isLightTheme = brightness == Brightness.light;
                      final bgColor = theme.background;
                      final dotColor = theme.onSurface;
                      return Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            // 🎯 스포일러 탭 시 파티클 해제 (setSpoiler으로 해제 → scatter 트리거)
                            widget.nodeService.setSpoiler(widget.nodeId, false);
                          },
                          child: IgnorePointer(
                            ignoring: true,
                            child: AnimatedBuilder(
                              animation: widget.controller,
                              builder: (context, __) {
                                return RepaintBoundary(
                                  child: CustomPaint(
                                    painter: _ParagraphSpoilerPainter(
                                      boxes: spoilerBoxes,
                                      phase: widget.controller.value,
                                      isEditing: false,
                                      backgroundColor: bgColor,
                                      dotColor: dotColor,
                                      isLightTheme: isLightTheme,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                // 스캐터 이펙트
                if (widget.scatterActive)
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
                            animation: widget.scatterCtrl,
                            builder: (context, __) {
                              return RepaintBoundary(
                                child: CustomPaint(
                                  painter: _ParagraphSpoilerScatterPainter(
                                    boxes: _prevBoxes,
                                    t: widget.scatterCtrl.value,
                                    dotColor: dotColor,
                                    isLightTheme: isLightTheme,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Rect> _collectSpoilerBoxes(BuildContext context) {
    try {
      final node = widget.editorService.editor.document.getNodeById(
        widget.nodeId,
      );
      if (node is! ParagraphNode) return const [];
      final text = node.text;

      // 스포일러가 명시적으로 해제되었는지 확인
      final isDisabled = widget.nodeService.isSpoilerDisabled(widget.nodeId);
      if (isDisabled) {
        return const [];
      }

      // 스포일러 구간 수집
      final calc = <TextRange>[];
      bool inSpoiler = false;
      int start = 0;
      for (int i = 0; i <= text.text.length; i++) {
        final attrs = i < text.text.length
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

      if (calc.isEmpty) {
        return const [];
      }

      // RenderParagraph 찾기
      final ctx = widget.subtreeKey.currentContext;
      if (ctx == null) return const [];
      final RenderObject? ro = ctx.findRenderObject();
      final rp = _findRenderParagraph(ro);
      if (rp == null) return const [];

      final paraBox = rp as RenderBox;
      final hostBox =
          (_paintHostKey.currentContext?.findRenderObject() as RenderBox?) ??
          (this.context.findRenderObject() as RenderBox?);
      if (hostBox == null) return const [];

      final boxes = <Rect>[];
      for (final r in calc) {
        boxes.addAll(
          _measureSelectionRectsForRange(rp, r.start, r.end, paraBox, hostBox),
        );
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

// 같은 줄(top/bottom 유사)에서 인접/겹치는 Rect들을 하나로 합쳐서
// 공백 단위 중복 렌더링(밝아짐)을 제거하고, 선택 영역(Rect)과 일관된 모양을 만든다.
List<Rect> _mergeRectsByLine(
  List<Rect> src, {
  double vTol = 1.0,
  double hJoin = 1.5,
}) {
  if (src.length <= 1) return src;

  // 줄 그룹화: top/bottom 완전 일치 비교는 폰트 크기 변경/스팬 분할 시 깨지기 쉬움.
  // 대신 "수직 겹침" 또는 "centerY 근접"으로 같은 줄을 판별한다.
  final List<_LineGroup> lineGroups = [];
  final sorted = [...src]..sort((a, b) => a.center.dy.compareTo(b.center.dy));

  for (final r in sorted) {
    _LineGroup? best;
    double bestScore = -1;

    for (final g in lineGroups) {
      final overlapTop = max(r.top, g.bounds.top);
      final overlapBottom = min(r.bottom, g.bounds.bottom);
      final double overlapH = (overlapBottom - overlapTop).toDouble();
      final double minH = min(r.height, g.bounds.height).toDouble();
      final double overlapRatio = (minH <= 0) ? 0.0 : (overlapH / minH);

      // 기존 vTol은 보정값으로만 사용하고, 실제 기준은 라인 높이에 비례하게 둔다
      final dynamicTol = max(
        vTol,
        max(2.0, min(r.height, g.bounds.height) * 0.35),
      );
      final centerClose = (r.center.dy - g.centerY).abs() <= dynamicTol;

      if (overlapRatio >= 0.5 || centerClose) {
        final score = overlapRatio;
        if (score > bestScore) {
          bestScore = score;
          best = g;
        }
      }
    }

    if (best == null) {
      lineGroups.add(_LineGroup([r]));
    } else {
      best.add(r);
    }
  }

  // 각 줄에서 좌우로 병합
  final List<Rect> merged = [];
  for (final g in lineGroups) {
    final line = g.rects..sort((a, b) => a.left.compareTo(b.left));
    // 띄어쓰기/스팬 경계로 박스가 끊겨도 자연스럽게 이어지도록 join 폭을 키운다
    final double join = max(
      hJoin,
      max(6.0, (g.bounds.height * 0.25)),
    ).toDouble();
    Rect? cur;
    for (final r in line) {
      if (cur == null) {
        cur = r;
        continue;
      }
      if (r.left <= cur.right + join) {
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

class _LineGroup {
  _LineGroup(this.rects) : bounds = rects.first;

  final List<Rect> rects;
  Rect bounds;

  double get centerY => bounds.center.dy;

  void add(Rect r) {
    rects.add(r);
    bounds = Rect.fromLTRB(
      min(bounds.left, r.left),
      min(bounds.top, r.top),
      max(bounds.right, r.right),
      max(bounds.bottom, r.bottom),
    );
  }
}

// Flutter가 selection(보라색 영역) 계산에 사용하는 RenderParagraph.getBoxesForSelection 결과를 그대로 사용해,
// 스포일러/형광펜 Rect가 선택 영역과 최대한 동일하게 보이도록 만든다.
List<Rect> _measureSelectionRectsForRange(
  RenderParagraph rp,
  int start,
  int end,
  RenderBox paraBox,
  RenderBox hostBox,
) {
  if (start >= end) return const [];

  final selection = TextSelection(baseOffset: start, extentOffset: end);
  final tboxes = rp.getBoxesForSelection(
    selection,
    // 🎯 폰트 크기 변경 시에도 줄 기준으로 높이를 안정화해서 박스가 "띄어쓰기 단위"로 갈라지는 현상을 완화
    boxHeightStyle: BoxHeightStyle.max,
    boxWidthStyle: BoxWidthStyle.tight,
  );
  if (tboxes.isEmpty) return const [];

  final localRects = tboxes
      .map((b) => Rect.fromLTRB(b.left, b.top, b.right, b.bottom))
      .toList();

  // 같은 줄에서 공백 단위로 쪼개진 박스들을 병합 (선택 영역과 동일한 높이 유지)
  final mergedLocal = _mergeRectsByLine(localRects);

  // ✅ 좌표계 변환: 문단 로컬 → 글로벌 → 호스트 로컬
  // offset 차 방식은 Postwrite/Reader 등 트리 구조 차이에 따라 쉽게 오차가 난다.
  return mergedLocal.map((r) {
    final globalTL = paraBox.localToGlobal(r.topLeft);
    final globalBR = paraBox.localToGlobal(r.bottomRight);
    final localTL = hostBox.globalToLocal(globalTL);
    final localBR = hostBox.globalToLocal(globalBR);
    return Rect.fromPoints(localTL, localBR);
  }).toList();
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
      final count = isEditing
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
        final effectiveColor = (!isLightTheme && isEditing)
            ? Colors.white
            : dotColor;
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
    final paint = Paint()
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
