import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/style/font_catalog.dart';
import 'package:doppy/editor/style/text_attributions.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 텍스트 스타일링 관리자
///
/// ✅ 목적:
/// - Toolbar(UI)와 분리된 "편집 동작"만 제공 (스타일 토글/정렬/폰트/하이라이트/스포일러 등)
/// - PostWrite/Stylesheet/PostReader/Exporter가 `defualt_toolbar.dart`에 종속되지 않도록 구조 분리
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

    // 1) 스포일러 attribution 먼저 적용 (이 프레임에서 박스 계산이 바로 되도록)
    // 2) selection 해제는 다음 프레임에 수행 (레이아웃/렌더 트리 안정화 후)
    final collapseTo = selection.extent;
    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: selection,
        attributions: {spoilerAttribution},
      ),
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(position: collapseTo),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
    });
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

  /// 외부(UI)에서 형광펜을 제거하고 싶을 때 사용.
  ///
  /// - 기존 구현의 `_removeHighlightAttributions`는 라이브러리 프라이빗이라
  ///   다른 파일(`defualt_toolbar.dart`)에서 접근할 수 없어서 public wrapper를 둔다.
  void removeHighlight({DocumentSelection? selectionOverride}) {
    _removeHighlightAttributions(selectionOverride: selectionOverride);
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
  /// 현재 스타일시트의 다른 속성들은 그대로 유지하고 텍스트 높이(폰트 크기)만 수정
  void changeFontSize(double size) {
    final selection = composer.selection;

    // 선택이 없으면 다음 입력에 적용
    if (selection == null || selection.isCollapsed) {
      // 🎯 현재 스타일시트에서 폰트 크기만 제거 (다른 속성은 유지)
      final currentAttrs = composer.preferences.currentAttributions.toList();
      for (final attr in currentAttrs) {
        if (attr is FontSizeAttribution) {
          composer.preferences.removeStyle(attr);
        }
      }
      // 새 폰트 크기만 추가 (다른 스타일은 그대로 유지)
      composer.preferences.addStyle(FontSizeAttribution(size));
      notifyListeners();
      return;
    }

    // 🎯 선택 영역이 있는 경우: 현재 스타일시트의 다른 속성들은 그대로 유지하고 폰트 크기만 변경
    // 1. 현재 선택 영역의 모든 속성 가져오기
    final existingAttributions = _getAttributionsInSelection();

    // 2. 폰트 크기 속성만 제거 (다른 속성은 유지)
    final fontSizeAttributions =
        existingAttributions.whereType<FontSizeAttribution>().toSet();

    final requests = <EditRequest>[];

    // 3. 기존 폰트 크기 속성 제거
    if (fontSizeAttributions.isNotEmpty) {
      requests.add(
        RemoveTextAttributionsRequest(
          documentRange: selection,
          attributions: fontSizeAttributions,
        ),
      );
    }

    // 4. 새 폰트 크기만 추가 (다른 스타일 속성은 그대로 유지)
    requests.add(
      AddTextAttributionsRequest(
        documentRange: selection,
        attributions: {FontSizeAttribution(size)},
      ),
    );

    if (requests.isNotEmpty) {
      editor.execute(requests);
    }
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

  /// 텍스트 정렬 적용 (문서 전체 ParagraphNode에 적용)
  /// 정렬은 문서 레이아웃 설정이므로 전체에 일괄 적용 (Google Docs / Notion 스타일)
  void applyTextAlignment(TextAlign alignment) {
    applyGlobalTextAlignment(alignment);
  }

  /// 문서 전체 ParagraphNode에 정렬 적용 (전역 정렬)
  /// 정렬 버튼은 자주 누르지 않으므로 성능 문제 없음
  void applyGlobalTextAlignment(TextAlign alignment) {
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
