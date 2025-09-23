import 'dart:io';
import 'dart:typed_data';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/overlay/sticker_overlay.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/image/gallery_bottom_sheet.dart';
import 'package:doppy/editor/overlay/link_overlay.dart';
import 'package:doppy/editor/overlay/location_overlay.dart';

import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/overlay/mention_overlay.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/component/divider_component.dart';

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

            // 오른쪽 끝으로 밀기
          ],
        );

      case ToolbarSection.insert:
        return Row(
          children: [
            _buildChip(
              icon: Icons.horizontal_rule,
              label: '구분선',
              onTap: () {
                widget.stylingService.insertDivider();
                // 추가 후 상단 두번째 툴바 닫기
                _toggle(ToolbarSection.none);
              },
            ),

            _buildChip(
              icon: Icons.link,
              label: '링크',
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    opaque: false,
                    barrierDismissible: true,
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
              icon: Icons.copy_all,
              label: '스티커',
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    opaque: false,
                    barrierDismissible: true,
                    pageBuilder:
                        (_, __, ___) => StickerOverlay(
                          onSubmit: ({
                            required String text,
                            String? emoji,
                            Uint8List? image,
                            Map<String, dynamic>? textStyle,
                          }) {
                            final svc = context.read<StickerService>();
                            // 현재 화면 스크롤 위치를 고려한 초기 위치 (뷰포트 중앙 상단 근처)
                            final Size size = MediaQuery.of(context).size;
                            final scrollY =
                                widget.scrollController?.offset ?? 0.0;
                            final Offset at = Offset(
                              size.width * 0.5 - 60,
                              scrollY + 200,
                            );
                            if (image != null) {
                              svc.addImageSticker(image, at);
                            } else if ((emoji ?? '').isNotEmpty) {
                              svc.addEmojiSticker(emoji!, at);
                            } else if (text.trim().isNotEmpty) {
                              svc.addTextStickerWithStyle(
                                text.trim(),
                                textStyle,
                                at,
                              );
                            }
                            // 스티커 추가 후 상단 두번째 툴바 자동 닫기
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
              icon: Icons.location_on_outlined,
              label: '장소',
              onTap: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).push(
                  PageRouteBuilder(
                    opaque: false,
                    barrierDismissible: true,
                    pageBuilder:
                        (_, __, ___) => LocationOverlay(
                          onSelect: (lat, lng, title, address) {
                            widget.editorService.addLocationNode(
                              lat: lat,
                              lng: lng,
                              title: title,
                              address: address,
                              description: '선택된 위치입니다.',
                            );
                            // 장소 추가 후 상단 두번째 툴바 자동 닫기
                            _toggle(ToolbarSection.none);
                            Navigator.of(context).maybePop();
                          },
                        ),
                  ),
                );
              },
            ),
          ],
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

  const DefaultToolbar({
    super.key,
    required this.stylingService,
    required this.editorService,

    this.scrollController,
    this.isKeyboardVisible = false,
    this.onDismissKeyboard,
  });

  @override
  State<DefaultToolbar> createState() => _DefaultToolbarState();
}

enum ToolbarSection { none, camera, insert, text, align, mention }

enum TextPanel { none, size, color }

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
    if (_expanded == ToolbarSection.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateTopAnchor());
    }
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    print(
      'DEBUG: DefaultToolbar build - isKeyboardVisible: ${widget.isKeyboardVisible}',
    );
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color borderColor = onSurface.withOpacity(0.15);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 상단 확장 행 (선택된 섹션별 옵션)
        if (_expanded != ToolbarSection.none) ...[
          Container(
            height: 38,
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: surfaceVariant,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: _buildTopExpandedRowContent(),
          ),
        ],
        // 기본 툴바
        SizedBox(
          height: 38,
          width: width,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: surface),
            child: Row(
              children: [
                SizedBox(width: 10),
                // 카메라 섹션 (아이콘만, 옵션은 상단 행)
                _buildMainIcon(
                  icon: Icons.camera_alt_outlined,
                  isActive: false,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder:
                          (sheetContext) => GalleryBottomSheet(
                            onImagesSelected: (List<File> files) async {
                              print('DEBUG: 갤러리에서 선택된 파일 수: ${files.length}');
                              final upload = context.read<UploadService>();

                              final placeholderIds = <String>[];
                              for (final f in files) {
                                placeholderIds.add(
                                  widget.editorService.addImagePlaceholderNode(
                                    f.path,
                                  ),
                                );
                              }

                              final tasks = await upload
                                  .uploadFilesViaServerBatches(
                                    files,
                                    kind: UploadKind.editorImage,
                                  );

                              final count =
                                  tasks.length < placeholderIds.length
                                      ? tasks.length
                                      : placeholderIds.length;
                              for (int i = 0; i < count; i++) {
                                final t = tasks[i];
                                final id = placeholderIds[i];
                                if (t.state == UploadState.success &&
                                    (t.url ?? '').isNotEmpty) {
                                  await widget.editorService
                                      .replacePlaceholderWithUrl(id, t.url!);
                                } else {
                                  widget.editorService
                                      .deleteImagePlaceholderNode(id);
                                }
                              }
                            },
                          ),
                    );
                  },
                ),

                // 더 이상 하단에서 펼치지 않음
                const SizedBox(width: 10),
                _buildDivider(),
                const SizedBox(width: 10),

                // 텍스트 스타일 섹션 (아이콘만, 옵션은 상단 행)
                _buildMainIcon(
                  icon: Icons.text_format,
                  isActive: _expanded == ToolbarSection.text,
                  onTap: () => _toggle(ToolbarSection.text),
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
                  activeColor: onSurface,
                ),

                // 오른쪽 끝으로 밀어내기 위한 공간
                const Expanded(child: SizedBox()),

                // 키보드가 올라와 있을 때만 키보드 내리기 버튼 표시 (오른쪽 끝)
                if (widget.isKeyboardVisible) ...[
                  const SizedBox(width: 10),
                  _buildDivider(),
                  const SizedBox(width: 10),
                  _buildMainIcon(
                    icon: Icons.keyboard_arrow_down,
                    isActive: false,
                    onTap: () {
                      widget.onDismissKeyboard?.call();
                    },
                  ),
                ],
                if (!widget.isKeyboardVisible) ...[
                  const SizedBox(width: 10),
                  _buildDivider(),
                  const SizedBox(width: 10),
                  _buildMainIcon(
                    icon: Icons.keyboard_arrow_up,
                    isActive: false,
                    onTap: () {
                      FocusScope.of(context).requestFocus();
                    },
                  ),
                ],
                // 더 이상 하단에서 펼치지 않음
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color =
        isActive ? (activeColor ?? onSurface) : onSurface.withOpacity(0.6);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 50,
          alignment: Alignment.center,
          child: Icon(icon, size: 24, color: color),
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
            color: isActive ? onSurface : onSurface.withOpacity(0.6),
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
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
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

  // legacy helpers (not used in the new expandable UI)
  // kept here intentionally commented out for reference
  // Widget _buildColorButton(...) {}

  // Widget _buildAlignmentButton(...) {}

  // Widget _buildFontSizeButton(...) {}
}
