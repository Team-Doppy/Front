import 'dart:io';
import 'dart:typed_data';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/overlay/sticker_overlay.dart';
import 'package:doppy/editor/overlay/font_overlay.dart';
import 'package:doppy/editor/style/font_catalog.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/image/native_image_picker.dart';
import 'package:doppy/editor/overlay/link_overlay.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/overlay/mention_overlay.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:video_compress/video_compress.dart';
import 'dart:ui';

/// 형광펜 효과 Attribution 정의
class HighlightAttribution extends ColorAttribution {
  const HighlightAttribution(Color color) : super(color);

  @override
  String get id => 'highlight';
}

/// 스포일러(가림) 텍스트 Attribution (JSON 직렬화용 id만 사용)
/// NamedAttribution을 사용하면 export/import 시 그대로 보존된다.
const NamedAttribution spoilerAttribution = NamedAttribution('spoiler');

/// 기본 형광펜 색상들 (연한 톤으로 수정)
const Color highlightYellow = Color(0xFFFFF59D); // 더 연한 노란색
const Color highlightGreen = Color(0xFFA5D6A7); // 더 연한 초록색
const Color highlightBlue = Color(0xFF90CAF9); // 더 연한 파란색
const Color highlightPink = Color(0xFFF8BBD9); // 더 연한 분홍색
const Color highlightOrange = Color(0xFFFFCC80); // 더 연한 주황색
const Color highlightPurple = Color(0xFFCE93D8); // 더 연한 보라색

/// 텍스트 스타일링 관리자
class TextStylingService extends ChangeNotifier {
  final Editor editor;
  final MutableDocumentComposer composer;

  // 전역 폰트 (새로 입력되는 모든 텍스트에 적용)
  String? _globalFontFamily;

  String? get globalFontFamily => _globalFontFamily;

  TextStylingService({required this.editor, required this.composer});

  /// 메타데이터에 폰트 적용
  void applyFontToMetadata(String fontFamily) {
    final selection = composer.selection;
    if (selection == null) return;

    // 선택된 모든 노드에 폰트 메타데이터 적용
    final selectedNodes = editor.document.getNodesInside(
      selection.extent,
      selection.base,
    );

    for (final node in selectedNodes) {
      if (node is ParagraphNode) {
        final updatedMetadata = Map<String, dynamic>.from(node.metadata);
        if (fontFamily.isNotEmpty) {
          updatedMetadata['fontFamily'] = fontFamily;
        } else {
          updatedMetadata.remove('fontFamily');
        }

        // 노드 교체로 메타데이터 업데이트
        final newNode = ParagraphNode(
          id: node.id,
          text: node.text,
          metadata: updatedMetadata,
        );

        editor.execute([
          ReplaceNodeRequest(existingNodeId: node.id, newNode: newNode),
        ]);
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

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

  /// 스포일러 토글 (선택 영역 가리기)
  void toggleSpoiler() {
    final selection = composer.selection;
    if (selection == null) return;

    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: selection,
        attributions: {spoilerAttribution},
      ),
    ]);
  }

  /// 형광펜 토글 (기본 노란색)
  void toggleHighlight() {
    final selection = composer.selection;
    if (selection == null) return;

    // 현재 형광펜 상태 확인
    final hasHighlight = _hasHighlightInSelection();

    if (hasHighlight) {
      // 형광펜 제거
      _removeHighlightAttributions();
    } else {
      // 형광펜 적용 (기본 노란색)
      applyHighlight(highlightYellow);
    }
  }

  /// 특정 색상으로 형광펜 적용
  void applyHighlight(Color color, {DocumentSelection? selectionOverride}) {
    final selection = selectionOverride ?? composer.selection;
    if (selection == null) return;

    // 🔧 선택 영역의 모든 노드에 대해 형광펜 적용
    final requests = <EditRequest>[];

    // 선택 영역이 여러 노드에 걸쳐 있는 경우 처리
    final startNode = editor.document.getNodeById(selection.base.nodeId);
    final endNode = editor.document.getNodeById(selection.extent.nodeId);

    if (startNode is TextNode && endNode is TextNode) {
      // 단일 노드 내에서 선택된 경우
      if (startNode.id == endNode.id) {
        final highlightAttribution = HighlightAttribution(color);
        requests.add(
          AddTextAttributionsRequest(
            documentRange: selection,
            attributions: {highlightAttribution},
          ),
        );
      } else {
        // 여러 노드에 걸친 선택의 경우 - 각 노드별로 처리

        // 첫 번째 노드 (시작부터 끝까지)
        requests.add(
          AddTextAttributionsRequest(
            documentRange: DocumentSelection(
              base: selection.base,
              extent: DocumentPosition(
                nodeId: startNode.id,
                nodePosition: TextNodePosition(
                  offset: startNode.text.text.length,
                ),
              ),
            ),
            attributions: {HighlightAttribution(color)},
          ),
        );

        // 중간 노드들 (전체)
        final startIndex = editor.document.getNodeIndexById(startNode.id);
        final endIndex = editor.document.getNodeIndexById(endNode.id);

        for (int i = startIndex + 1; i < endIndex; i++) {
          final node = editor.document.getNodeAt(i);
          if (node is TextNode) {
            requests.add(
              AddTextAttributionsRequest(
                documentRange: DocumentSelection(
                  base: DocumentPosition(
                    nodeId: node.id,
                    nodePosition: TextNodePosition(offset: 0),
                  ),
                  extent: DocumentPosition(
                    nodeId: node.id,
                    nodePosition: TextNodePosition(
                      offset: node.text.text.length,
                    ),
                  ),
                ),
                attributions: {HighlightAttribution(color)},
              ),
            );
          }
        }

        // 마지막 노드 (시작부터 끝까지)
        requests.add(
          AddTextAttributionsRequest(
            documentRange: DocumentSelection(
              base: DocumentPosition(
                nodeId: endNode.id,
                nodePosition: TextNodePosition(offset: 0),
              ),
              extent: selection.extent,
            ),
            attributions: {HighlightAttribution(color)},
          ),
        );
      }
    }

    // 기존 형광펜 제거 후 새 형광펜 적용
    if (requests.isNotEmpty) {
      // 먼저 기존 형광펜 제거
      _removeHighlightAttributions();

      // 새 형광펜 적용
      editor.execute(requests);
    }
  }

  /// 선택 영역에 형광펜이 있는지 확인
  bool _hasHighlightInSelection({DocumentSelection? selectionOverride}) {
    final selection = selectionOverride ?? composer.selection;
    if (selection == null) return false;

    final existingAttributions = _getAttributionsInSelection(
      selectionOverride: selection,
    );
    return existingAttributions.any((attr) => attr is HighlightAttribution);
  }

  /// 기존 형광펜 속성 제거
  void _removeHighlightAttributions({DocumentSelection? selectionOverride}) {
    final selection = selectionOverride ?? composer.selection;
    if (selection == null) return;

    // 🔧 선택 영역의 모든 노드에 대해 형광펜 제거
    final requests = <EditRequest>[];

    // 선택 영역이 여러 노드에 걸쳐 있는 경우 처리
    final startNode = editor.document.getNodeById(selection.base.nodeId);
    final endNode = editor.document.getNodeById(selection.extent.nodeId);

    if (startNode is TextNode && endNode is TextNode) {
      // 단일 노드 내에서 선택된 경우
      if (startNode.id == endNode.id) {
        final existingAttributions = _getAttributionsInSelection(
          selectionOverride: selection,
        );
        final highlightAttributions =
            existingAttributions
                .where((attr) => attr is HighlightAttribution)
                .toSet();

        if (highlightAttributions.isNotEmpty) {
          requests.add(
            RemoveTextAttributionsRequest(
              documentRange: selection,
              attributions: highlightAttributions,
            ),
          );
        }
      } else {
        // 여러 노드에 걸친 선택의 경우 - 각 노드별로 처리
        final startIndex = editor.document.getNodeIndexById(startNode.id);
        final endIndex = editor.document.getNodeIndexById(endNode.id);

        // 모든 관련 노드에서 형광펜 제거
        for (int i = startIndex; i <= endIndex; i++) {
          final node = editor.document.getNodeAt(i);
          if (node is TextNode) {
            final nodeRange = DocumentSelection(
              base: DocumentPosition(
                nodeId: node.id,
                nodePosition: TextNodePosition(offset: 0),
              ),
              extent: DocumentPosition(
                nodeId: node.id,
                nodePosition: TextNodePosition(offset: node.text.text.length),
              ),
            );

            // 해당 노드의 모든 형광펜 속성 찾기
            final nodeAttributions = <Attribution>{};

            // 노드 전체를 순회하며 형광펜 속성 찾기
            for (int i = 0; i < node.text.text.length; i++) {
              final attributions = node.text.getAllAttributionsAt(i);
              for (final attr in attributions) {
                if (attr is HighlightAttribution) {
                  nodeAttributions.add(attr);
                }
              }
            }

            final highlightAttributions = nodeAttributions.toSet();

            if (highlightAttributions.isNotEmpty) {
              requests.add(
                RemoveTextAttributionsRequest(
                  documentRange: nodeRange,
                  attributions: highlightAttributions,
                ),
              );
            }
          }
        }
      }
    }

    if (requests.isNotEmpty) {
      editor.execute(requests);
    }
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
  Set<Attribution> _getAttributionsInSelection({
    DocumentSelection? selectionOverride,
  }) {
    final selection = selectionOverride ?? composer.selection;
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
        'highlight': false,
        'spoiler': false,
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
        'highlight': false,
        'spoiler': false,
      };
    }

    final position = selection.base.nodePosition as TextNodePosition;
    final attributions = node.text.getAllAttributionsAt(position.offset);

    return {
      'bold': attributions.contains(boldAttribution),
      'italic': attributions.contains(italicsAttribution),
      'underline': attributions.contains(underlineAttribution),
      'strikethrough': attributions.contains(strikethroughAttribution),
      'highlight': attributions.any((attr) => attr is HighlightAttribution),
      'spoiler': attributions.contains(spoilerAttribution),
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

    // 기존 속성들을 모두 수집하여 제거
    final existingAttributions = _getAttributionsInSelection();
    final allAttributions =
        existingAttributions
            .where(
              (attr) =>
                  attr == boldAttribution ||
                  attr == italicsAttribution ||
                  attr == underlineAttribution ||
                  attr == strikethroughAttribution ||
                  attr is HighlightAttribution ||
                  attr is ColorAttribution ||
                  attr is FontSizeAttribution ||
                  attr is FontFamilyAttribution,
            )
            .toSet();

    if (allAttributions.isNotEmpty) {
      editor.execute([
        RemoveTextAttributionsRequest(
          documentRange: selection,
          attributions: allAttributions,
        ),
      ]);
    }
  }

  /// 폰트 적용: 선택 영역이 있으면 그 범위에만, 없으면 현재 커서 위치에 zero-width 삽입+삭제로 활성화
  void applyFont(FontItem fontItem) {
    final selection = composer.selection;

    // 🔧 폰트 패밀리명 결정: Google Fonts는 displayName을 그대로 사용 (GoogleFonts.getFont()용)
    String targetFamily;
    if (fontItem.googleFont != null) {
      // Google Fonts: displayName을 사용 (예: "Yeon Sung", "Cute Font")
      targetFamily = fontItem.displayName;
      print('[FontDebug] Google Font 감지: $targetFamily');
    } else if (fontItem.localFontFamily != null) {
      // 로컬 폰트
      targetFamily = fontItem.localFontFamily!;
      print('[FontDebug] 로컬 폰트 감지: $targetFamily');
    } else {
      // 기본 폰트 (null)
      targetFamily = '';
      print('[FontDebug] 기본 폰트 사용');
    }

    if (selection != null && !selection.isCollapsed) {
      // ✅ 선택 영역이 있으면: 메타데이터에 폰트 적용
      print('[FontDebug] 선택 영역에 폰트 적용: $targetFamily');
      applyFontToMetadata(targetFamily);
    } else {
      // ✅ 선택 영역이 없으면: 모든 ParagraphNode에 전역 폰트 적용
      print('[FontDebug] 전역 폰트 적용: $targetFamily');

      // 전역 폰트 설정
      if (_globalFontFamily != targetFamily) {
        _globalFontFamily = targetFamily.isNotEmpty ? targetFamily : null;
        notifyListeners();
      }

      // 모든 ParagraphNode에 폰트 적용
      for (int i = 0; i < editor.document.length; i++) {
        final node = editor.document.getNodeAt(i);
        if (node is ParagraphNode) {
          final updatedMetadata = Map<String, dynamic>.from(node.metadata);
          if (targetFamily.isNotEmpty) {
            updatedMetadata['fontFamily'] = targetFamily;
          } else {
            updatedMetadata.remove('fontFamily');
          }

          // 노드 교체로 메타데이터 업데이트
          final newNode = ParagraphNode(
            id: node.id,
            text: node.text,
            metadata: updatedMetadata,
          );

          editor.execute([
            ReplaceNodeRequest(existingNodeId: node.id, newNode: newNode),
          ]);
        }
      }
    }
  }

  /// 현재 커서 위치에 있는 폰트 정보 가져오기
  FontFamilyAttribution? getCurrentFont() {
    final selection = composer.selection;
    if (selection == null) return null;

    final attributions = _getAttributionsInSelection();
    return attributions.whereType<FontFamilyAttribution>().firstOrNull;
  }

  /// 구분선 삽입: 전용 DividerNode를 커서 위치에 삽입
  void insertDivider() {
    // 현재 커서 기준 삽입 인덱스 계산
    final selection = composer.selection;
    final int insertIndex;
    if (selection == null) {
      insertIndex = editor.document.nodeCount;
    } else {
      final nodeId = selection.extent.nodeId;
      final idx = editor.document.getNodeIndexById(nodeId);
      insertIndex = idx == -1 ? editor.document.nodeCount : idx + 1;
    }

    // 1) DividerNode 삽입
    final divider = DividerNode(
      id: 'divider_${DateTime.now().microsecondsSinceEpoch}',
    );

    // 2) Divider 뒤에 빈 문단 삽입 (정렬 승계)
    final TextAlign align = getCurrentAlignment();
    final paragraphId = 'p_${DateTime.now().microsecondsSinceEpoch}';
    final paragraph = ParagraphNode(
      id: paragraphId,
      text: AttributedText(''),
      metadata: {'textAlign': align.name},
    );

    editor.execute([
      InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: divider),
      InsertNodeAtIndexRequest(nodeIndex: insertIndex + 1, newNode: paragraph),
      // 커서를 새 문단 시작으로 이동
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: paragraphId,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
  }
}
// (font overlay moved to editor/overlay/font_overlay.dart)

// 상단 확장 행 콘텐츠 (DefaultToolbar 내부 전용)
extension _TopExpandedRow on _DefaultToolbarState {
  Widget _buildTopExpandedRowContent() {
    switch (_expanded) {
      case ToolbarSection.camera:
        return const SizedBox.shrink();

      case ToolbarSection.text:
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            // 축약 아이콘: 사이즈 / 색상
            if (_textPanel == TextPanel.none) ...[_buildSizeCollapsedButton()],
            if (_textPanel == TextPanel.size) ...[_buildFontSizeRow()],
            if (_textPanel == TextPanel.none) ...[_buildColorCollapsedButton()],
            if (_textPanel == TextPanel.color) ...[_buildColorPaletteRow()],

            // 폰트 선택 버튼 (오버레이)
            _buildToggleIcon(
              icon: Icons.font_download_outlined,
              isActive: false,
              onTap: _openFontPickerOverlay,
            ),
            const SizedBox(width: 6),

            // 간단 토글들
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
            const SizedBox(width: 6),
            // 🎨 형광펜 버튼 추가
            _buildHighlightToggleIcon(),

            const SizedBox(width: 6),
            // 🙈 스포일러(가림) 토글 버튼
            _buildToggleIcon(
              icon: Icons.visibility_off,
              isActive: _currentStyles['spoiler'] ?? false,
              onTap: () {
                widget.stylingService.toggleSpoiler();
                _updateStyles();
              },
            ),

            // 오른쪽 끝으로 밀기
          ],
        );

      case ToolbarSection.insert:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildSvgChip(
                svgPath: 'assets/icons/editor_pen.svg',
                label: '그리기',
                onTap: () => _selectStickerType(StickerKind.draw),
              ),

              _buildSvgChip(
                svgPath: 'assets/icons/link.svg',
                label: '링크',
                onTap: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      barrierDismissible: true,
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder:
                          (_, __, ___) => LinkOverlay(
                            onSubmit: ({
                              required String url,
                              String? title,
                              String? description,
                              String? thumbnailUrl,
                            }) {
                              widget.editorService.addLinkNode(
                                url: url,
                                title: title,
                                description: description,
                                thumbnailUrl: thumbnailUrl,
                              );
                              // 링크 추가 후 상단 두번째 툴바 자동 닫기
                              _toggle(ToolbarSection.none);
                              Navigator.of(context).maybePop();
                            },
                          ),
                    ),
                  );
                },
              ),

              _buildChip(
                icon: Icons.alternate_email,
                label: '언급',
                onTap: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      barrierDismissible: true,
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder:
                          (_, __, ___) => MentionOverlay(
                            onClose: () {},
                            onSelect: (username) {},
                            onSubmit: (usernames) {
                              widget.editorService.addMentionNode(usernames);
                              // 언급 추가 후 상단 두번째 툴바 자동 닫기
                              _toggle(ToolbarSection.none);
                              Navigator.of(context).maybePop();
                            },
                          ),
                    ),
                  );
                },
              ),
              _buildChip(
                icon: Icons.horizontal_rule,
                label: '구분선',
                onTap: () {
                  widget.stylingService.insertDivider();
                  // 추가 후 상단 두번째 툴바 닫기
                  _toggle(ToolbarSection.none);
                },
              ),
            ],
          ),
        );

      case ToolbarSection.align:
        return Row(
          children: [
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
        );
      case ToolbarSection.mention:
        return Row(
          children: [
            _buildChip(
              icon: Icons.alternate_email,
              label: '언급',
              onTap: () {
                print('언급 삽입');
              },
            ),
            const SizedBox(width: 6),
            _buildChip(
              icon: Icons.tag,
              label: '태그',
              onTap: () {
                print('태그 삽입');
              },
            ),
          ],
        );
      case ToolbarSection.none:
        return const SizedBox.shrink();
    }
  }
}

/// 4개의 기본 아이콘만 보이고, 탭 시 옆으로 세부 기능이 펼쳐지는 툴바
class DefaultToolbar extends StatefulWidget {
  final TextStylingService stylingService;
  final EditorService editorService;
  final ScrollController? scrollController;
  final bool isKeyboardVisible;
  final VoidCallback? onDismissKeyboard;
  final VoidCallback? onRequestFocus;
  final VoidCallback? onShowDraftList;
  final bool isEditMode;

  const DefaultToolbar({
    super.key,
    required this.stylingService,
    required this.editorService,

    this.scrollController,
    this.isKeyboardVisible = false,
    this.onDismissKeyboard,
    this.onRequestFocus,
    this.onShowDraftList,
    this.isEditMode = false,
  });

  @override
  State<DefaultToolbar> createState() => _DefaultToolbarState();
}

enum ToolbarSection { none, camera, insert, text, align, mention }

enum TextPanel { none, size, color }

enum StickerPanel { none, sticker }

class _DefaultToolbarState extends State<DefaultToolbar> {
  Map<String, bool> _currentStyles = {
    'bold': false,
    'italic': false,
    'underline': false,
    'strikethrough': false,
  };

  TextAlign _currentAlignment = TextAlign.left;
  ToolbarSection _expanded = ToolbarSection.none;
  TextPanel _textPanel = TextPanel.none;
  // (reserved) 대표 아이콘 기준 정렬이 필요할 때 사용할 수 있는 앵커 키
  final GlobalKey _textIconKey = GlobalKey();

  // 선택 상태 추적
  bool _hasTextSelection = false;

  @override
  void initState() {
    super.initState();
    _updateStyles();

    // 선택 상태 변화 감지
    widget.stylingService.composer.selectionNotifier.addListener(
      _onSelectionChanged,
    );
  }

  @override
  void dispose() {
    widget.stylingService.composer.selectionNotifier.removeListener(
      _onSelectionChanged,
    );
    super.dispose();
  }

  void _onSelectionChanged() {
    final selection = widget.stylingService.composer.selection;
    final hasSelection = selection != null && !selection.isCollapsed;

    if (_hasTextSelection != hasSelection) {
      setState(() {
        _hasTextSelection = hasSelection;
        if (hasSelection) {
          // 텍스트가 선택되면 자동으로 텍스트 툴바 열기
          _expanded = ToolbarSection.text;
        } else {
          // 선택이 해제되면 툴바 닫기
          _expanded = ToolbarSection.none;
        }
      });
    }

    _updateStyles();
  }

  void _updateStyles() {
    final newStyles = widget.stylingService.getCurrentStyles();
    final newAlignment = widget.stylingService.getCurrentAlignment();

    // 스타일이나 정렬이 실제로 변경된 경우에만 setState 호출
    bool needsUpdate = false;

    if (_currentAlignment != newAlignment) {
      needsUpdate = true;
    }

    if (_currentStyles.length != newStyles.length) {
      needsUpdate = true;
    } else {
      for (var key in _currentStyles.keys) {
        if (_currentStyles[key] != newStyles[key]) {
          needsUpdate = true;
          break;
        }
      }
    }

    if (needsUpdate) {
      setState(() {
        _currentStyles = newStyles;
        _currentAlignment = newAlignment;
      });
    }
  }

  void _toggle(ToolbarSection section) {
    setState(() {
      _expanded = _expanded == section ? ToolbarSection.none : section;
    });

    if (_expanded == ToolbarSection.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateTopAnchor());
    }
  }

  // 수동으로 툴바 닫기 (텍스트 선택이 있을 때도 강제로 닫을 수 있도록)
  void _forceCloseToolbar() {
    setState(() {
      _expanded = ToolbarSection.none;
    });
  }

  void _updateTopAnchor() {
    try {
      final context = _textIconKey.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && mounted) {
          // anchor reserved (no-op for now)
        }
      }
    } catch (_) {}
  }

  // 폰트 선택 오버레이 열기 (블러 배경)
  void _openFontPickerOverlay() {
    // 🔧 선택 영역을 저장 (포커스 해제 전에)
    final savedSelection = widget.stylingService.composer.selection;
    print('[FontDebug] 저장된 selection: $savedSelection');
    FocusManager.instance.primaryFocus?.unfocus();

    Navigator.of(context)
        .push(
          PageRouteBuilder(
            opaque: false,
            barrierDismissible: true,
            pageBuilder:
                (ctx, __, ___) => FontOverlay(
                  onSelect: (fontItem) {
                    // 🔧 저장된 selection 복원
                    if (savedSelection != null) {
                      widget.stylingService.editor.execute([
                        ChangeSelectionRequest(
                          savedSelection,
                          SelectionChangeType.placeCaret,
                          SelectionReason.userInteraction,
                        ),
                      ]);
                      print('[FontDebug] selection 복원됨: $savedSelection');
                    }

                    // 폰트 적용
                    widget.stylingService.applyFont(fontItem);
                    print(
                      '[FontOverlay] 폰트 적용됨: ${fontItem.displayName} (${fontItem.identifier})',
                    );
                  },
                  onClose: () => Navigator.of(ctx).maybePop(),
                ),
          ),
        )
        .then((_) {
          if (context.mounted) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    print(
      'DEBUG: DefaultToolbar build - isKeyboardVisible: ${widget.isKeyboardVisible}',
    );
    final Color background = Theme.of(context).colorScheme.background;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child:
          _expanded != ToolbarSection.none
              ? _buildExpandedToolbar()
              : _buildMainToolbar(),
    );
  }

  Widget _buildMainToolbar() {
    // 키보드 상태에 따라 변하는 부분만 별도 위젯으로 분리
    return Row(
      children: [
        SizedBox(width: 10),
        // 카메라 섹션 (아이콘만, 옵션은 상단 행)
        _buildMainSvgIcon(
          svgPath: 'assets/icons/editor_gallery.svg',
          size: 27,
          isActive: true,
          onTap: () async {
            // 키보드 내리기 (한 번만, 충분한 시간 대기)
            FocusManager.instance.primaryFocus?.unfocus();
            String mode = 'none';
            await showModalBottomSheet(
              backgroundColor: Colors.transparent,
              context: context,
              builder:
                  (context) => ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        height: 180,
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,

                          children: [
                            const SizedBox(height: 8),
                            Container(
                              width: 50,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(height: 8),

                            ListTile(
                              onTap: () async {
                                mode = 'image';
                                return Navigator.of(context).pop(mode);
                              },

                              title: Text('이미지 업로드'),
                            ),
                            ListTile(
                              onTap: () async {
                                mode = 'short clip';
                                return Navigator.of(context).pop(mode);
                              },

                              title: Text('short clip 업로드'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            );

            if (!context.mounted) return;

            if (mode == 'image') {
              try {
                final picker = NativeImagePicker();
                final files = await picker.pickMultipleImages(maxCount: 10);

                if (!mounted) return;

                if (files.isNotEmpty) {
                  print('DEBUG: 선택된 파일 수: ${files.length}');
                  final upload = context.read<UploadService>();

                  final placeholderIds = <String>[];
                  for (final f in files) {
                    placeholderIds.add(
                      widget.editorService.addImagePlaceholderNode(f.path),
                    );
                  }

                  // 즉시 로딩 피드백: 업로드 시작 전 가벼운 로딩 오버레이를 잠깐 표시할 수 있음(필요 시)
                  final tasks = await upload.uploadFilesViaServerBatches(
                    files,
                    kind: UploadKind.editorImage,
                  );

                  if (!mounted) return;

                  final count =
                      tasks.length < placeholderIds.length
                          ? tasks.length
                          : placeholderIds.length;
                  for (int i = 0; i < count; i++) {
                    final t = tasks[i];
                    final id = placeholderIds[i];
                    if (t.state == UploadState.success &&
                        (t.url ?? '').isNotEmpty) {
                      await widget.editorService.replacePlaceholderWithUrl(
                        id,
                        t.url!,
                        mediaId: t.imageId,
                      );
                    } else {
                      widget.editorService.deleteImagePlaceholderNode(id);
                    }
                  }

                  // 키보드는 이미 내려가 있으므로 추가 unfocus 불필요
                }
              } catch (e) {
                debugPrint('image pick/upload error: $e');
              }
            }
            if (mode == 'short clip') {
              try {
                // 바텀시트가 완전히 닫힐 때까지 대기
                await Future.delayed(const Duration(milliseconds: 300));

                if (!mounted) return;

                // 시스템 비디오 피커(1개)
                final picker = NativeImagePicker();
                final file = await picker.pickSingleVideo();

                if (!mounted) return;
                if (file == null) return;

                // 길이/용량 선검증(선택)
                // TODO: 필요 시 video_player로 duration 체크, 파일 크기 200MB 이하 확인

                final upload = context.read<UploadService>();

                // 먼저 placeholder 노드 추가 (원본 파일 경로로 즉시 표시)
                print('[VideoUpload] 원본 파일: ${file.path}');
                final originalFileName = file.path.split('/').last;

                // 원본 파일로 썸네일 생성
                print('[VideoUpload] 썸네일 생성 시작...');
                final thumbnail = await VideoCompress.getFileThumbnail(
                  file.path,
                  quality: 50,
                  position: 1000, // 1초 위치
                );
                print('[VideoUpload] 썸네일 생성 완료: ${thumbnail.path}');

                // 압축 전에 즉시 placeholder 추가
                final placeholderId = widget.editorService
                    .addVideoClipPlaceholderNode(
                      file.path,
                      originalFileName,
                      thumbnailPath: thumbnail.path,
                    );

                print('[VideoUpload] Placeholder 추가 완료');

                // MOV 파일을 MP4로 변환 (원본 화질 유지)
                final compressed = await VideoCompress.compressVideo(
                  file.path,
                  quality: VideoQuality.HighestQuality, // 원본 화질 유지
                  deleteOrigin: false,
                );

                if (compressed == null) {
                  throw Exception('비디오 압축 실패');
                }

                final mp4Path = compressed.path!;
                final mp4FileName = mp4Path.split('/').last;
                print('[VideoUpload] MP4 변환 완료: $mp4Path');

                // 압축된 MP4 파일 업로드
                final task = upload.enqueueFile(
                  File(mp4Path),
                  kind: UploadKind.video,
                  overrideName: mp4FileName,
                );

                // 완료 대기(간단 버전)
                task.addListener(() async {
                  print(
                    '[VideoUpload] task.state=${task.state}, task.url=${task.url}',
                  );
                  if (task.state == UploadState.success && task.url != null) {
                    print('[VideoUpload] 성공! URL: ${task.url}');
                    // placeholder를 실제 URL로 교체
                    await widget.editorService.replaceVideoPlaceholderWithUrl(
                      placeholderId,
                      task.url!,
                    );
                    _forceCloseToolbar();

                    // 문서 변경 후 SuperEditor가 포커스를 복원하기 전에 명시적으로 해제
                    if (context.mounted) {
                      FocusManager.instance.primaryFocus?.unfocus();
                    }
                  } else if (task.state == UploadState.failed) {
                    // 영상 업로드 실패 시 에러 표시
                    if (context.mounted) {
                      ErrorHandler.showError(context, '영상 업로드에 실패했습니다.');
                      widget.editorService.deleteVideoPlaceholderNode(
                        placeholderId,
                      );
                      FocusManager.instance.primaryFocus?.unfocus();
                    }
                  }
                });
              } catch (e) {
                debugPrint('video pick/upload error: $e');
              } finally {
                // 영상 처리 완료/실패 후 키보드 내리기 보장
                if (context.mounted) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
              }
            }
          },
        ),

        // 더 이상 하단에서 펼치지 않음
        const SizedBox(width: 10),
        _buildDivider(),
        const SizedBox(width: 10),

        // 텍스트 스타일 섹션 (아이콘만, 옵션은 상단 행)
        _buildMainSvgIcon(
          svgPath: 'assets/icons/ic_text.svg',
          isActive: _expanded == ToolbarSection.text,
          onTap: () => _toggle(ToolbarSection.text),
          size: 24,
        ),
        // 더 이상 하단에서 펼치지 않음
        const SizedBox(width: 10),
        _buildDivider(),
        const SizedBox(width: 10),

        // 정렬 섹션 (아이콘만, 옵션은 상단 행)
        _buildMainIcon(
          icon: _getAlignmentIcon(_currentAlignment),
          isActive: false,
          onTap: () {
            // 왼쪽 -> 가운데 -> 오른쪽 -> 왼쪽 순환
            TextAlign nextAlignment;
            switch (_currentAlignment) {
              case TextAlign.left:
                nextAlignment = TextAlign.center;
                break;
              case TextAlign.center:
                nextAlignment = TextAlign.right;
                break;
              case TextAlign.right:
              default:
                nextAlignment = TextAlign.left;
            }
            final offset = widget.scrollController?.offset;
            widget.stylingService.applyTextAlignment(nextAlignment);
            _updateStyles();
            if (offset != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.scrollController?.jumpTo(offset);
              });
            }
          },
        ),

        const SizedBox(width: 10),
        _buildDivider(),
        const SizedBox(width: 10),

        // 언급/태그 섹션 (아이콘만, 옵션은 상단 행)
        // (언급은 + 메뉴로 이동)

        // 추가(플러스) 섹션 - 상단 행에서 옵션 표시
        _buildMainIcon(
          icon: Icons.add,
          isActive: _expanded == ToolbarSection.insert,
          onTap: () => _toggle(ToolbarSection.insert),
          activeColor: Theme.of(context).colorScheme.onSurface,
          size: 32,
        ),

        // 오른쪽 끝으로 밀어내기 위한 공간
        const Expanded(child: SizedBox()),

        // 키보드 상태에 따라 변하는 부분만 별도 위젯으로 분리
        _KeyboardDependentButtons(
          isKeyboardVisible: widget.isKeyboardVisible,
          isEditMode: widget.isEditMode,
          onDismissKeyboard: widget.onDismissKeyboard,
          onShowDraftList: widget.onShowDraftList,
        ),
        // 더 이상 하단에서 펼치지 않음
      ],
    );
  }

  Widget _buildExpandedToolbar() {
    return Row(
      children: [
        // 닫기 버튼 (왼쪽 끝)
        _buildMainIcon(
          icon: Icons.close,
          isActive: false,
          onTap: _forceCloseToolbar,
          size: 20,
        ),
        const SizedBox(width: 4),
        _buildDivider(),
        const SizedBox(width: 4),
        // 확장된 내용
        Expanded(child: _buildTopExpandedRowContent()),
      ],
    );
  }

  Widget _buildMainIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    Color? activeColor,
    double? size,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color =
        isActive ? (activeColor ?? onSurface) : onSurface.withOpacity(0.5);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 50,
          alignment: Alignment.center,
          child: Icon(icon, size: size ?? (isActive ? 28 : 25), color: color),
        ),
      ),
    );
  }

  Widget _buildMainSvgIcon({
    required String svgPath,
    required bool isActive,
    required VoidCallback onTap,
    double? size,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color = onSurface.withOpacity(0.5);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 40,
          alignment: Alignment.center,
          child: SvgPicture.asset(
            svgPath,
            width: size ?? (isActive ? 28 : 25),
            height: size ?? (isActive ? 28 : 25),
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: isActive ? surfaceVariant : Colors.transparent,
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
            color: isActive ? onSurface : onSurface.withOpacity(0.4),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final Color borderColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.15);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: 1,
      height: 28,
      color: borderColor,
    );
  }

  Widget _buildColorDot(Color color, VoidCallback onTap) {
    final Color borderColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.15);
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
            border: Border.all(color: borderColor),
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

  Widget _buildChip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final Color onSurface = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.7);
    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: onTap,

        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(icon, size: 20, color: onSurface)],
          ),
        ),
      ),
    );
  }

  Widget _buildSvgChip({
    required String svgPath,
    required String label,
    VoidCallback? onTap,
  }) {
    final Color onSurface = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.7);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,

        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                svgPath,
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(onSurface, BlendMode.srcIn),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // (unused) 정렬 토글 버튼 - 상단 확장 행으로 이동됨

  // 현재 정렬 상태에 따른 아이콘 반환
  IconData _getAlignmentIcon(TextAlign alignment) {
    switch (alignment) {
      case TextAlign.left:
        return Icons.format_align_left;
      case TextAlign.center:
        return Icons.format_align_center;
      case TextAlign.right:
        return Icons.format_align_right;
      default:
        return Icons.format_align_center;
    }
  }

  // 폰트 사이즈 선택 행
  Widget _buildFontSizeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 왼쪽 화살표
        GestureDetector(
          onTap: () {
            setState(() {
              _textPanel = TextPanel.none;
            });
          },
          child: Icon(
            Icons.chevron_left,
            size: 20,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 16),
        // 폰트 사이즈 버튼들
        _buildFontSizeButton('11', 11),
        const SizedBox(width: 8),
        _buildFontSizeButton('13', 13),
        const SizedBox(width: 8),
        _buildFontSizeButton('15', 15),
        const SizedBox(width: 8),
        _buildFontSizeButton('16', 16),
        const SizedBox(width: 8),
        _buildFontSizeButton('19', 19),
        const SizedBox(width: 8),
        _buildFontSizeButton('24', 24),
        const SizedBox(width: 8),
        _buildFontSizeButton('28', 28),
        const SizedBox(width: 16),
        _buildDivider(),
        const SizedBox(width: 16),
      ],
    );
  }

  // 폰트 사이즈 버튼
  Widget _buildFontSizeButton(String label, double size) {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final currentSize = _getCurrentFontSize();
    final isActive = currentSize == size;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.stylingService.changeFontSize(size);
          _updateStyles();
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isActive ? surfaceVariant : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isActive ? onSurface : onSurface.withOpacity(0.6),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 축약 버튼: 사이즈
  Widget _buildSizeCollapsedButton() {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final currentSize = _getCurrentFontSize().toInt();
    return Material(
      color: _textPanel == TextPanel.size ? surfaceVariant : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() {
            _textPanel =
                _textPanel == TextPanel.size ? TextPanel.none : TextPanel.size;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Text(
                '$currentSize',
                style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 축약 버튼: 색상
  Widget _buildColorCollapsedButton() {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color:
          _textPanel == TextPanel.color ? surfaceVariant : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() {
            _textPanel =
                _textPanel == TextPanel.color
                    ? TextPanel.none
                    : TextPanel.color;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [Icon(Icons.circle, size: 18, color: onSurface)],
          ),
        ),
      ),
    );
  }

  // 펼쳐진 색상 팔레트 행
  Widget _buildColorPaletteRow() {
    final List<Color> palette = [
      Colors.white,
      Colors.black,
      const Color(0xFFE53935),
      const Color(0xFFD81B60),
      const Color(0xFF8E24AA),
      const Color(0xFF5E35B1),
      const Color(0xFF3949AB),
      const Color(0xFF1E88E5),
      const Color(0xFF039BE5),
      const Color(0xFF00ACC1),
      const Color(0xFF00897B),
      const Color(0xFF43A047),
      const Color(0xFF7CB342),
      const Color(0xFFC0CA33),
      const Color(0xFFFDD835),
      const Color(0xFFFFB300),
      const Color(0xFFF57C00),
      const Color(0xFF6D4C41),
      const Color(0xFF9E9E9E),
      const Color(0xFF607D8B),
    ];

    return Row(
      children: [
        // 왼쪽 화살표
        GestureDetector(
          onTap: () {
            setState(() {
              _textPanel = TextPanel.none;
            });
          },
          child: Icon(
            Icons.chevron_left,
            size: 20,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 16),
        for (final c in palette) ...[
          _buildColorDot(c, () {
            widget.stylingService.applyTextColor(c);
            _updateStyles();
          }),
        ],

        const SizedBox(width: 16),
      ],
    );
  }

  // 현재 폰트 사이즈 가져오기
  double _getCurrentFontSize() {
    final selection = widget.stylingService.composer.selection;
    if (selection == null) return 16.0;

    final node = widget.stylingService.editor.document.getNodeById(
      selection.base.nodeId,
    );
    if (node is! TextNode) return 16.0;

    final position = selection.base.nodePosition as TextNodePosition;
    final attributions = node.text.getAllAttributionsAt(position.offset);

    for (final attribution in attributions) {
      if (attribution is FontSizeAttribution) {
        return attribution.fontSize;
      }
    }

    return 16.0; // 기본값
  }

  // 스티커 종류 선택 메서드
  Future<void> _selectStickerType(StickerKind kind) async {
    _toggle(ToolbarSection.none); // 메뉴 닫기

    // 키보드 내리기 (한 번만, 충분한 시간 대기)
    FocusManager.instance.primaryFocus?.unfocus();
    // 선택된 종류에 따라 해당 오버레이로 이동
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder:
            (_, __, ___) => StickerOverlay(
              initialKind: kind,
              scrollController: widget.scrollController,
              onSubmit: ({
                required String text,
                String? emoji,
                Uint8List? image,
                Map<String, dynamic>? textStyle,
              }) {
                final svc = context.read<StickerService>();

                // 그리기의 경우 textStyle에 벡터 데이터가 포함되어 있음
                if (textStyle != null && textStyle.containsKey('drawingData')) {
                  final drawingData =
                      textStyle['drawingData'] as Map<String, dynamic>;
                  final strokes =
                      (drawingData['strokes'] as List)
                          .cast<Map<String, dynamic>>();
                  final pos = drawingData['position'] as Map<String, dynamic>;
                  // DrawingOverlay에서 이미 문서 좌표로 변환된 위치를 반환하므로 추가 보정 불필요
                  final at = Offset(
                    (pos['x'] as num).toDouble(),
                    (pos['y'] as num).toDouble(),
                  );
                  svc.addDrawingSticker(strokes, at);
                } else if (image != null) {
                  // 일반 이미지 스티커 - 화면 정가운데
                  final Size size = MediaQuery.of(context).size;
                  final scrollY = widget.scrollController?.offset ?? 0.0;
                  // 이미지는 좌상단이 기준점이지만, 위치는 그냥 중앙값 사용
                  // (나중에 사용자가 드래그로 조정)
                  final at = Offset(
                    size.width / 2 - 100,
                    scrollY + size.height / 2 - 200,
                  );
                  svc.addImageSticker(image, at);
                } else if ((emoji ?? '').isNotEmpty) {
                  final Size size = MediaQuery.of(context).size;
                  final scrollY = widget.scrollController?.offset ?? 0.0;
                  final at = Offset(size.width * 0.5 - 60, scrollY + 200);
                  svc.addEmojiSticker(emoji!, at);
                } else if (text.trim().isNotEmpty) {
                  final Size size = MediaQuery.of(context).size;
                  final scrollY = widget.scrollController?.offset ?? 0.0;
                  final at = Offset(size.width * 0.5 - 60, scrollY + 200);
                  svc.addTextStickerWithStyle(text.trim(), textStyle, at);
                }
                // 스티커 추가 후 상단 두번째 툴바 자동 닫기
                _toggle(ToolbarSection.none);
              },
            ),
      ),
    );

    if (context.mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  // 🎨 형광펜 토글 버튼 (색상 팔레트 포함)
  Widget _buildHighlightToggleIcon() {
    final isActive = _currentStyles['highlight'] ?? false;
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Material(
      color: isActive ? surfaceVariant : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        // 탭 시 바로 팔레트 표시 (롱프레스 불필요)
        onTap: _showHighlightColorPalette,
        onLongPress: () {
          // 롱프레스 시 색상 팔레트 표시
          _showHighlightColorPalette();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.highlight,
                size: 20,
                color: isActive ? onSurface : onSurface.withOpacity(0.6),
              ),
              if (isActive) ...[
                const SizedBox(width: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getCurrentHighlightColor(),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: onSurface.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 현재 형광펜 색상 가져오기
  Color _getCurrentHighlightColor() {
    final selection = widget.stylingService.composer.selection;
    if (selection == null) return highlightYellow;

    final node = widget.stylingService.editor.document.getNodeById(
      selection.base.nodeId,
    );
    if (node is! TextNode) return highlightYellow;

    final position = selection.base.nodePosition as TextNodePosition;
    final attributions = node.text.getAllAttributionsAt(position.offset);

    for (final attribution in attributions) {
      if (attribution is HighlightAttribution) {
        return attribution.color;
      }
    }

    return highlightYellow; // 기본값
  }

  // 형광펜 색상 팔레트 표시
  void _showHighlightColorPalette() {
    // 선택 스냅샷 저장: 모달이 떠도 동일 범위에 적용하기 위함
    final selectionSnapshot = widget.stylingService.composer.selection;
    final List<Color> highlightColors = [
      highlightYellow,
      highlightGreen,
      highlightBlue,
      highlightPink,
      highlightOrange,
      highlightPurple,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            padding: const EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: 30,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ...highlightColors.map((color) {
                      return GestureDetector(
                        onTap: () {
                          // 🔧 선택 스냅샷 범위에서 기존 형광펜 제거 후 새 색상 적용
                          widget.stylingService._removeHighlightAttributions(
                            selectionOverride: selectionSnapshot,
                          );
                          widget.stylingService.applyHighlight(
                            color,
                            selectionOverride: selectionSnapshot,
                          );
                          _updateStyles();
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.2),
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }),
                    // 마지막에 제거 아이템(원형) 추가
                    GestureDetector(
                      onTap: () {
                        widget.stylingService._removeHighlightAttributions(
                          selectionOverride: selectionSnapshot,
                        );
                        _updateStyles();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.2),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}

/// 키보드 상태에 따라서만 변경되는 버튼들을 별도 위젯으로 분리
/// 이렇게 하면 키보드 상태 변경 시 이 위젯만 리빌드됨
class _KeyboardDependentButtons extends StatelessWidget {
  final bool isKeyboardVisible;
  final bool isEditMode;
  final VoidCallback? onDismissKeyboard;
  final VoidCallback? onShowDraftList;

  const _KeyboardDependentButtons({
    required this.isKeyboardVisible,
    required this.isEditMode,
    this.onDismissKeyboard,
    this.onShowDraftList,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 키보드가 올라와 있을 때만 키보드 내리기 버튼 표시
        if (isKeyboardVisible)
          _buildMainIcon(
            context: context,
            icon: Icons.keyboard_arrow_down,
            isActive: false,
            onTap: () {
              onDismissKeyboard?.call();
            },
          ),
        // 키보드가 내려가 있고 편집 모드가 아닐 때만 불러오기 버튼 표시
        if (!isKeyboardVisible && !isEditMode) ...[
          const SizedBox(width: 10),
          _buildMainSvgIcon(
            context: context,
            svgPath: 'assets/icons/download.svg',
            isActive: false,
            size: 24,
            onTap: () {
              onShowDraftList?.call();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildMainSvgIcon({
    required String svgPath,
    required bool isActive,
    required VoidCallback onTap,
    double? size,
    required BuildContext context,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color = onSurface.withOpacity(0.5);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 40,
          alignment: Alignment.center,
          child: SvgPicture.asset(
            svgPath,
            width: size ?? (isActive ? 28 : 25),
            height: size ?? (isActive ? 28 : 25),
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }

  Widget _buildMainIcon({
    required BuildContext context,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color =
        isActive ? (activeColor ?? onSurface) : onSurface.withOpacity(0.5);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 50,
          alignment: Alignment.center,
          child: Icon(icon, size: isActive ? 26 : 22, color: color),
        ),
      ),
    );
  }
}
