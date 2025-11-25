import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:doppy/editor/style/font_catalog.dart';
import 'package:doppy/editor/service/font_preload_service.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontPrefsService {
  static const String _keyCurrentFamily = 'editor.current_font_family';
  static const String _keyCurrentWeight = 'editor.current_font_weight';
  static const String _keyFavorites = 'editor.favorite_fonts';

  Future<void> saveCurrentFont(String? family, int weight) async {
    final prefs = await SharedPreferences.getInstance();
    if (family == null || family.isEmpty) {
      await prefs.remove(_keyCurrentFamily);
    } else {
      await prefs.setString(_keyCurrentFamily, family);
    }
    await prefs.setInt(_keyCurrentWeight, weight);
  }

  Future<(String?, int?)> loadCurrentFont() async {
    final prefs = await SharedPreferences.getInstance();
    final family = prefs.getString(_keyCurrentFamily);
    final weight = prefs.getInt(_keyCurrentWeight);
    return (family, weight);
  }

  Future<List<String>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyFavorites) ?? const [];
  }

  Future<void> toggleFavorite(String family) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyFavorites) ?? <String>[];
    if (list.contains(family)) {
      list.removeWhere((e) => e == family);
    } else {
      list.add(family);
    }
    await prefs.setStringList(_keyFavorites, list);
  }

  Future<bool> isFavorite(String family) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyFavorites) ?? const [];
    return list.contains(family);
  }
}

/// 폰트 선택 오버레이 (mention_overlay와 유사한 구조)
class FontOverlay extends StatefulWidget {
  final void Function(FontItem fontItem) onSelect;
  final VoidCallback? onClose;
  final ScrollController? scrollController; // DraggableScrollableSheet용
  final DraggableScrollableController? sheetController; // 시트 확장/축소용 컨트롤러
  final String? initialCurrentFamily; // 현재 적용 폰트(식별자)

  const FontOverlay({
    super.key,
    required this.onSelect,
    this.onClose,
    this.scrollController,
    this.sheetController,
    this.initialCurrentFamily,
  });

  @override
  State<FontOverlay> createState() => _FontOverlayState();
}

class _FontOverlayState extends State<FontOverlay> {
  final FontPrefsService _prefs = FontPrefsService();
  Set<String> _favorites = <String>{};
  (String?, int?) _current = (null, null);
  final TextEditingController _searchCtrl = TextEditingController(text: '');
  String _query = '';
  String _selectedCategory = '전체'; // 전체, 손글씨, 산세리프, 세리프, 디스플레이, 모노스페이스
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // 🎯 로케일에 따라 초기 카테고리 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final localeProvider = Provider.of<LocaleProvider>(
        context,
        listen: false,
      );
      if (localeProvider.isEnglish && _selectedCategory == '전체') {
        setState(() {
          _selectedCategory = 'All';
        });
      }
    });
  }

  Future<void> _loadPrefs() async {
    final fav = await _prefs.loadFavorites();
    final cur = await _prefs.loadCurrentFont();
    if (!mounted) return;
    setState(() {
      _favorites = fav.toSet();
      // 우선순위: 외부에서 전달된 현재 폰트 → 저장된 최근 폰트
      if ((widget.initialCurrentFamily ?? '').isNotEmpty) {
        _current = (widget.initialCurrentFamily, cur.$2);
      } else {
        _current = cur;
      }
    });
  }

  Future<void> _toggleFavorite(String? family) async {
    if (family == null || family.isEmpty) return;
    await _prefs.toggleFavorite(family);
    final fav = await _prefs.loadFavorites();
    if (!mounted) return;
    setState(() => _favorites = fav.toSet());
  }

  bool _isFavorite(String? family) =>
      family != null && family.isNotEmpty && _favorites.contains(family);

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _expandSheet() {
    // DraggableScrollableController를 사용해서 시트 확장
    if (widget.sheetController != null) {
      widget.sheetController!.animateTo(
        0.9, // maxChildSize로 확장
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final onSurface = theme.onSurface;
    final surface = theme.surface;
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isEnglish = localeProvider.isEnglish;

    // 전체 폰트 리스트
    List<FontItem> allFonts = FontCatalog.all;

    // 🎯 영어 모드일 때 한글 지원 폰트 제외
    if (isEnglish) {
      allFonts = allFonts.where((f) => !f.supportsKorean).toList();
    }

    // 카테고리 필터링
    if (_selectedCategory != (isEnglish ? 'All' : '전체')) {
      allFonts =
          allFonts.where((f) => f.category == _selectedCategory).toList();
    }

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          // 드래그 핸들 (탭하면 시트가 위로 올라감)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (details) {
              // 위로 스와이프하면 시트 최대 확장
              if (details.velocity.pixelsPerSecond.dy < -300) {
                _expandSheet();
              }
            },
            onTap: _expandSheet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: onSurface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),

          // 상단 바 (검색 + 닫기)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: Row(
              children: [
                // 검색창
                Expanded(
                  child: TextField(
                    cursorColor: onSurface,
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(color: onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      hintText:
                          Provider.of<LocaleProvider>(
                                context,
                                listen: false,
                              ).isEnglish
                              ? 'Search fonts'
                              : '폰트 검색',
                      hintStyle: TextStyle(
                        color: onSurface.withOpacity(0.5),
                        fontSize: 14,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      filled: true,
                      fillColor: onSurface.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    color: onSurface.withOpacity(0.5),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // 중앙 리스트 영역
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double maxWidth =
                    constraints.maxWidth > 520 ? 520 : constraints.maxWidth;
                // 검색 및 정렬: 현재 사용 → 즐겨찾기 → 그 외
                final String q = _query.trim().toLowerCase();
                bool matches(FontItem f) {
                  final dn = f.displayName.toLowerCase();
                  final cat = f.category.toLowerCase();
                  return q.isEmpty || dn.contains(q) || cat.contains(q);
                }

                final filtered = allFonts.where(matches).toList();
                final String? curIdentifier = _current.$1;

                // 현재 폰트 찾기
                FontItem? currentChoice;
                if (curIdentifier == null || curIdentifier.isEmpty) {
                  // 🎯 영어 모드일 때는 기본 시스템 폰트 찾기 (localFontFamily == null && supportsKorean == false)
                  if (isEnglish) {
                    currentChoice = filtered.firstWhere(
                      (f) => f.localFontFamily == null && !f.supportsKorean,
                      orElse:
                          () =>
                              filtered.isNotEmpty
                                  ? filtered.firstWhere(
                                    (f) => !f.supportsKorean,
                                    orElse: () => filtered.first,
                                  )
                                  : FontCatalog.all.firstWhere(
                                    (f) => !f.supportsKorean,
                                    orElse: () => FontCatalog.all.first,
                                  ),
                    );
                  } else {
                    currentChoice = filtered.firstWhere(
                      (f) => f.identifier == '기본 산세리프',
                      orElse:
                          () =>
                              filtered.isNotEmpty
                                  ? filtered.first
                                  : FontCatalog.all.first,
                    );
                  }
                } else {
                  currentChoice = filtered.firstWhere(
                    (f) => f.identifier == curIdentifier,
                    orElse:
                        () =>
                            filtered.isNotEmpty
                                ? filtered.first
                                : FontCatalog.all.first,
                  );
                }

                // 즐겨찾기와 기타로 분류 (손글씨, 산세리프 우선)
                final favorites =
                    filtered
                        .where(
                          (f) =>
                              _isFavorite(f.identifier) &&
                              f.identifier != currentChoice?.identifier,
                        )
                        .toList();

                // 기타 폰트를 카테고리별로 분류
                final others =
                    filtered
                        .where(
                          (f) =>
                              !_isFavorite(f.identifier) &&
                              f.identifier != currentChoice?.identifier,
                        )
                        .toList();

                // 손글씨 우선
                final handwriting =
                    others.where((f) => f.category == '손글씨').toList();
                // 산세리프 (반듯한 서체) 우선
                final sansSerif =
                    others.where((f) => f.category == '산세리프').toList();
                // 나머지
                final rest =
                    others
                        .where(
                          (f) => f.category != '손글씨' && f.category != '산세리프',
                        )
                        .toList();

                final ordered = <FontItem>[
                  currentChoice,
                  ...favorites,
                  ...handwriting,
                  ...sansSerif,
                  ...rest,
                ];

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: RawScrollbar(
                      controller: widget.scrollController ?? _scrollController,
                      thumbVisibility: true,
                      thickness: 6,
                      radius: const Radius.circular(10),
                      thumbColor: onSurface.withOpacity(0.3),
                      trackColor: onSurface.withOpacity(0.05),
                      child: ListView.separated(
                        controller:
                            widget.scrollController ?? _scrollController,
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                        itemCount: ordered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final f = ordered[i];
                          final bool isCurrent =
                              f.identifier == (currentChoice?.identifier ?? '');

                          return _GlassTile(
                            onTap: () async {
                              // 🎯 폰트 선택 시 해당 폰트만 빠르게 로드
                              final preloadService = FontPreloadService();
                              if (f.googleFont != null &&
                                  !preloadService.isPreloaded(f.identifier)) {
                                // 폰트 로드를 백그라운드에서 시작 (await 하지 않음)
                                preloadService.preloadFont(f).catchError((e) {
                                  debugPrint(
                                    '[FontOverlay] 폰트 로드 실패: ${f.displayName} - $e',
                                  );
                                });
                              }

                              // 에디터에 즉시 적용
                              widget.onSelect(f);
                              // 현재 폰트 저장 (다음 오픈 시 "현재 사용 중"으로 인식)
                              await _prefs.saveCurrentFont(
                                f.identifier,
                                FontWeight.w400.index,
                              );
                              Navigator.of(context).pop();
                            },
                            highlighted: isCurrent,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 5,
                                right: 10,
                                top: 8,
                                bottom: 8,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,

                                children: [
                                  // 현재 사용 중이면 ! 아이콘
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              f.displayName,
                                              style: TextStyle(
                                                color:
                                                    isCurrent
                                                        ? onSurface
                                                        : onSurface.withOpacity(
                                                          0.5,
                                                        ),
                                                fontSize: isCurrent ? 15 : 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                        ),

                                        _FontPreviewText(
                                          fontItem: f,
                                          isCurrent: isCurrent,
                                          onSurface: onSurface,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 즐겨찾기 토글
                                  GestureDetector(
                                    child: Center(
                                      child: Icon(
                                        size: 20,
                                        _isFavorite(f.identifier)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color:
                                            _isFavorite(f.identifier)
                                                ? Colors.redAccent
                                                : onSurface.withOpacity(0.2),
                                      ),
                                    ),
                                    onTap: () => _toggleFavorite(f.identifier),
                                  ),
                                ],
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
          ),
        ],
      ),
    );
  }
}

/// 폰트 미리보기 텍스트 (폰트 로딩 안정화)
class _FontPreviewText extends StatefulWidget {
  final FontItem fontItem;
  final bool isCurrent;
  final Color onSurface;

  const _FontPreviewText({
    required this.fontItem,
    required this.isCurrent,
    required this.onSurface,
  });

  @override
  State<_FontPreviewText> createState() => _FontPreviewTextState();
}

class _FontPreviewTextState extends State<_FontPreviewText> {
  TextStyle? _cachedStyle;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  @override
  void didUpdateWidget(_FontPreviewText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontItem != widget.fontItem ||
        oldWidget.isCurrent != widget.isCurrent) {
      _cachedStyle = null;
      _isLoading = true;
      _loadFont();
    }
  }

  Future<void> _loadFont() async {
    if (widget.fontItem.googleFont != null) {
      try {
        final preloadService = FontPreloadService();

        // 이미 프리로드된 폰트인지 확인
        final isPreloaded = preloadService.isPreloaded(
          widget.fontItem.identifier,
        );

        if (isPreloaded) {
          // 이미 로드된 폰트는 즉시 적용 (깜빡임 없음)
          if (mounted) {
            setState(() {
              _cachedStyle = widget.fontItem.getTextStyle(
                fontWeight:
                    widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
                fontSize: widget.isCurrent ? 18 : 14,
                color:
                    widget.isCurrent
                        ? widget.onSurface
                        : widget.onSurface.withOpacity(0.5),
              );
              _isLoading = false;
            });
          }
          return;
        }

        // 아직 로드되지 않은 폰트는 로드 시도
        // 구글 폰트를 미리 로드하여 캐시
        final style = widget.fontItem.googleFont!(
          fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
          fontSize: widget.isCurrent ? 18 : 14,
        );

        // 폰트가 실제로 로드될 때까지 짧게 대기 (프리로드되어 있으면 빠름)
        await Future.delayed(Duration(milliseconds: isPreloaded ? 10 : 50));

        if (mounted) {
          setState(() {
            _cachedStyle = style.copyWith(
              color:
                  widget.isCurrent
                      ? widget.onSurface
                      : widget.onSurface.withOpacity(0.5),
            );
            _isLoading = false;
          });
        }
      } catch (e) {
        // 폰트 로드 실패 시 기본 스타일 사용
        if (mounted) {
          setState(() {
            _cachedStyle = widget.fontItem.getTextStyle(
              fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
              fontSize: widget.isCurrent ? 18 : 14,
              color:
                  widget.isCurrent
                      ? widget.onSurface
                      : widget.onSurface.withOpacity(0.5),
            );
            _isLoading = false;
          });
        }
      }
    } else {
      // 구글 폰트가 아닌 경우 즉시 적용
      if (mounted) {
        setState(() {
          _cachedStyle = widget.fontItem.getTextStyle(
            fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
            fontSize: widget.isCurrent ? 18 : 14,
            color:
                widget.isCurrent
                    ? widget.onSurface
                    : widget.onSurface.withOpacity(0.5),
          );
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _cachedStyle == null) {
      // 로딩 중일 때는 기본 스타일로 표시 (깜빡임 최소화)
      return Text(
        widget.fontItem.supportsKorean ? '가나다 ABCD 1234' : 'ABCD 1234 !?',
        style: TextStyle(
          fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
          fontSize: widget.isCurrent ? 18 : 14,
          color:
              widget.isCurrent
                  ? widget.onSurface
                  : widget.onSurface.withOpacity(0.5),
        ),
      );
    }

    return Text(
      widget.fontItem.supportsKorean ? '가나다 ABCD 1234' : 'ABCD 1234 !?',
      style: _cachedStyle,
    );
  }
}

class _GlassTile extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final bool highlighted;
  const _GlassTile({
    required this.onTap,
    required this.child,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 5.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,

          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
