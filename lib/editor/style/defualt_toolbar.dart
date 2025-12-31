import 'dart:async';
import 'dart:typed_data';
import 'package:doppy/editor/overlay/sticker_overlay.dart';
import 'package:doppy/editor/overlay/font_overlay.dart';
import 'package:doppy/editor/style/media_upload_handler.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/overlay/link_overlay.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/overlay/mention_overlay.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:doppy/editor/style/text_attributions.dart';
import 'package:doppy/editor/style/text_styling_service.dart';

// TextStylingService는 lib/editor/style/text_styling_service.dart 로 분리됨
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
                _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
              },
              size: 24,
            ),

            const SizedBox(width: 6),
            _buildToggleIcon(
              icon: Icons.format_italic,
              isActive: _currentStyles['italic'] ?? false,
              onTap: () {
                widget.stylingService.toggleItalic();
                _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
              },
              size: 24,
            ),

            SizedBox(width: 6),
            _buildToggleIcon(
              icon: Icons.format_underlined,
              isActive: _currentStyles['underline'] ?? false,
              onTap: () {
                widget.stylingService.toggleUnderline();
                _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
              },
              size: 24,
            ),

            SizedBox(width: 6),
            _buildToggleIcon(
              icon: Icons.format_strikethrough,
              isActive: _currentStyles['strikethrough'] ?? false,
              onTap: () {
                widget.stylingService.toggleStrikethrough();
                _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
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
                        _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
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
                              // 노드가 추가되고 렌더링이 완료된 후 부드럽게 닫기
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                Future.delayed(
                                  const Duration(milliseconds: 150),
                                  () {
                                    if (context.mounted) {
                                      // 링크 추가 후 상단 두번째 툴바 자동 닫기
                                      // 🎯 LinkOverlay가 이미 Navigator.pop()을 호출하므로 여기서는 툴바만 닫기
                                      _toggle(ToolbarSection.none);
                                    }
                                  },
                                );
                              });
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
                              // 노드가 추가되고 렌더링이 완료된 후 부드럽게 닫기
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                Future.delayed(
                                  const Duration(milliseconds: 150),
                                  () {
                                    if (context.mounted) {
                                      // 언급 추가 후 상단 두번째 툴바 자동 닫기
                                      _toggle(ToolbarSection.none);
                                      Navigator.of(context).maybePop();
                                    }
                                  },
                                );
                              });
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
                widget.editorService.setCurrentParagraphAlignment(
                  TextAlign.left,
                );
                _updateStyles(
                  updateAlignment: true,
                ); // 🎯 정렬 버튼 클릭 시에만 alignment 업데이트
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
                widget.editorService.setCurrentParagraphAlignment(
                  TextAlign.center,
                );
                _updateStyles(
                  updateAlignment: true,
                ); // 🎯 정렬 버튼 클릭 시에만 alignment 업데이트
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
                widget.editorService.setCurrentParagraphAlignment(
                  TextAlign.right,
                );
                _updateStyles(
                  updateAlignment: true,
                ); // 🎯 정렬 버튼 클릭 시에만 alignment 업데이트
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
  final VoidCallback? onDismissKeyboard;
  final VoidCallback? onRequestFocus;
  final VoidCallback? onShowDraftList;
  final bool isEditMode;
  final ValueNotifier<bool>? videoUploadIndicatorNotifier; // 영상 업로드 인디케이터 상태
  final ValueNotifier<bool>? keyboardVisibleNotifier; // 🎯 키보드 상태 (외부에서 주입)

  const DefaultToolbar({
    super.key,
    required this.stylingService,
    required this.editorService,

    this.scrollController,
    this.onDismissKeyboard,
    this.onRequestFocus,
    this.onShowDraftList,
    this.isEditMode = false,
    this.videoUploadIndicatorNotifier,
    this.keyboardVisibleNotifier, // 🎯 키보드 상태 주입
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

  // 🎯 최적화: debounce 타이머
  Timer? _selectionDebounceTimer;
  Timer? _stylesDebounceTimer;

  // 🎯 최적화: 스타일 캐싱
  Map<String, bool>? _cachedStyles;
  TextAlign? _cachedAlignment;
  String? _lastSelectionHash; // 선택 상태 해시 (변경 감지용)

  // 🎯 최적화: 색상/폰트 크기 캐싱
  Color? _cachedTextColor;
  double? _cachedFontSize;
  List<Color>? _cachedTextColors;

  @override
  void initState() {
    super.initState();
    _updateStyles(updateAlignment: true); // 🎯 초기화 시에는 둘 다 업데이트

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
    _selectionDebounceTimer?.cancel();
    _stylesDebounceTimer?.cancel();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;

    // 🎯 Debounce: 50ms 후 실행 (드래그 중 과도한 호출 방지)
    _selectionDebounceTimer?.cancel();
    _selectionDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      _onSelectionChangedDebounced();
    });
  }

  void _onSelectionChangedDebounced() {
    final selection = widget.stylingService.composer.selection;
    final hasSelection = selection != null && !selection.isCollapsed;
    final isCollapsed = selection == null || selection.isCollapsed;

    // 🎯 선택 상태 해시 생성 (변경 감지용)
    String? selectionHash;
    if (selection != null) {
      try {
        selectionHash =
            '${selection.base.nodeId}_${selection.base.nodePosition}_${selection.extent.nodeId}_${selection.extent.nodePosition}';
      } catch (_) {
        selectionHash = hasSelection.toString();
      }
    } else {
      selectionHash = 'null';
    }

    // 🎯 선택 상태가 실제로 변경되지 않았으면 무시
    if (_lastSelectionHash == selectionHash) {
      return;
    }
    _lastSelectionHash = selectionHash;

    // 🎯 멘션 노드에서 선택이면 툴바 열지 않음
    bool isMentionNode = false;
    if (hasSelection) {
      try {
        final nodeId = selection.extent.nodeId;
        final node = widget.editorService.document.getNodeById(nodeId);
        // 🎯 NodeTypeChecker를 사용하여 멘션 노드 확인
        isMentionNode = NodeTypeChecker.isMentionNode(node);
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

    // 🎯 collapsed selection일 때는 스타일 재계산 스킵 (preferences 기반으로 충분)
    if (isCollapsed) {
      _stylesDebounceTimer?.cancel();
      // ✅ 커서만 있는 상태에서도 폰트사이즈/색상 UI는 preferences 기반으로 즉시 갱신돼야 한다.
      // (캐시만 비우고 setState로 리빌드 트리거)
      setState(() {
        _cachedTextColor = null;
        _cachedFontSize = null;
        _cachedTextColors = null;
      });
      return;
    }

    // 🎯 스타일 업데이트도 debounce (alignment는 업데이트 안 함 - 키보드 변화 시 불필요한 문서 순회 방지)
    _stylesDebounceTimer?.cancel();
    _stylesDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        _updateStyles(
          updateAlignment: false,
        ); // 🎯 selection 변경 시에는 styles만 업데이트
        // ✅ selection이 바뀌어도 bold/italic 등이 같으면 _updateStyles가 setState를 안 할 수 있음.
        // 폰트 사이즈/색상은 styles 맵에 포함되지 않으므로, 캐시를 setState로 비우며 리빌드를 보장한다.
        setState(() {
          _cachedTextColor = null;
          _cachedFontSize = null;
          _cachedTextColors = null;
        });
      }
    });
  }

  /// 🎯 스타일만 업데이트 (selection 변경 시 사용, alignment는 업데이트 안 함)
  void _updateStyles({bool updateAlignment = false}) {
    if (!mounted) return;

    final newStyles = widget.stylingService.getCurrentStyles();

    // 🎯 alignment는 정렬 버튼 클릭 시에만 업데이트 (키보드 변화 시 불필요한 문서 순회 방지)
    TextAlign? newAlignment;
    if (updateAlignment) {
      newAlignment = widget.stylingService.getCurrentAlignment();
      // ✅ EditorService도 "현재 정렬"을 인지하도록 동기화한다.
      // (삭제 후 정렬 보정 fallback에서 사용)
      widget.editorService.setCurrentParagraphAlignment(newAlignment);
    }

    // 🎯 캐시와 비교하여 실제 변경 여부 확인
    bool needsUpdate = false;

    // 정렬 변경 확인 (updateAlignment가 true일 때만)
    if (updateAlignment && newAlignment != null) {
      if (_cachedAlignment != newAlignment ||
          _currentAlignment != newAlignment) {
        needsUpdate = true;
      }
    }

    // 스타일 변경 확인 (캐시 우선 비교)
    if (_cachedStyles == null || _cachedStyles!.length != newStyles.length) {
      needsUpdate = true;
    } else {
      for (var key in newStyles.keys) {
        if (_cachedStyles![key] != newStyles[key] ||
            _currentStyles[key] != newStyles[key]) {
          needsUpdate = true;
          break;
        }
      }
    }

    if (needsUpdate) {
      // 🎯 캐시 업데이트
      _cachedStyles = Map<String, bool>.from(newStyles);
      if (updateAlignment && newAlignment != null) {
        _cachedAlignment = newAlignment;
      }

      setState(() {
        _currentStyles = newStyles;
        if (updateAlignment && newAlignment != null) {
          _currentAlignment = newAlignment;
        }
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
          height: 40,
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
          iconTopPadding: 2,
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

              // 🎯 바로 이미지 피커로 이동 (바텀시트 없이)
              await handler.handleImageUpload();
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
          iconTopPadding: 2,
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
          iconTopPadding: 2,
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
            widget.editorService.setCurrentParagraphAlignment(nextAlignment);
            _updateStyles(
              updateAlignment: true,
            ); // 🎯 정렬 버튼 클릭 시에만 alignment 업데이트
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
        // 🎯 키보드 상태를 외부에서 주입받아 MediaQuery 직접 읽기 방지
        _KeyboardDependentButtons(
          isEditMode: widget.isEditMode,
          onDismissKeyboard: widget.onDismissKeyboard,
          onShowDraftList: widget.onShowDraftList,
          keyboardVisibleNotifier: widget.keyboardVisibleNotifier,
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
            size: 26,
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
    double iconTopPadding = 0,
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder:
                (child, anim) => FadeTransition(opacity: anim, child: child),
            child: Padding(
              key: ValueKey(icon.codePoint),
              padding: EdgeInsets.only(top: iconTopPadding),
              child: Icon(
                icon,
                size: size ?? (isActive ? 28 : 25),
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainSvgIcon({
    required String svgPath,
    required bool isActive,
    required VoidCallback onTap,
    double? size,
    double iconTopPadding = 0,
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder:
                (child, anim) => FadeTransition(opacity: anim, child: child),
            child: Padding(
              key: ValueKey(svgPath),
              padding: EdgeInsets.only(top: iconTopPadding),
              child: SvgPicture.asset(
                svgPath,
                width: size ?? (isActive ? 28 : 25),
                height: size ?? (isActive ? 28 : 25),
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
            ),
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
            // 🎯 폰트 사이즈 변경 후 캐시 무효화하여 UI 즉시 업데이트
            _cachedFontSize = null;
          });
          _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
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

  /// 현재 적용 중인 텍스트 색상 가져오기 (캐싱)
  Color _getCurrentTextColor() {
    // 🎯 캐시가 있으면 반환
    if (_cachedTextColor != null) {
      return _cachedTextColor!;
    }

    final selection = widget.stylingService.composer.selection;
    Color? color;

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
            color = attribution.color;
            break;
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
          color = attr.color;
          break;
        }
      }
    }

    // 기본 색상 (테마의 onSurface)
    _cachedTextColor = color ?? Theme.of(context).colorScheme.onSurface;
    return _cachedTextColor!;
  }

  /// 선택 영역에 여러 색상이 섞여 있는지 확인 (단일 노드 내 선택만 체크, 캐싱)
  List<Color> _getTextColorsInSelection() {
    // 🎯 캐시가 있으면 반환
    if (_cachedTextColors != null) {
      return _cachedTextColors!;
    }

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
          for (final i in _sampleOffsets(startOffset, endOffset)) {
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

              for (final j in _sampleOffsets(startOffset, endOffset)) {
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

    _cachedTextColors = colors.toList();
    return _cachedTextColors!;
  }

  // 🎯 텍스트 속성 계산 시 전체 범위 순회 대신 대표 offset만 샘플링
  List<int> _sampleOffsets(int start, int end) {
    if (end <= start) return const [];
    final mid = (start + end) >> 1;
    final last = end - 1;
    final candidates = <int>{start, mid, last};
    candidates.removeWhere((o) => o < start || o >= end);
    return candidates.toList();
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
            _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
          }),
        ],

        const SizedBox(width: 16),
      ],
    );
  }

  // 현재 폰트 사이즈 가져오기 (캐싱)
  double _getCurrentFontSize() {
    // 🎯 캐시가 있으면 반환
    if (_cachedFontSize != null) {
      return _cachedFontSize!;
    }

    final selection = widget.stylingService.composer.selection;
    double? fontSize;

    // 선택이 없거나 커서만 있을 때: preferences에서 조회
    if (selection == null || selection.isCollapsed) {
      final current =
          widget.stylingService.composer.preferences.currentAttributions;
      for (final attr in current) {
        if (attr is FontSizeAttribution) {
          fontSize = attr.fontSize;
          break;
        }
      }
    } else {
      final node = widget.stylingService.editor.document.getNodeById(
        selection.base.nodeId,
      );
      if (node is TextNode) {
        final position = selection.base.nodePosition as TextNodePosition;
        final attributions = node.text.getAllAttributionsAt(position.offset);

        for (final attribution in attributions) {
          if (attribution is FontSizeAttribution) {
            fontSize = attribution.fontSize;
            break;
          }
        }
      }
    }

    _cachedFontSize = fontSize ?? EditorConfig.defaultBodyFontSize;
    return _cachedFontSize!;
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
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return SizedBox(
          height: 200,
          child: Container(
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
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ...highlightColors.map((color) {
                      return GestureDetector(
                        onTap: () {
                          // 🔧 선택 스냅샷 범위에서 기존 형광펜 제거 후 새 색상 적용
                          widget.stylingService.removeHighlight(
                            selectionOverride: selectionSnapshot,
                          );
                          widget.stylingService.applyHighlight(
                            color,
                            selectionOverride: selectionSnapshot,
                          );
                          _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
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
                        widget.stylingService.removeHighlight(
                          selectionOverride: selectionSnapshot,
                        );
                        _updateStyles(updateAlignment: false); // 🎯 스타일만 업데이트
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
                            size: 26,
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
      },
    );
  }
}

/// 키보드 상태에 따라서만 변경되는 버튼들을 별도 위젯으로 분리
/// 이렇게 하면 키보드 상태 변경 시 이 위젯만 리빌드됨
/// 🎯 키보드 상태를 외부에서 주입받아 MediaQuery 직접 읽기 방지 (캐싱된 위젯에서도 동작)
class _KeyboardDependentButtons extends StatelessWidget {
  final bool isEditMode;
  final VoidCallback? onDismissKeyboard;
  final VoidCallback? onShowDraftList;
  final ValueNotifier<bool>? keyboardVisibleNotifier; // 🎯 키보드 상태 (외부에서 주입)

  const _KeyboardDependentButtons({
    required this.isEditMode,
    this.onDismissKeyboard,
    this.onShowDraftList,
    this.keyboardVisibleNotifier, // 🎯 키보드 상태 주입
  });

  @override
  Widget build(BuildContext context) {
    // 🎯 키보드 상태를 ValueNotifier로 받아서 캐싱된 위젯에서도 동작
    if (keyboardVisibleNotifier != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: keyboardVisibleNotifier!,
        builder: (context, isKeyboardVisible, _) {
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
        },
      );
    }

    // 🎯 fallback: keyboardVisibleNotifier가 없으면 MediaQuery 사용 (레거시 지원)
    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
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
