import 'dart:async';
import 'dart:typed_data';
import 'package:doppy/editor/overlay/sticker_overlay.dart';
import 'package:doppy/editor/overlay/font_overlay.dart';
import 'package:doppy/editor/style/font_catalog.dart';
import 'package:doppy/editor/style/media_upload_handler.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/overlay/link_overlay.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/overlay/mention_overlay.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/providers/locale_provider.dart';

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
    if (selection == null || selection.isCollapsed) {
      // 선택이 없으면 다음 입력에 적용
      composer.preferences.toggleStyle(boldAttribution);
      notifyListeners();
      return;
    }

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
    if (selection == null || selection.isCollapsed) {
      // 선택이 없으면 다음 입력에 적용
      composer.preferences.toggleStyle(italicsAttribution);
      notifyListeners();
      return;
    }

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
    if (selection == null || selection.isCollapsed) {
      // 선택이 없으면 다음 입력에 적용
      composer.preferences.toggleStyle(underlineAttribution);
      notifyListeners();
      return;
    }

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
    if (selection == null || selection.isCollapsed) {
      // 선택이 없으면 다음 입력에 적용
      composer.preferences.toggleStyle(strikethroughAttribution);
      notifyListeners();
      return;
    }

    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: selection,
        attributions: {strikethroughAttribution},
      ),
    ]);
  }

  /// 스포일러 토글 (선택 영역 가리기)
  /// 스포일러는 선택 영역이 있을 때만 작동 (특정 텍스트를 가리는 용도)
  void toggleSpoiler() {
    final selection = composer.selection;
    if (selection == null || selection.isCollapsed) {
      // 스포일러는 선택 영역이 필수
      return;
    }

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

    // 선택이 없으면 다음 입력에 적용
    if (selection == null || selection.isCollapsed) {
      // 기존 색상 제거 (형광펜은 제외!)
      final currentAttrs = composer.preferences.currentAttributions.toList();
      for (final attr in currentAttrs) {
        if (attr is ColorAttribution && attr is! HighlightAttribution) {
          composer.preferences.removeStyle(attr);
        }
      }
      // 새 색상 추가
      composer.preferences.addStyle(ColorAttribution(color));
      notifyListeners();
      return;
    }

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

    // 선택이 없으면 다음 입력에 적용
    if (selection == null || selection.isCollapsed) {
      // 기존 폰트 크기 제거
      final currentAttrs = composer.preferences.currentAttributions.toList();
      for (final attr in currentAttrs) {
        if (attr is FontSizeAttribution) {
          composer.preferences.removeStyle(attr);
        }
      }
      // 새 폰트 크기 추가
      composer.preferences.addStyle(FontSizeAttribution(size));
      notifyListeners();
      return;
    }

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
    // ✅ HighlightAttribution은 제외하고 ColorAttribution만 제거
    final colorAttributions =
        existingAttributions
            .where(
              (attr) =>
                  attr is ColorAttribution && attr is! HighlightAttribution,
            ) // 형광펜은 제외!
            .toSet();

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

    // 선택이 없거나 collapsed면 preferences에서 상태 확인
    if (selection == null || selection.isCollapsed) {
      final currentStyles = composer.preferences.currentAttributions;
      return {
        'bold': currentStyles.contains(boldAttribution),
        'italic': currentStyles.contains(italicsAttribution),
        'underline': currentStyles.contains(underlineAttribution),
        'strikethrough': currentStyles.contains(strikethroughAttribution),
        'highlight': currentStyles.any((attr) => attr is HighlightAttribution),
        'spoiler': currentStyles.contains(spoilerAttribution),
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
      debugPrint('[FontDebug] Google Font 감지: $targetFamily');
    } else if (fontItem.localFontFamily != null) {
      // 로컬 폰트
      targetFamily = fontItem.localFontFamily!;
      debugPrint('[FontDebug] 로컬 폰트 감지: $targetFamily');
    } else {
      // 기본 폰트 (null)
      targetFamily = '';
      debugPrint('[FontDebug] 기본 폰트 사용');
    }

    if (selection != null && !selection.isCollapsed) {
      // ✅ 선택 영역이 있으면: Attribution + 메타데이터 동시 적용
      debugPrint(
        '[FontDebug] 선택 영역에 Attribution + 메타데이터로 폰트 적용: $targetFamily',
      );

      // 1. 선택 영역의 기존 FontFamilyAttribution만 제거 (선택 영역 내에서만)
      final existingAttributions = _getAttributionsInSelection(
        selectionOverride: selection,
      );
      final fontAttributions =
          existingAttributions.whereType<FontFamilyAttribution>().toSet();

      if (fontAttributions.isNotEmpty) {
        editor.execute([
          RemoveTextAttributionsRequest(
            documentRange: selection,
            attributions: fontAttributions,
          ),
        ]);
      }

      // 2. 새로운 폰트 attribution 추가 (선택 영역에만)
      if (targetFamily.isNotEmpty) {
        final newAttribution = FontFamilyAttribution(targetFamily);
        editor.execute([
          AddTextAttributionsRequest(
            documentRange: selection,
            attributions: {newAttribution},
          ),
        ]);
      }

      // 3. 선택된 노드들의 메타데이터도 업데이트
      final selectedNodes = editor.document.getNodesInside(
        selection.extent,
        selection.base,
      );

      for (final node in selectedNodes) {
        if (node is ParagraphNode) {
          final updatedMetadata = Map<String, dynamic>.from(node.metadata);
          if (targetFamily.isNotEmpty) {
            updatedMetadata['fontFamily'] = targetFamily;
            debugPrint(
              '[TextStylingService] 📝 선택된 ParagraphNode ${node.id}에 fontFamily 메타데이터 저장: $targetFamily',
            );
          } else {
            updatedMetadata.remove('fontFamily');
            debugPrint(
              '[TextStylingService] 📝 선택된 ParagraphNode ${node.id}에서 fontFamily 메타데이터 제거',
            );
          }

          // 노드 교체로 메타데이터 업데이트 (텍스트와 Attribution은 그대로 유지)
          final newNode = ParagraphNode(
            id: node.id,
            text: node.text, // 🎯 기존 텍스트와 Attribution 그대로 유지
            metadata: updatedMetadata,
          );

          editor.execute([
            ReplaceNodeRequest(existingNodeId: node.id, newNode: newNode),
          ]);
        }
      }
    } else {
      // ✅ 선택 영역이 없으면: 모든 ParagraphNode에 메타데이터만 설정 (기존 Attribution 유지)

      // 전역 폰트 설정
      if (_globalFontFamily != targetFamily) {
        _globalFontFamily = targetFamily.isNotEmpty ? targetFamily : null;
        notifyListeners();
      }

      // 모든 ParagraphNode에 메타데이터만 업데이트 (기존 Attribution은 그대로 유지)
      final requests = <EditRequest>[];

      for (int i = 0; i < editor.document.length; i++) {
        final node = editor.document.getNodeAt(i);
        if (node is ParagraphNode) {
          final updatedMetadata = Map<String, dynamic>.from(node.metadata);

          // 🎯 기존 Attribution이 있는지 확인
          bool hasExistingAttribution = false;
          for (int j = 0; j < node.text.text.length; j++) {
            final attributions = node.text.getAllAttributionsAt(j);
            if (attributions.any((attr) => attr is FontFamilyAttribution)) {
              hasExistingAttribution = true;
              break;
            }
          }

          // 메타데이터만 업데이트 (기존 Attribution은 유지)
          if (targetFamily.isNotEmpty) {
            updatedMetadata['fontFamily'] = targetFamily;
            debugPrint(
              '[TextStylingService] 📝 ParagraphNode ${node.id}에 fontFamily 메타데이터 저장: $targetFamily (기존 Attribution 유지: $hasExistingAttribution)',
            );
          } else {
            // 🎯 기존 Attribution이 없을 때만 메타데이터 제거
            if (!hasExistingAttribution) {
              updatedMetadata.remove('fontFamily');
              debugPrint(
                '[TextStylingService] 📝 ParagraphNode ${node.id}에서 fontFamily 메타데이터 제거 (기존 Attribution 없음)',
              );
            } else {
              debugPrint(
                '[TextStylingService] ⚠️ ParagraphNode ${node.id}에서 메타데이터 유지 (기존 Attribution 있음)',
              );
            }
          }

          // 노드 교체로 메타데이터 업데이트 (텍스트와 Attribution은 그대로 유지)
          final newNode = ParagraphNode(
            id: node.id,
            text: node.text, // 🎯 기존 텍스트와 Attribution 그대로 유지
            metadata: updatedMetadata,
          );

          requests.add(
            ReplaceNodeRequest(existingNodeId: node.id, newNode: newNode),
          );
        }
      }

      // 한 번에 실행
      if (requests.isNotEmpty) {
        editor.execute(requests);
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
            if (_textPanel == TextPanel.none) ...[_buildFontNameButton()],
            if (_textPanel == TextPanel.none) ...[_buildSizeCollapsedButton()],
            // 축약 아이콘: 사이즈 / 색상
            if (_textPanel == TextPanel.size) ...[_buildFontSizeRow()],
            if (_textPanel == TextPanel.none) ...[_buildColorCollapsedButton()],
            if (_textPanel == TextPanel.color) ...[_buildColorPaletteRow()],
            SizedBox(width: 6),

            // 간단 토글들
            _buildToggleIcon(
              icon: Icons.format_bold,
              isActive: _currentStyles['bold'] ?? false,
              onTap: () {
                widget.stylingService.toggleBold();
                _updateStyles();
              },
              size: 24,
            ),

            const SizedBox(width: 6),
            _buildToggleIcon(
              icon: Icons.format_italic,
              isActive: _currentStyles['italic'] ?? false,
              onTap: () {
                widget.stylingService.toggleItalic();
                _updateStyles();
              },
              size: 24,
            ),

            SizedBox(width: 6),
            _buildToggleIcon(
              icon: Icons.format_underlined,
              isActive: _currentStyles['underline'] ?? false,
              onTap: () {
                widget.stylingService.toggleUnderline();
                _updateStyles();
              },
              size: 24,
            ),

            SizedBox(width: 6),
            _buildToggleIcon(
              icon: Icons.format_strikethrough,
              isActive: _currentStyles['strikethrough'] ?? false,
              onTap: () {
                widget.stylingService.toggleStrikethrough();
                _updateStyles();
              },
              size: 24,
            ),
            SizedBox(width: 6),
            // 🎨 형광펜 토글 버튼 (실제 형광펜 색상 표시)
            _buildHighlighterToggleIcon(
              isActive: _currentStyles['highlight'] ?? false,
              onTap: () {
                _showHighlightColorPalette();
              },
            ),
            SizedBox(width: 6),

            // 🙈 스포일러(가림) 토글 버튼 (선택 영역 필수)
            _buildSvgToggleIcon(
              svgPath: 'assets/icons/spoiler.svg',
              isActive: _currentStyles['spoiler'] ?? false,
              label: '스포일러',
              onTap:
                  _hasTextSelection
                      ? () {
                        widget.stylingService.toggleSpoiler();
                        _updateStyles();
                      }
                      : () {},
              size: 28,
            ),

            SizedBox(width: 40),

            // 오른쪽 끝으로 밀기
          ],
        );

      case ToolbarSection.insert:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildSvgChip(
                size: 24,
                svgPath: 'assets/icons/editor_pen.svg',
                label: '그리기',
                onTap: () => _selectStickerType(StickerKind.draw),
              ),

              _buildSvgChip(
                size: 26,
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
                            autoSubmit: true, // 🎯 프로필과 동일하게 즉시 미리보기 표시
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
                size: 24,
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
                size: 24,
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
                debugPrint('언급 삽입');
              },
            ),
            const SizedBox(width: 6),
            _buildChip(
              icon: Icons.tag,
              label: '태그',
              onTap: () {
                debugPrint('태그 삽입');
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
  final ValueNotifier<bool>? videoUploadIndicatorNotifier; // 영상 업로드 인디케이터 상태

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
    this.videoUploadIndicatorNotifier,
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

    // 🎯 멘션 노드에서 선택이면 툴바 열지 않음
    bool isMentionNode = false;
    if (hasSelection) {
      try {
        final nodeId = selection.extent.nodeId;
        final node = widget.editorService.document.getNodeById(nodeId);
        if (node is ParagraphNode) {
          isMentionNode = node.metadata['mention'] == true;
        }
      } catch (_) {}
    }

    if (_hasTextSelection != hasSelection) {
      setState(() {
        _hasTextSelection = hasSelection;
        if (hasSelection && !isMentionNode) {
          // 텍스트가 선택되면 자동으로 텍스트 툴바 열기 (멘션 노드 제외)
          _expanded = ToolbarSection.text;
        } else {
          // 선택이 해제되거나 멘션 노드면 툴바 닫기
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
    if (!mounted) return; // 🎯 mounted 체크 추가
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
    // 선택 영역을 저장 (포커스 해제 전에)
    final savedSelection = widget.stylingService.composer.selection;
    FocusManager.instance.primaryFocus?.unfocus();

    // DraggableScrollableController 생성
    final sheetController = DraggableScrollableController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (ctx) => DraggableScrollableSheet(
            controller: sheetController, // 컨트롤러 연결
            initialChildSize: 0.6, // 처음엔 반만
            minChildSize: 0.5,
            maxChildSize: 0.9, // 위로 드래그하면 거의 전체까지
            builder:
                (_, scrollController) => FontOverlay(
                  scrollController:
                      scrollController, // DraggableScrollableSheet의 컨트롤러 전달
                  sheetController: sheetController, // 시트 컨트롤러 전달
                  onSelect: (fontItem) {
                    // 저장된 selection 복원
                    if (savedSelection != null) {
                      widget.stylingService.editor.execute([
                        ChangeSelectionRequest(
                          savedSelection,
                          SelectionChangeType.placeCaret,
                          SelectionReason.userInteraction,
                        ),
                      ]);
                    }

                    // 폰트 적용
                    widget.stylingService.applyFont(fontItem);
                  },
                  // 현재 적용 폰트를 최상단에 노출
                  initialCurrentFamily: () {
                    final current = _getCurrentFontName();
                    final localeProvider = Provider.of<LocaleProvider>(
                      ctx,
                      listen: false,
                    );
                    if (current == '기본' || current == 'Default') {
                      // 🎯 영어 모드일 때는 기본 시스템 폰트 이름 반환
                      return localeProvider.isEnglish
                          ? 'Default Sans Serif'
                          : '기본 산세리프';
                    }
                    return current;
                  }(),
                  onClose: () => Navigator.of(ctx).pop(),
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color background = Theme.of(context).colorScheme.background;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
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
        ),
      ],
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
            try {
              // 키보드 내리기
              FocusManager.instance.primaryFocus?.unfocus();
              widget.stylingService.composer.clearSelection();

              if (!mounted) return;

              // 🎯 MediaUploadHandler 생성
              final handler = MediaUploadHandler(
                context: context,
                editorService: widget.editorService,
                onUploadComplete: _forceCloseToolbar,
              );

              // 미디어 타입 선택
              final mode = await handler.showMediaTypeSelector();
              if (!context.mounted || mode == null) return;

              // 선택된 타입에 따라 처리
              if (mode == 'image') {
                await handler.handleImageUpload();
              } else if (mode == 'short clip') {
                await handler.handleVideoUpload();
              }
            } catch (e) {
              debugPrint('[Toolbar] 미디어 업로드 에러: $e');
              if (context.mounted) {
                FocusManager.instance.primaryFocus?.unfocus();
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
        // 폰트 크기/색상 패널이 펼쳐졌을 때는 닫기 버튼 숨김
        if (_textPanel == TextPanel.none) ...[
          const SizedBox(width: 4),
          // 닫기 버튼 (왼쪽 끝)
          _buildMainIcon(
            icon: Icons.close,
            isActive: false,
            onTap: _forceCloseToolbar,
            size: 20,
          ),
          const SizedBox(width: 2),
          _buildDivider(),
          const SizedBox(width: 4),
        ],
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
    required VoidCallback? onTap,
    double? size,
  }) {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final bool isEnabled = onTap != null;

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.3,
      child: Material(
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
              size: size ?? 20,
              color: isActive ? onSurface : onSurface.withOpacity(0.4),
            ),
          ),
        ),
      ),
    );
  }

  /// 현재 적용 중인 폰트명 가져오기
  String _getCurrentFontName() {
    final selection = widget.stylingService.composer.selection;

    // 선택 영역이 있으면 해당 범위의 폰트 확인
    if (selection != null && !selection.isCollapsed) {
      final node = widget.stylingService.editor.document.getNodeById(
        selection.base.nodeId,
      );
      if (node is ParagraphNode) {
        // 1. Attribution에서 폰트 확인
        final position = selection.base.nodePosition as TextNodePosition;
        final attributions = node.text.getAllAttributionsAt(position.offset);
        for (final attribution in attributions) {
          if (attribution is FontFamilyAttribution) {
            return attribution.fontFamily;
          }
        }
        // 2. 메타데이터에서 폰트 확인
        final fontFamily = node.metadata['fontFamily'] as String?;
        if (fontFamily != null && fontFamily.isNotEmpty) {
          return fontFamily;
        }
      }
    }

    // 선택 영역이 없으면 전역 폰트 또는 첫 번째 문단의 폰트 확인
    final globalFont = widget.stylingService.globalFontFamily;
    if (globalFont != null && globalFont.isNotEmpty) {
      return globalFont;
    }

    // 첫 번째 문단의 폰트 확인
    for (int i = 0; i < widget.stylingService.editor.document.length; i++) {
      final node = widget.stylingService.editor.document.getNodeAt(i);
      if (node is ParagraphNode) {
        final fontFamily = node.metadata['fontFamily'] as String?;
        if (fontFamily != null && fontFamily.isNotEmpty) {
          return fontFamily;
        }
      }
    }

    // 🎯 로케일에 따라 기본 폰트 이름 반환
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    return localeProvider.isEnglish ? 'Default' : '기본'; // 기본 폰트
  }

  /// 폰트명 표시 버튼
  Widget _buildFontNameButton() {
    final String fontName = _getCurrentFontName();
    final String displayName =
        fontName.length > 8 ? '${fontName.substring(0, 8)}' : fontName;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _openFontPickerOverlay,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 10, right: 8, top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_up,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final Color borderColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.1);
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
            width: 22,
            height: 22,
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
    double? size,
  }) {
    final Color onSurface = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.6);
    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: onTap,

        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(icon, size: size ?? 20, color: onSurface)],
          ),
        ),
      ),
    );
  }

  Widget _buildSvgToggleIcon({
    required String svgPath,
    required bool isActive,
    required VoidCallback onTap,
    required String label,
    double? size,
  }) {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.6);

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
          child: SvgPicture.asset(
            svgPath,
            width: size ?? 24,
            height: size ?? 24,
            colorFilter: ColorFilter.mode(onSurface, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }

  /// 형광펜 전용 토글 버튼 (실제 형광펜 색상 표시)
  Widget _buildHighlighterToggleIcon({
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color? highlightColor = _getCurrentHighlightColor();

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
          child: SvgPicture.asset(
            'assets/icons/highlighter.svg',
            width: 24.5,
            height: 24.5,
            colorFilter: ColorFilter.mode(
              // 활성화 시: 실제 형광펜 색상, 비활성화 시: 회색
              isActive && highlightColor != null
                  ? highlightColor
                  : onSurface.withOpacity(0.4),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSvgChip({
    required String svgPath,
    required String label,
    VoidCallback? onTap,
    double? size,
  }) {
    final Color onSurface = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.6);
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
                width: size ?? 20,
                height: size ?? 20,
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
        const SizedBox(width: 6),
        // 왼쪽 화살표
        GestureDetector(
          onTap: () {
            setState(() {
              _textPanel = TextPanel.none;
            });
          },
          child: Icon(
            Icons.chevron_left,
            size: 28,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 4),
        // 폰트 사이즈 버튼들
        _buildFontSizeButton('10', 11),
        const SizedBox(width: 8),
        _buildFontSizeButton('13', 13),
        const SizedBox(width: 8),
        _buildFontSizeButton('16', 16),
        const SizedBox(width: 8),
        _buildFontSizeButton('19', 19),
        const SizedBox(width: 8),
        _buildFontSizeButton('22', 22),
        const SizedBox(width: 8),
        _buildFontSizeButton('25', 25),
        const SizedBox(width: 8),
        _buildFontSizeButton('28', 28),
        const SizedBox(width: 16),
        _buildFontSizeButton('31', 31),
        const SizedBox(width: 8),
        _buildFontSizeButton('34', 34),
        const SizedBox(width: 8),
        _buildFontSizeButton('37', 37),
        const SizedBox(width: 8),
        _buildFontSizeButton('40', 40),
        const SizedBox(width: 8),
        _buildFontSizeButton('43', 43),
        const SizedBox(width: 8),
        _buildFontSizeButton('46', 46),
        const SizedBox(width: 8),
        _buildFontSizeButton('49', 49),
        const SizedBox(width: 8),
        _buildFontSizeButton('52', 52),
        const SizedBox(width: 8),

        const SizedBox(width: 8),
        _buildFontSizeButton('55', 55),
        const SizedBox(width: 8),
        _buildFontSizeButton('58', 58),
        const SizedBox(width: 8),
        _buildFontSizeButton('61', 61),
        const SizedBox(width: 8),
        _buildFontSizeButton('64', 64),
        const SizedBox(width: 8),
        _buildDivider(),
        const SizedBox(width: 16),
      ],
    );
  }

  // 폰트 사이즈 버튼
  Widget _buildFontSizeButton(String label, double size) {
    final Color surfaceVariant = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.1);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final currentSize = _getCurrentFontSize();
    final isActive = currentSize == size;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final offset = widget.scrollController?.offset;
          widget.stylingService.changeFontSize(size);
          setState(() {
            _textPanel = TextPanel.none; // 크기 선택 후 패널 닫기
          });
          _updateStyles();
          if (offset != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.scrollController?.jumpTo(offset);
            });
          }
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
                fontSize: 17,
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
    final Color onSurface = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.6);
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
          padding: const EdgeInsets.only(left: 10, right: 10, bottom: 1),
          child: Row(
            children: [
              Text(
                '$currentSize',
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.w400,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 축약 버튼: 색상 (현재 적용된 색상 표시)
  Widget _buildColorCollapsedButton() {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color currentColor = _getCurrentTextColor();

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
          padding: const EdgeInsets.only(left: 12, right: 8, bottom: 1.4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/icons/ic_text.svg',
                width: 19.5,
                height: 19.5,
                colorFilter: ColorFilter.mode(
                  onSurface.withOpacity(0.6),
                  BlendMode.srcIn,
                ),
              ),

              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(height: 10),
                  // 🎨 여러 색상이 섞여 있으면 무지개 닷 표시
                  Builder(
                    builder: (context) {
                      final colors = _getTextColorsInSelection();
                      if (colors.length > 1) {
                        // 무지개 닷 (여러 색상)
                        return Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors:
                                  colors.length > 1
                                      ? colors
                                      : [currentColor, currentColor],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        );
                      } else {
                        // 단일 색상 닷
                        return Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: currentColor,
                            shape: BoxShape.circle,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 현재 적용 중인 텍스트 색상 가져오기
  Color _getCurrentTextColor() {
    final selection = widget.stylingService.composer.selection;

    // 선택 영역이 있으면 해당 범위의 색상 확인
    if (selection != null && !selection.isCollapsed) {
      final node = widget.stylingService.editor.document.getNodeById(
        selection.base.nodeId,
      );
      if (node is TextNode) {
        final position = selection.base.nodePosition as TextNodePosition;
        final attributions = node.text.getAllAttributionsAt(position.offset);
        for (final attribution in attributions) {
          // ✅ 형광펜은 제외하고 글자색만 반환
          if (attribution is ColorAttribution &&
              attribution is! HighlightAttribution) {
            return attribution.color;
          }
        }
      }
    } else {
      // 선택이 없으면 preferences에서 확인
      final currentAttrs =
          widget.stylingService.composer.preferences.currentAttributions;
      for (final attr in currentAttrs) {
        // ✅ 형광펜은 제외하고 글자색만 반환
        if (attr is ColorAttribution && attr is! HighlightAttribution) {
          return attr.color;
        }
      }
    }

    // 기본 색상 (테마의 onSurface)
    return Theme.of(context).colorScheme.onSurface;
  }

  /// 선택 영역에 여러 색상이 섞여 있는지 확인 (단일 노드 내 선택만 체크)
  List<Color> _getTextColorsInSelection() {
    final selection = widget.stylingService.composer.selection;
    final colors = <Color>{};

    if (selection != null && !selection.isCollapsed) {
      final startNode = widget.stylingService.editor.document.getNodeById(
        selection.base.nodeId,
      );
      final endNode = widget.stylingService.editor.document.getNodeById(
        selection.extent.nodeId,
      );

      if (startNode is TextNode && endNode is TextNode) {
        final startPos = selection.base.nodePosition as TextNodePosition;
        final endPos = selection.extent.nodePosition as TextNodePosition;

        // 🎯 단일 노드 내에서 선택된 경우만 여러 색상 체크
        if (startNode.id == endNode.id) {
          final startOffset = startPos.offset;
          final endOffset = endPos.offset;
          for (int i = startOffset; i < endOffset; i++) {
            final attributions = startNode.text.getAllAttributionsAt(i);
            for (final attribution in attributions) {
              if (attribution is ColorAttribution &&
                  attribution is! HighlightAttribution) {
                colors.add(attribution.color);
              }
            }
          }
        } else {
          // 여러 노드에 걸친 선택
          final startIndex = widget.stylingService.editor.document
              .getNodeIndexById(startNode.id);
          final endIndex = widget.stylingService.editor.document
              .getNodeIndexById(endNode.id);

          for (int i = startIndex; i <= endIndex; i++) {
            final node = widget.stylingService.editor.document.getNodeAt(i);
            if (node is TextNode) {
              final startOffset = i == startIndex ? startPos.offset : 0;
              final endOffset =
                  i == endIndex ? endPos.offset : node.text.text.length;

              for (int j = startOffset; j < endOffset; j++) {
                final attributions = node.text.getAllAttributionsAt(j);
                for (final attribution in attributions) {
                  if (attribution is ColorAttribution &&
                      attribution is! HighlightAttribution) {
                    colors.add(attribution.color);
                  }
                }
              }
            }
          }
        }
      }
    }

    return colors.toList();
  }

  /// 현재 형광펜 색상 가져오기
  Color? _getCurrentHighlightColor() {
    final selection = widget.stylingService.composer.selection;

    // 선택 영역이 있으면 해당 범위의 형광펜 색상 확인
    if (selection != null && !selection.isCollapsed) {
      final node = widget.stylingService.editor.document.getNodeById(
        selection.base.nodeId,
      );
      if (node is TextNode) {
        final position = selection.base.nodePosition as TextNodePosition;
        final attributions = node.text.getAllAttributionsAt(position.offset);
        for (final attribution in attributions) {
          if (attribution is HighlightAttribution) {
            return attribution.color;
          }
        }
      }
    }

    return null; // 형광펜이 없으면 null
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
        const SizedBox(width: 6),
        // 왼쪽 화살표
        GestureDetector(
          onTap: () {
            setState(() {
              _textPanel = TextPanel.none;
            });
          },
          child: Icon(
            Icons.chevron_left,
            size: 28,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 16),
        for (final c in palette) ...[
          _buildColorDot(c, () {
            widget.stylingService.applyTextColor(c);
            setState(() {
              _textPanel = TextPanel.none; // 색상 선택 후 패널 닫기
            });
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
    // 선택이 없거나 커서만 있을 때: preferences에서 조회
    if (selection == null || selection.isCollapsed) {
      final current =
          widget.stylingService.composer.preferences.currentAttributions;
      for (final attr in current) {
        if (attr is FontSizeAttribution) {
          return attr.fontSize;
        }
      }
      return 16.0;
    }

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
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
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
                  final groupIndex = drawingData['groupIndex'] as int?;
                  // DrawingOverlay에서 이미 문서 좌표로 변환된 위치를 반환하므로 추가 보정 불필요
                  final at = Offset(
                    (pos['x'] as num).toDouble(),
                    (pos['y'] as num).toDouble(),
                  );
                  svc.addDrawingSticker(strokes, at, groupIndex: groupIndex);
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
                }
                // 🎯 emoji, text 스티커 제거됨 (PNG 드로잉만 지원)
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
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildMainIcon(
              context: context,
              icon: Icons.keyboard_arrow_down,
              isActive: false,
              size: 30,
              onTap: () {
                onDismissKeyboard?.call();
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMainIcon({
    required BuildContext context,
    required IconData icon,
    required bool isActive,
    double? size,
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
          child: Icon(icon, size: size ?? (isActive ? 26 : 22), color: color),
        ),
      ),
    );
  }
}
