import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 텍스트 스타일링 관리자
class TextStylingService {
  final Editor editor;
  final MutableDocumentComposer composer;

  TextStylingService({required this.editor, required this.composer});

  /// 굵게 토글
  void toggleBold() {
    final selection = composer.selection;
    if (selection == null) return;

    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: selection,
        attributions: {boldAttribution},
      ),
    ]);
  }

  /// 기울임 토글
  void toggleItalic() {
    final selection = composer.selection;
    if (selection == null) return;

    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: selection,
        attributions: {italicsAttribution},
      ),
    ]);
  }

  /// 밑줄 토글
  void toggleUnderline() {
    final selection = composer.selection;
    if (selection == null) return;

    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: selection,
        attributions: {underlineAttribution},
      ),
    ]);
  }

  /// 취소선 토글
  void toggleStrikethrough() {
    final selection = composer.selection;
    if (selection == null) return;

    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: selection,
        attributions: {strikethroughAttribution},
      ),
    ]);
  }

  /// 텍스트 색상 적용
  void applyTextColor(Color color) {
    final selection = composer.selection;
    if (selection == null) return;

    // 기존 색상 속성 제거
    _removeColorAttributions();

    // 새 색상 적용
    final colorAttribution = ColorAttribution(color);
    editor.execute([
      AddTextAttributionsRequest(
        documentRange: selection,
        attributions: {colorAttribution},
      ),
    ]);
  }

  /// 폰트 크기 변경
  void changeFontSize(double size) {
    final selection = composer.selection;
    if (selection == null) return;

    // 기존 폰트 크기 속성 제거
    _removeFontSizeAttributions();

    // 새 폰트 크기 적용
    final fontSizeAttribution = FontSizeAttribution(size);
    editor.execute([
      AddTextAttributionsRequest(
        documentRange: selection,
        attributions: {fontSizeAttribution},
      ),
    ]);
  }

  /// 기존 색상 속성 제거
  void _removeColorAttributions() {
    final selection = composer.selection;
    if (selection == null) return;

    final existingAttributions = _getAttributionsInSelection();
    final colorAttributions =
        existingAttributions.where((attr) => attr is ColorAttribution).toSet();

    if (colorAttributions.isNotEmpty) {
      editor.execute([
        RemoveTextAttributionsRequest(
          documentRange: selection,
          attributions: colorAttributions,
        ),
      ]);
    }
  }

  /// 기존 폰트 크기 속성 제거
  void _removeFontSizeAttributions() {
    final selection = composer.selection;
    if (selection == null) return;

    final existingAttributions = _getAttributionsInSelection();
    final fontSizeAttributions =
        existingAttributions.whereType<FontSizeAttribution>().toSet();

    if (fontSizeAttributions.isNotEmpty) {
      editor.execute([
        RemoveTextAttributionsRequest(
          documentRange: selection,
          attributions: fontSizeAttributions,
        ),
      ]);
    }
  }

  /// 선택 영역의 모든 속성 가져오기
  Set<Attribution> _getAttributionsInSelection() {
    final selection = composer.selection;
    if (selection == null) return {};

    final startNode = editor.document.getNodeById(selection.base.nodeId);
    if (startNode is! TextNode) return {};

    final startPosition = selection.base.nodePosition as TextNodePosition;
    final endPosition = selection.extent.nodePosition as TextNodePosition;

    final startOffset = startPosition.offset;
    final endOffset = endPosition.offset;

    // 선택 영역의 모든 속성 수집
    final attributions = <Attribution>{};
    for (int i = startOffset; i < endOffset; i++) {
      final charAttributions = startNode.text.getAllAttributionsAt(i);
      attributions.addAll(charAttributions);
    }

    return attributions;
  }

  /// 현재 선택된 텍스트의 스타일 상태 확인
  Map<String, bool> getCurrentStyles() {
    final selection = composer.selection;
    if (selection == null) {
      return {
        'bold': false,
        'italic': false,
        'underline': false,
        'strikethrough': false,
      };
    }

    // 선택된 텍스트의 속성 확인
    final node = editor.document.getNodeById(selection.base.nodeId);
    if (node is! TextNode) {
      return {
        'bold': false,
        'italic': false,
        'underline': false,
        'strikethrough': false,
      };
    }

    final position = selection.base.nodePosition as TextNodePosition;
    final attributions = node.text.getAllAttributionsAt(position.offset);

    return {
      'bold': attributions.contains(boldAttribution),
      'italic': attributions.contains(italicsAttribution),
      'underline': attributions.contains(underlineAttribution),
      'strikethrough': attributions.contains(strikethroughAttribution),
    };
  }

  /// 텍스트 정렬 적용 (문서 전체 일괄 적용)
  void applyTextAlignment(TextAlign alignment) {
    _applyAlignmentToAllTextNodes(alignment);
  }

  /// 모든 텍스트 노드에 정렬 적용 (이미지 제외)
  void _applyAlignmentToAllTextNodes(TextAlign alignment) {
    final requests = <EditRequest>[];

    for (int i = 0; i < editor.document.nodeCount; i++) {
      final node = editor.document.getNodeAt(i);
      if (node is ParagraphNode) {
        final updatedMetadata = Map<String, dynamic>.from(node.metadata);
        updatedMetadata['textAlign'] = alignment.name;

        requests.add(
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: ParagraphNode(
              id: node.id,
              text: node.text,
              metadata: updatedMetadata,
            ),
          ),
        );
      }
      // 🎯 ImageNode는 제외 (이미지는 정렬하지 않음)
    }

    if (requests.isNotEmpty) {
      editor.execute(requests);
    }
  }

  /// 현재 정렬 상태 가져오기 (문서 첫 번째 문단 기준)
  TextAlign getCurrentAlignment() {
    for (int i = 0; i < editor.document.nodeCount; i++) {
      final node = editor.document.getNodeAt(i);
      if (node is ParagraphNode) {
        final textAlignName = node.metadata['textAlign'] as String?;
        switch (textAlignName) {
          case 'left':
            return TextAlign.left;
          case 'center':
            return TextAlign.center;
          case 'right':
            return TextAlign.right;
        }
        break;
      }
    }
    return TextAlign.center; // 기본값
  }

  /// 모든 스타일 제거
  void clearAllStyles() {
    final selection = composer.selection;
    if (selection == null) return;

    editor.execute([
      RemoveTextAttributionsRequest(
        documentRange: selection,
        attributions: {
          boldAttribution,
          italicsAttribution,
          underlineAttribution,
          strikethroughAttribution,
        },
      ),
    ]);
  }

  /// 인용 블록 삽입: 현재 커서 아래에 인용 스타일 문단을 추가
  void insertQuoteBlock() {
    final position = composer.selection?.extent;
    final insertIndex = _indexAfter(position);
    final node = ParagraphNode(
      id: 'quote_${DateTime.now().millisecondsSinceEpoch}',
      text: AttributedText(''),
      metadata: {'textAlign': getCurrentAlignment().name, 'blockquote': true},
    );
    editor.execute([
      // 캐럿 기준 삽입 + 선택 이동 처리까지 내장됨
      InsertNodeAtCaretRequest(node: node),
    ]);
    print('인용 블록 삽입: $insertIndex');
  }

  /// 구분선 삽입: 비어있는 문단으로 표현(스타일시트에서 선으로 렌더)
  void insertDivider() {
    final position = composer.selection?.extent;
    final insertIndex = _indexAfter(position);
    final node = ParagraphNode(
      id: 'divider_${DateTime.now().millisecondsSinceEpoch}',
      text: AttributedText(''),
      metadata: {'isDivider': true},
    );
    editor.execute([
      // 캐럿 기준 삽입 + 선택 이동 처리까지 내장됨
      InsertNodeAtCaretRequest(node: node),
    ]);
    print('구분선 삽입: $insertIndex');
  }

  int _indexAfter(DocumentPosition? pos) {
    if (pos == null) return editor.document.nodeCount;
    final idx = editor.document.getNodeIndexById(pos.nodeId);
    return idx == -1 ? editor.document.nodeCount : idx + 1;
  }
}

/// 4개의 기본 아이콘만 보이고, 탭 시 옆으로 세부 기능이 펼쳐지는 툴바
class DefaultToolbar extends StatefulWidget {
  final TextStylingService stylingService;
  final VoidCallback? onInsertImage;
  final ScrollController? scrollController;

  const DefaultToolbar({
    super.key,
    required this.stylingService,
    this.onInsertImage,
    this.scrollController,
  });

  @override
  State<DefaultToolbar> createState() => _DefaultToolbarState();
}

enum ToolbarSection { none, image, insert, text, align }

class _DefaultToolbarState extends State<DefaultToolbar> {
  Map<String, bool> _currentStyles = {
    'bold': false,
    'italic': false,
    'underline': false,
    'strikethrough': false,
  };

  TextAlign _currentAlignment = TextAlign.center;
  ToolbarSection _expanded = ToolbarSection.none;

  @override
  void initState() {
    super.initState();
    _updateStyles();
  }

  void _updateStyles() {
    setState(() {
      _currentStyles = widget.stylingService.getCurrentStyles();
      _currentAlignment = widget.stylingService.getCurrentAlignment();
    });
  }

  void _toggle(ToolbarSection section) {
    setState(() {
      _expanded = _expanded == section ? ToolbarSection.none : section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return SizedBox(
      height: 38,
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: Colors.white),
        child: ListView(
          scrollDirection: Axis.horizontal,

          children: [
            // 이미지 섹션
            _buildMainIcon(
              icon: Icons.image_outlined,
              isActive: _expanded == ToolbarSection.image,
              onTap: () => _toggle(ToolbarSection.image),
            ),
            if (_expanded == ToolbarSection.image) ...[
              const SizedBox(width: 8),
              _buildChip(
                icon: Icons.add_photo_alternate_outlined,
                label: '이미지 삽입',
                onTap: widget.onInsertImage,
              ),
            ],

            const SizedBox(width: 10),
            _buildDivider(),
            const SizedBox(width: 10),

            // 추가(플러스) 섹션
            _buildMainIcon(
              icon: Icons.add_box_outlined,
              isActive: _expanded == ToolbarSection.insert,
              onTap: () => _toggle(ToolbarSection.insert),
              activeColor: Colors.teal,
            ),
            if (_expanded == ToolbarSection.insert) ...[
              const SizedBox(width: 8),
              _buildColorDot(Colors.red, () {
                widget.stylingService.applyTextColor(Colors.red);
                _updateStyles();
              }),
              const SizedBox(width: 6),
              _buildColorDot(Colors.blue, () {
                widget.stylingService.applyTextColor(Colors.blue);
                _updateStyles();
              }),
              const SizedBox(width: 6),
              _buildColorDot(Colors.green, () {
                widget.stylingService.applyTextColor(Colors.green);
                _updateStyles();
              }),
              const SizedBox(width: 10),
              _buildMiniButton('12', () {
                widget.stylingService.changeFontSize(12);
                _updateStyles();
              }),
              const SizedBox(width: 6),
              _buildMiniButton('16', () {
                widget.stylingService.changeFontSize(16);
                _updateStyles();
              }),
              const SizedBox(width: 6),
              _buildMiniButton('20', () {
                widget.stylingService.changeFontSize(20);
                _updateStyles();
              }),
              const SizedBox(width: 6),
              _buildMiniButton('24', () {
                widget.stylingService.changeFontSize(24);
                _updateStyles();
              }),
              const SizedBox(width: 10),
              _buildChip(
                icon: Icons.format_quote,
                label: '인용',
                onTap: () {
                  widget.stylingService.insertQuoteBlock();
                },
              ),
              const SizedBox(width: 6),
              _buildChip(
                icon: Icons.horizontal_rule,
                label: '구분선',
                onTap: () {
                  widget.stylingService.insertDivider();
                },
              ),
            ],

            const SizedBox(width: 10),
            _buildDivider(),
            const SizedBox(width: 10),

            // 텍스트 스타일 섹션 (A)
            _buildMainIcon(
              icon: Icons.text_fields,
              isActive: _expanded == ToolbarSection.text,
              onTap: () => _toggle(ToolbarSection.text),
            ),
            if (_expanded == ToolbarSection.text) ...[
              const SizedBox(width: 8),
              _buildToggleIcon(
                icon: Icons.format_bold,
                isActive: _currentStyles['bold'] ?? false,
                onTap: () {
                  widget.stylingService.toggleBold();
                  _updateStyles();
                },
              ),
              const SizedBox(width: 6),
              _buildToggleIcon(
                icon: Icons.format_italic,
                isActive: _currentStyles['italic'] ?? false,
                onTap: () {
                  widget.stylingService.toggleItalic();
                  _updateStyles();
                },
              ),
              const SizedBox(width: 6),
              _buildToggleIcon(
                icon: Icons.format_underlined,
                isActive: _currentStyles['underline'] ?? false,
                onTap: () {
                  widget.stylingService.toggleUnderline();
                  _updateStyles();
                },
              ),
              const SizedBox(width: 6),
              _buildToggleIcon(
                icon: Icons.format_strikethrough,
                isActive: _currentStyles['strikethrough'] ?? false,
                onTap: () {
                  widget.stylingService.toggleStrikethrough();
                  _updateStyles();
                },
              ),
            ],

            const SizedBox(width: 10),
            _buildDivider(),
            const SizedBox(width: 10),

            // 정렬 섹션
            _buildMainIcon(
              icon: Icons.format_align_left,
              isActive: _expanded == ToolbarSection.align,
              onTap: () => _toggle(ToolbarSection.align),
            ),
            if (_expanded == ToolbarSection.align) ...[
              const SizedBox(width: 8),
              _buildToggleIcon(
                icon: Icons.format_align_left,
                isActive: _currentAlignment == TextAlign.left,
                onTap: () {
                  final offset = widget.scrollController?.offset;
                  widget.stylingService.applyTextAlignment(TextAlign.left);
                  _updateStyles();
                  if (offset != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.scrollController?.jumpTo(offset);
                    });
                  }
                },
              ),
              const SizedBox(width: 6),
              _buildToggleIcon(
                icon: Icons.format_align_center,
                isActive: _currentAlignment == TextAlign.center,
                onTap: () {
                  final offset = widget.scrollController?.offset;
                  widget.stylingService.applyTextAlignment(TextAlign.center);
                  _updateStyles();
                  if (offset != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.scrollController?.jumpTo(offset);
                    });
                  }
                },
              ),
              const SizedBox(width: 6),
              _buildToggleIcon(
                icon: Icons.format_align_right,
                isActive: _currentAlignment == TextAlign.right,
                onTap: () {
                  final offset = widget.scrollController?.offset;
                  widget.stylingService.applyTextAlignment(TextAlign.right);
                  _updateStyles();
                  if (offset != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.scrollController?.jumpTo(offset);
                    });
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMainIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final color =
        isActive ? (activeColor ?? Colors.black) : Colors.grey.shade700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }

  Widget _buildToggleIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isActive ? Colors.blue.shade100 : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 20,
            color: isActive ? Colors.blue.shade700 : Colors.grey.shade800,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: 1,
      height: 28,
      color: Colors.grey.shade300,
    );
  }

  Widget _buildColorDot(Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniButton(String label, VoidCallback onTap) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.grey.shade900),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // legacy helpers (not used in the new expandable UI)
  // kept here intentionally commented out for reference
  // Widget _buildColorButton(...) {}

  // Widget _buildAlignmentButton(...) {}

  // Widget _buildFontSizeButton(...) {}
}
