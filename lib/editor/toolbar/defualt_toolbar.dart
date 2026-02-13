import 'dart:async';
import 'package:flutter/material.dart';
import '../data/font.dart';
import 'package:super_editor/super_editor.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/font_selection_widget.dart';
import '../style/media_upload_handler.dart';
import '../widgets/link_addition_widget.dart';
import '../service/editor_service.dart';
import '../style/text_styling_service.dart';
import '../utils/editor_localization.dart';
import 'toolbar_types.dart';
import 'toolbar_constants.dart';
import 'toolbar_components.dart';
import 'toolbar_utils.dart';
import '../utils/list_paragraph_meta.dart';

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
            ToolbarToggleIcon(
              icon: Icons.format_bold,
              isActive: _currentStyles['bold'] ?? false,
              onTap: () {
                widget.stylingService.toggleBold();
                _updateStyles(updateAlignment: false);
              },
              size: 24,
            ),

            const SizedBox(width: 6),
            ToolbarToggleIcon(
              icon: Icons.format_italic,
              isActive: _currentStyles['italic'] ?? false,
              onTap: () {
                widget.stylingService.toggleItalic();
                _updateStyles(updateAlignment: false);
              },
              size: 24,
            ),

            const SizedBox(width: 6),
            ToolbarToggleIcon(
              icon: Icons.format_underlined,
              isActive: _currentStyles['underline'] ?? false,
              onTap: () {
                widget.stylingService.toggleUnderline();
                _updateStyles(updateAlignment: false);
              },
              size: 24,
            ),

            const SizedBox(width: 6),
            ToolbarToggleIcon(
              icon: Icons.format_strikethrough,
              isActive: _currentStyles['strikethrough'] ?? false,
              onTap: () {
                widget.stylingService.toggleStrikethrough();
                _updateStyles(updateAlignment: false);
              },
              size: 24,
            ),
            SizedBox(width: 6),
            // 형광펜 토글 버튼 (실제 형광펜 색상 표시)
            _buildHighlighterToggleIcon(
              isActive: _currentStyles['highlight'] ?? false,
              onTap: () {
                _showHighlightColorPalette();
              },
            ),
            SizedBox(width: 6),

            // 스포일러(가림) 토글 버튼 (선택 영역 필수)
            ToolbarToggleIcon(
              svgPath: 'assets/icons/spoiler.svg',
              isActive: _currentStyles['spoiler'] ?? false,
              onTap: _hasTextSelection
                  ? () {
                      widget.stylingService.toggleSpoiler();
                      _updateStyles(updateAlignment: false);
                    }
                  : null,
              size: 28,
            ),

            // 오른쪽 끝으로 밀기
          ],
        );

      case ToolbarSection.insert:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // 리스트: 번호 / 불릿 / 체크리스트
              ToolbarChip(
                svgPath: 'assets/icons/numbered.svg',
                label: context.tr('editor_list_numbered'),
                size: 24,
                onTap: () {
                  widget.editorService.insertEmptyListParagraphAfterCaret(
                    ListParagraphMeta.typeNumbered,
                  );
                  _updateStyles(updateAlignment: false);
                  _toggle(ToolbarSection.none);
                },
              ),
              ToolbarChip(
                svgPath: 'assets/icons/bullet.svg',
                label: context.tr('editor_list_bullet'),
                size: 22,
                onTap: () {
                  widget.editorService.insertEmptyListParagraphAfterCaret(
                    ListParagraphMeta.typeBullet,
                  );
                  _updateStyles(updateAlignment: false);
                  _toggle(ToolbarSection.none);
                },
              ),
              ToolbarChip(
                svgPath: 'assets/icons/checklist.svg',
                label: context.tr('editor_list_checklist'),
                size: 28,
                onTap: () {
                  widget.editorService.insertEmptyListParagraphAfterCaret(
                    ListParagraphMeta.typeChecklist,
                  );
                  _updateStyles(updateAlignment: false);
                  _toggle(ToolbarSection.none);
                },
              ),
              ToolbarChip(
                svgPath: 'assets/icons/quote.svg',
                label: context.tr('editor_list_quote'),
                size: 23,
                onTap: () {
                  widget.editorService.insertEmptyListParagraphAfterCaret(
                    ListParagraphMeta.typeQuote,
                  );
                  _updateStyles(updateAlignment: false);
                  _toggle(ToolbarSection.none);
                },
              ),

              ToolbarChip(
                svgPath: 'assets/icons/link.svg',
                label: context.tr('editor_link'),
                size: 26,
                onTap: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: true,
                      barrierDismissible: true,
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (_, __, ___) => LinkOverlay(
                        autoSubmit: true,
                        onSubmit:
                            ({
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

              ToolbarChip(
                icon: Icons.horizontal_rule,
                label: context.tr('editor_divider'),
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
            ToolbarToggleIcon(
              icon: Icons.format_align_left,
              isActive: _currentAlignment == TextAlign.left,
              onTap: () {
                final offset = widget.scrollController?.offset;
                widget.stylingService.applyTextAlignment(TextAlign.left);
                widget.editorService.setCurrentParagraphAlignment(
                  TextAlign.left,
                );
                _updateStyles(updateAlignment: true);
                if (offset != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.scrollController?.jumpTo(offset);
                  });
                }
              },
            ),
            const SizedBox(width: 6),
            ToolbarToggleIcon(
              icon: Icons.format_align_center,
              isActive: _currentAlignment == TextAlign.center,
              onTap: () {
                final offset = widget.scrollController?.offset;
                widget.stylingService.applyTextAlignment(TextAlign.center);
                widget.editorService.setCurrentParagraphAlignment(
                  TextAlign.center,
                );
                _updateStyles(updateAlignment: true);
                if (offset != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.scrollController?.jumpTo(offset);
                  });
                }
              },
            ),
            const SizedBox(width: 6),
            ToolbarToggleIcon(
              icon: Icons.format_align_right,
              isActive: _currentAlignment == TextAlign.right,
              onTap: () {
                final offset = widget.scrollController?.offset;
                widget.stylingService.applyTextAlignment(TextAlign.right);
                widget.editorService.setCurrentParagraphAlignment(
                  TextAlign.right,
                );
                _updateStyles(updateAlignment: true);
                if (offset != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.scrollController?.jumpTo(offset);
                  });
                }
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
  // ✅ 미디어 추가 시 빈 상태 오버레이를 숨기기 위한 콜백
  final VoidCallback? onMediaAdded;
  final int? initialYear; // 초기 연도
  final int? initialYearOfWeek; // 초기 주차 (1-53)
  final Function(int year, int yearOfWeek)? onDateChanged; // 날짜 변경 콜백

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
    this.onMediaAdded,
    this.initialYear,
    this.initialYearOfWeek,
    this.onDateChanged,
  });

  @override
  State<DefaultToolbar> createState() => _DefaultToolbarState();
}

class _DefaultToolbarState extends State<DefaultToolbar> {
  Map<String, bool> _currentStyles = {
    'bold': false,
    'italic': false,
    'underline': false,
    'strikethrough': false,
  };

  TextAlign _currentAlignment = TextAlign.left;
  String? _currentListType; // 'numbered' | 'bullet' | 'checklist' | null
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
  String? _cachedListType;
  String? _lastSelectionHash; // 선택 상태 해시 (변경 감지용)

  // 🎯 최적화: 색상/폰트 크기 캐싱
  Color? _cachedTextColor;
  double? _cachedFontSize;
  List<Color>? _cachedTextColors;

  /// 범위 선택 → collapsed 전환 시 툴바 폰트 크기를 preferences에 반영하기 위한 플래그
  bool _hadRangeSelectionBefore = false;

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

    // 🎯 범위 선택 시 툴바에 보이는 폰트 크기 저장; collapsed 전환 시 preferences에 반영해 새 입력이 툴바와 동기화
    if (hasSelection) {
      widget.stylingService.captureFontSizeFromSelection();
      _hadRangeSelectionBefore = true;
    } else if (isCollapsed && _hadRangeSelectionBefore) {
      widget.stylingService.applyLastSelectionFontSizeWhenCollapsed();
      _hadRangeSelectionBefore = false;
    } else {
      _hadRangeSelectionBefore = false;
    }

    if (_hasTextSelection != hasSelection) {
      setState(() {
        _hasTextSelection = hasSelection;
        if (hasSelection) {
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
  void _updateStyles({
    bool updateAlignment = false,
    bool updateListType = true,
  }) {
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

    // 🎯 리스트 타입: 현재 포커스 문단 기준
    String? newListType;
    if (updateListType) {
      newListType = widget.editorService.currentParagraphListType;
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

    // 리스트 타입 변경 확인
    if (updateListType &&
        (_cachedListType != newListType || _currentListType != newListType)) {
      needsUpdate = true;
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
      if (updateListType) {
        _cachedListType = newListType;
      }

      setState(() {
        _currentStyles = newStyles;
        if (updateAlignment && newAlignment != null) {
          _currentAlignment = newAlignment;
        }
        if (updateListType) {
          _currentListType = newListType;
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
      builder: (ctx) => DraggableScrollableSheet(
        controller: sheetController, // 컨트롤러 연결
        initialChildSize: 0.6, // 처음엔 반만
        minChildSize: 0.5,
        maxChildSize: 0.9, // 위로 드래그하면 거의 전체까지
        builder: (_, scrollController) => FontOverlay(
          scrollController:
              scrollController, // DraggableScrollableSheet의 컨트롤러 전달
          sheetController: sheetController, // 시트 컨트롤러 전달
          onSelect: (FontItem fontItem) {
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
          initialCurrentFamily: _getCurrentFontName(),
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color background = Theme.of(context).colorScheme.surface;

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
          child: _expanded != ToolbarSection.none
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
        ToolbarMainIcon(
          svgPath: 'assets/icons/gallery.svg',
          size: 27,
          isActive: false,
          iconTopPadding: 2,
          height: 40,
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
                onMediaAdded: widget.onMediaAdded,
              );

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
        const ToolbarDivider(),
        const SizedBox(width: 10),

        // 텍스트 스타일 섹션 (아이콘만, 옵션은 상단 행)
        ToolbarMainIcon(
          svgPath: 'assets/icons/text.svg',
          isActive: _expanded == ToolbarSection.text,
          iconTopPadding: 2,
          height: 40,
          onTap: () => _toggle(ToolbarSection.text),
          size: 24,
        ),
        // 더 이상 하단에서 펼치지 않음
        const SizedBox(width: 10),
        const ToolbarDivider(),
        const SizedBox(width: 10),

        // 정렬 섹션 (아이콘만, 옵션은 상단 행)
        ToolbarMainIcon(
          icon: getAlignmentIcon(_currentAlignment),
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
        const ToolbarDivider(),
        const SizedBox(width: 10),

        // 언급/태그 섹션 (아이콘만, 옵션은 상단 행)
        // (언급은 + 메뉴로 이동)

        // 추가(플러스) 섹션 - 상단 행에서 옵션 표시
        ToolbarMainIcon(
          icon: Icons.add,
          isActive: _expanded == ToolbarSection.insert,
          onTap: () => _toggle(ToolbarSection.insert),
          activeColor: Theme.of(context).colorScheme.onSurface,
          size: 32,
        ),

        // 오른쪽 끝으로 밀어내기 위한 공간
        const Expanded(child: SizedBox()),

        // 달력 아이콘 (initialYear와 initialYearOfWeek가 있을 때만 표시, 키보드가 내려와 있을 때만 표시)
        if (widget.initialYear != null && widget.initialYearOfWeek != null)
          _CalendarIcon(
            keyboardVisibleNotifier: widget.keyboardVisibleNotifier,
            onTap: () => _showDatePickerBottomSheet(),
          ),

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

  void _showDatePickerBottomSheet() {
    // 키보드 내리기
    FocusManager.instance.primaryFocus?.unfocus();

    // TODO: WeekUtils와 DatePickerScreen import 필요
    // 현재는 기능이 비활성화됨
    debugPrint('[Toolbar] Date picker 기능은 아직 구현되지 않았습니다.');
  }

  Widget _buildExpandedToolbar() {
    return Row(
      children: [
        // 폰트 크기/색상 패널이 펼쳐졌을 때는 닫기 버튼 숨김
        if (_textPanel == TextPanel.none) ...[
          const SizedBox(width: 4),
          // 닫기 버튼 (왼쪽 끝)
          ToolbarMainIcon(
            icon: Icons.close,
            isActive: false,
            onTap: _forceCloseToolbar,
            size: 26,
          ),
          const SizedBox(width: 2),
          const ToolbarDivider(),
          const SizedBox(width: 4),
        ],
        // 확장된 내용
        Expanded(child: _buildTopExpandedRowContent()),
      ],
    );
  }

  /// 현재 적용 중인 폰트명 가져오기
  String _getCurrentFontName() {
    return getCurrentFontName(context, widget.stylingService);
  }

  /// 폰트명 표시 버튼
  Widget _buildFontNameButton() {
    final String fontName = _getCurrentFontName();
    final String displayName = fontName.length > 8
        ? '${fontName.substring(0, 8)}'
        : fontName;

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

  // (unused) 정렬 토글 버튼 - 상단 확장 행으로 이동됨

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
        ...ToolbarFontSizes.sizes.map(
          (size) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildFontSizeButton('${size.toInt()}', size),
          ),
        ),
        const SizedBox(width: 8),
        const ToolbarDivider(),
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
    final isActive = currentSize != null && currentSize == size;

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
    final currentSize = _getCurrentFontSize();
    final label = currentSize == null
        ? context.tr('editor_font_size_mixed')
        : '${currentSize.toInt()}';
    return Material(
      color: _textPanel == TextPanel.size ? surfaceVariant : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() {
            _textPanel = _textPanel == TextPanel.size
                ? TextPanel.none
                : TextPanel.size;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 10, right: 10, bottom: 1),
          child: Row(
            children: [
              Text(
                label,
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
      color: _textPanel == TextPanel.color
          ? surfaceVariant
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() {
            _textPanel = _textPanel == TextPanel.color
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
                'assets/icons/text.svg',
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
                              colors: colors.length > 1
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

    _cachedTextColor = getCurrentTextColor(context, widget.stylingService);
    return _cachedTextColor!;
  }

  /// 선택 영역에 여러 색상이 섞여 있는지 확인 (단일 노드 내 선택만 체크, 캐싱)
  List<Color> _getTextColorsInSelection() {
    // 🎯 캐시가 있으면 반환
    if (_cachedTextColors != null) {
      return _cachedTextColors!;
    }

    _cachedTextColors = getTextColorsInSelection(widget.stylingService);
    return _cachedTextColors!;
  }

  /// 현재 형광펜 색상 가져오기
  Color? _getCurrentHighlightColor() {
    return getCurrentHighlightColor(widget.stylingService);
  }

  // 펼쳐진 색상 팔레트 행
  Widget _buildColorPaletteRow() {
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
        for (final c in ToolbarColorPalette.textColors) ...[
          ToolbarColorDot(
            color: c,
            onTap: () {
              widget.stylingService.applyTextColor(c);
              setState(() {
                _textPanel = TextPanel.none;
              });
              _updateStyles(updateAlignment: false);
            },
          ),
        ],

        const SizedBox(width: 16),
      ],
    );
  }

  // 현재 폰트 사이즈 가져오기 (캐싱). 선택 영역에 서로 다른 크기가 섞여 있으면 null(mixed)
  double? _getCurrentFontSize() {
    if (_cachedFontSize != null) return _cachedFontSize;
    final result = getCurrentFontSize(widget.stylingService);
    if (result != null) _cachedFontSize = result;
    return result;
  }

  // 형광펜 색상 팔레트 표시
  void _showHighlightColorPalette() {
    // 선택 스냅샷 저장: 모달이 떠도 동일 범위에 적용하기 위함
    final selectionSnapshot = widget.stylingService.composer.selection;

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
                    ...ToolbarColorPalette.highlightColors.map((color) {
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
                        _updateStyles(updateAlignment: false);
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

/// 달력 아이콘 (키보드 상태에 따라 표시/숨김)
class _CalendarIcon extends StatelessWidget {
  final ValueNotifier<bool>? keyboardVisibleNotifier;
  final VoidCallback onTap;

  const _CalendarIcon({
    required this.keyboardVisibleNotifier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 키보드 상태에 따라 달력 아이콘 표시/숨김
    if (keyboardVisibleNotifier != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: keyboardVisibleNotifier!,
        builder: (context, isKeyboardVisible, _) {
          if (isKeyboardVisible) {
            return const SizedBox.shrink();
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 10),
              ToolbarMainIcon(
                svgPath: 'assets/icons/calendar.svg',
                size: 24,
                isActive: false,
                iconTopPadding: 2,
                height: 40,
                onTap: onTap,
              ),
              const SizedBox(width: 10),
            ],
          );
        },
      );
    }

    // fallback: keyboardVisibleNotifier가 없으면 MediaQuery 사용
    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (isKeyboardVisible) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 10),
        ToolbarMainIcon(
          svgPath: 'assets/icons/calendar.svg',
          size: 24,
          isActive: false,
          iconTopPadding: 2,
          height: 40,
          onTap: onTap,
        ),
        const SizedBox(width: 10),
      ],
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
                  child: ToolbarMainIcon(
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
            child: ToolbarMainIcon(
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
}
