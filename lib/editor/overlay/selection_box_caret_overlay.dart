import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_text_layout/super_text_layout.dart';

/// A [SuperEditorLayerBuilder] that paints a caret whose vertical bounds come
/// from the same selection-box calculation that Flutter uses for selection
/// highlights.
///
/// Why: SuperEditor caret positioning uses `DocumentLayout.getEdgeForPosition`,
/// which can disagree with selection boxes when line metrics change (e.g.,
/// different font sizes, `TextStyle.height`, `leadingDistribution`).
///
/// Standard hook: injected via `SuperEditor.documentOverlayBuilders`.
class SelectionBoxCaretOverlayBuilder implements SuperEditorLayerBuilder {
  const SelectionBoxCaretOverlayBuilder({
    this.caretStyle = const CaretStyle(width: 2),
    this.platformOverride,
    this.displayOnAllPlatforms = true,
    this.displayCaretWithExpandedSelection = true,
    this.blinkTimingMode = BlinkTimingMode.ticker,
  });

  final CaretStyle caretStyle;
  final TargetPlatform? platformOverride;
  final bool displayOnAllPlatforms;
  final bool displayCaretWithExpandedSelection;
  final BlinkTimingMode blinkTimingMode;

  @override
  ContentLayerWidget build(
    BuildContext context,
    SuperEditorContext editContext,
  ) {
    return SelectionBoxCaretDocumentOverlay(
      composer: editContext.composer,
      document: editContext.document,
      documentLayoutResolver: () => editContext.documentLayout,
      caretStyle: caretStyle,
      platformOverride: platformOverride,
      displayOnAllPlatforms: displayOnAllPlatforms,
      displayCaretWithExpandedSelection: displayCaretWithExpandedSelection,
      blinkTimingMode: blinkTimingMode,
    );
  }
}

/// Like SuperEditor's `CaretDocumentOverlay`, but derives caret `top/height`
/// from a 1-character selection box near the caret, keeping caret aligned with
/// selection/highlight boxes.
class SelectionBoxCaretDocumentOverlay
    extends DocumentLayoutLayerStatefulWidget {
  const SelectionBoxCaretDocumentOverlay({
    super.key,
    required this.composer,
    required this.document,
    required this.documentLayoutResolver,
    this.caretStyle = const CaretStyle(width: 2, color: Colors.black),
    this.platformOverride,
    this.displayOnAllPlatforms = true,
    this.displayCaretWithExpandedSelection = true,
    this.blinkTimingMode = BlinkTimingMode.ticker,
  });

  final DocumentComposer composer;
  final Document document;
  final DocumentLayout Function() documentLayoutResolver;
  final CaretStyle caretStyle;
  final TargetPlatform? platformOverride;
  final bool displayOnAllPlatforms;
  final bool displayCaretWithExpandedSelection;
  final BlinkTimingMode blinkTimingMode;

  @override
  DocumentLayoutLayerState<SelectionBoxCaretDocumentOverlay, Rect?>
  createState() => _SelectionBoxCaretDocumentOverlayState();
}

class _SelectionBoxCaretDocumentOverlayState
    extends DocumentLayoutLayerState<SelectionBoxCaretDocumentOverlay, Rect?>
    with SingleTickerProviderStateMixin {
  late final BlinkController _blinkController;

  @override
  void initState() {
    super.initState();

    switch (widget.blinkTimingMode) {
      case BlinkTimingMode.ticker:
        _blinkController = BlinkController(tickerProvider: this);
      case BlinkTimingMode.timer:
        _blinkController = BlinkController.withTimer();
    }

    widget.composer.selectionNotifier.addListener(_onSelectionChange);
    _startOrStopBlinking();
  }

  @override
  void didUpdateWidget(SelectionBoxCaretDocumentOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.composer != oldWidget.composer) {
      oldWidget.composer.selectionNotifier.removeListener(_onSelectionChange);
      widget.composer.selectionNotifier.addListener(_onSelectionChange);
      _startOrStopBlinking();
    }
  }

  @override
  void dispose() {
    widget.composer.selectionNotifier.removeListener(_onSelectionChange);
    _blinkController.dispose();
    super.dispose();
  }

  bool get _shouldHideCaretForExpandedSelection =>
      !widget.displayCaretWithExpandedSelection &&
      widget.composer.selection?.isCollapsed == false;

  void _onSelectionChange() {
    _blinkController.jumpToOpaque();
    _startOrStopBlinking();

    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {
        // caret is positioned during layout computation.
      });
    }
  }

  void _startOrStopBlinking() {
    final wantsToBlink = widget.composer.selection != null;
    if (wantsToBlink && _blinkController.isBlinking) return;
    if (!wantsToBlink && !_blinkController.isBlinking) return;

    wantsToBlink
        ? _blinkController.startBlinking()
        : _blinkController.stopBlinking();
  }

  Rect? _computeSelectionBoxForCaret({
    required DocumentLayout documentLayout,
    required DocumentPosition caretPosition,
  }) {
    final component = documentLayout.getComponentByNodeId(caretPosition.nodeId);
    if (component == null) return null;

    // Prefer a 1-char selection downstream of the caret. If that doesn't exist
    // (e.g., at end of text), fall back to upstream.
    NodePosition? neighbor = component.movePositionRight(
      caretPosition.nodePosition,
    );
    if (neighbor == null) {
      neighbor = component.movePositionLeft(caretPosition.nodePosition);
    }
    if (neighbor == null) return null;

    final base = caretPosition;
    final extent = DocumentPosition(
      nodeId: caretPosition.nodeId,
      nodePosition: neighbor,
    );

    // This rect is derived from the same selection boxes that the platform uses
    // for selection highlight geometry.
    return documentLayout.getRectForSelection(base, extent);
  }

  @override
  Rect? computeLayoutDataWithDocumentLayout(
    BuildContext contentLayersContext,
    BuildContext documentContext,
    DocumentLayout documentLayout,
  ) {
    final selection = widget.composer.selection;
    if (selection == null) return null;

    final selectedComponent = documentLayout.getComponentByNodeId(
      selection.extent.nodeId,
    );
    if (selectedComponent == null) {
      // transient moment where layout doesn't have the component yet
      return null;
    }

    // Keep the caret X from SuperEditor's standard edge computation (affinity-aware),
    // but replace Y/height with the selection box bounds for consistency.
    Rect caretRect = documentLayout
        .getEdgeForPosition(selection.extent)!
        .translate(-widget.caretStyle.width / 2, 0.0);

    final caretPos = selection.extent;
    final selectionBox = _computeSelectionBoxForCaret(
      documentLayout: documentLayout,
      caretPosition: caretPos,
    );
    if (selectionBox != null && selectionBox.height > 0) {
      caretRect = Rect.fromLTWH(
        caretRect.left,
        selectionBox.top,
        caretRect.width,
        selectionBox.height,
      );
    }

    // Keep caret fully visible horizontally (same behavior as upstream overlay).
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox != null &&
        overlayBox.hasSize &&
        caretRect.left + widget.caretStyle.width >= overlayBox.size.width) {
      caretRect = Rect.fromLTWH(
        overlayBox.size.width - widget.caretStyle.width,
        caretRect.top,
        caretRect.width,
        caretRect.height,
      );
    }

    return caretRect;
  }

  @override
  Widget doBuild(BuildContext context, Rect? caret) {
    final platform = widget.platformOverride ?? defaultTargetPlatform;
    if (!widget.displayOnAllPlatforms &&
        (platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS)) {
      return const SizedBox.shrink();
    }

    if (_shouldHideCaretForExpandedSelection) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (caret != null)
              Positioned(
                top: caret.top,
                left: caret.left,
                height: caret.height,
                child: AnimatedBuilder(
                  animation: _blinkController,
                  builder: (context, child) {
                    return Container(
                      key: DocumentKeys.caret,
                      width: widget.caretStyle.width,
                      decoration: BoxDecoration(
                        color: widget.caretStyle.color.withValues(
                          alpha: _blinkController.opacity,
                        ),
                        borderRadius: widget.caretStyle.borderRadius,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
