import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/font.dart';
import '../style/font_catalog.dart';
import '../service/font_preload_service.dart';
import '../utils/font_localizations.dart';
import '../utils/editor_localization.dart';

// ==========================================
// 상수 정의
// ==========================================

class _FontSelectionConstants {
  _FontSelectionConstants._();

  // SharedPreferences 키
  static const String keyCurrentFamily = 'editor.current_font_family';
  static const String keyCurrentWeight = 'editor.current_font_weight';
  static const String keyFavorites = 'editor.favorite_fonts';

  // UI 상수
  static const double maxContentWidth = 520.0;
  static const double scrollbarThickness = 6.0;

  static const double fontLoadDelayPreloaded = 10.0;
  static const double fontLoadDelayNotPreloaded = 50.0;

  // 폰트 크기
  static const double fontSizeCurrent = 15.0;
  static const double fontSizeNormal = 12.0;
  static const double fontSizePreviewCurrent = 18.0;
  static const double fontSizePreviewNormal = 14.0;

  // 카테고리 값 (FontCatalog와 일치해야 함)
  static String getCategoryAll(BuildContext context) {
    return context.tr('editor_font_category_all');
  }

  static String getCategoryHandwriting(BuildContext context) {
    return context.tr('editor_font_category_handwriting');
  }

  static String getCategorySansSerif(BuildContext context) {
    return context.tr('editor_font_category_sans_serif');
  }

  static String getDefaultFontIdentifier(BuildContext context) {
    return context.tr('editor_font_default_sans_serif');
  }
}

// ==========================================
// 서비스 레이어
// ==========================================

/// 폰트 설정 저장/로드 서비스
class FontPrefsService {
  Future<void> saveCurrentFont(String? family, int weight) async {
    final prefs = await SharedPreferences.getInstance();
    if (family == null || family.isEmpty) {
      await prefs.remove(_FontSelectionConstants.keyCurrentFamily);
    } else {
      await prefs.setString(_FontSelectionConstants.keyCurrentFamily, family);
    }
    await prefs.setInt(_FontSelectionConstants.keyCurrentWeight, weight);
  }

  Future<(String?, int?)> loadCurrentFont() async {
    final prefs = await SharedPreferences.getInstance();
    final family = prefs.getString(_FontSelectionConstants.keyCurrentFamily);
    final weight = prefs.getInt(_FontSelectionConstants.keyCurrentWeight);
    return (family, weight);
  }

  Future<List<String>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_FontSelectionConstants.keyFavorites) ??
        const [];
  }

  Future<void> toggleFavorite(String family) async {
    final prefs = await SharedPreferences.getInstance();
    final list =
        prefs.getStringList(_FontSelectionConstants.keyFavorites) ?? <String>[];
    if (list.contains(family)) {
      list.removeWhere((e) => e == family);
    } else {
      list.add(family);
    }
    await prefs.setStringList(_FontSelectionConstants.keyFavorites, list);
  }

  Future<bool> isFavorite(String family) async {
    final prefs = await SharedPreferences.getInstance();
    final list =
        prefs.getStringList(_FontSelectionConstants.keyFavorites) ?? const [];
    return list.contains(family);
  }
}

// ==========================================
// 메인 위젯
// ==========================================

/// 폰트 선택 오버레이 위젯
///
/// DraggableScrollableSheet 형태로 표시되며, 사용자가 폰트를 검색하고 선택할 수 있습니다.
class FontOverlay extends StatefulWidget {
  final void Function(FontItem fontItem) onSelect;
  final VoidCallback? onClose;
  final ScrollController? scrollController;
  final DraggableScrollableController? sheetController;
  final String? initialCurrentFamily;

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
  // ==========================================
  // 의존성 및 상태
  // ==========================================

  final FontPrefsService _prefs = FontPrefsService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Set<String> _favorites = <String>{};
  (String?, int?) _current = (null, null);
  String _query = '';
  late String _selectedCategory;

  // ==========================================
  // 생명주기
  // ==========================================

  @override
  void initState() {
    super.initState();
    // 초기 카테고리는 나중에 context를 사용할 수 있을 때 설정
    _selectedCategory = ''; // 임시값, _loadPreferences에서 설정됨
    _loadPreferences();
    _initializeCategoryByLocale();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==========================================
  // 초기화 메서드
  // ==========================================

  Future<void> _loadPreferences() async {
    final favorites = await _prefs.loadFavorites();
    final current = await _prefs.loadCurrentFont();

    if (!mounted) return;

    setState(() {
      _favorites = favorites.toSet();
      _current = widget.initialCurrentFamily?.isNotEmpty == true
          ? (widget.initialCurrentFamily, current.$2)
          : current;
      // 초기 카테고리 설정
      _selectedCategory = _FontSelectionConstants.getCategoryAll(context);
    });
  }

  void _initializeCategoryByLocale() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isEnglish =
          EditorTranslations.currentLocale == EditorLocale.english;
      final categoryAll = _FontSelectionConstants.getCategoryAll(context);
      if (isEnglish && _selectedCategory == categoryAll) {
        setState(() {
          _selectedCategory = FontSelectionLocalizations.translate(
            'category_all',
            isEnglish: true,
          );
        });
      }
    });
  }

  // ==========================================
  // 비즈니스 로직
  // ==========================================

  Future<void> _toggleFavorite(String? family) async {
    if (family == null || family.isEmpty) return;

    await _prefs.toggleFavorite(family);
    final favorites = await _prefs.loadFavorites();

    if (!mounted) return;

    setState(() => _favorites = favorites.toSet());
  }

  bool _isFavorite(String? family) {
    return family != null && family.isNotEmpty && _favorites.contains(family);
  }

  Future<void> _handleFontSelection(FontItem font) async {
    // 폰트 프리로드 (백그라운드)
    final preloadService = FontPreloadService();
    if (font.googleFont != null &&
        !preloadService.isPreloaded(font.identifier)) {
      preloadService.preloadFont(font).catchError((e) {
        debugPrint('[FontOverlay] 폰트 로드 실패: ${font.displayName} - $e');
      });
    }

    // 에디터에 즉시 적용
    widget.onSelect(font);

    // 현재 폰트 저장
    await _prefs.saveCurrentFont(font.identifier, FontWeight.w400.index);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ==========================================
  // 데이터 필터링 및 정렬
  // ==========================================

  List<FontItem> _getFilteredFonts(bool isEnglish) {
    List<FontItem> fonts = FontCatalog.all;

    // 영어 모드일 때 한글 지원 폰트 제외
    if (isEnglish) {
      fonts = fonts.where((f) => !f.supportsKorean).toList();
    }

    // 카테고리 필터링
    final categoryAll = FontSelectionLocalizations.translate(
      'category_all',
      isEnglish: isEnglish,
    );
    if (_selectedCategory != categoryAll) {
      fonts = fonts.where((f) => f.category == _selectedCategory).toList();
    }

    // 검색 필터링
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      fonts = fonts.where((f) {
        final displayName = f.displayName.toLowerCase();
        final category = f.category.toLowerCase();
        return displayName.contains(query) || category.contains(query);
      }).toList();
    }

    return fonts;
  }

  FontItem? _findCurrentFont(List<FontItem> fonts, bool isEnglish) {
    final currentIdentifier = _current.$1;

    if (currentIdentifier == null || currentIdentifier.isEmpty) {
      // 기본 폰트 찾기
      if (isEnglish) {
        return fonts.firstWhere(
          (f) => f.localFontFamily == null && !f.supportsKorean,
          orElse: () => fonts.isNotEmpty
              ? fonts.firstWhere(
                  (f) => !f.supportsKorean,
                  orElse: () => fonts.first,
                )
              : FontCatalog.all.firstWhere(
                  (f) => !f.supportsKorean,
                  orElse: () => FontCatalog.all.first,
                ),
        );
      } else {
        final defaultIdentifier =
            _FontSelectionConstants.getDefaultFontIdentifier(context);
        return fonts.firstWhere(
          (f) =>
              f.identifier == defaultIdentifier ||
              (f.displayName == defaultIdentifier &&
                  f.category ==
                      _FontSelectionConstants.getCategorySansSerif(context)),
          orElse: () => fonts.isNotEmpty ? fonts.first : FontCatalog.all.first,
        );
      }
    } else {
      return fonts.firstWhere(
        (f) => f.identifier == currentIdentifier,
        orElse: () => fonts.isNotEmpty ? fonts.first : FontCatalog.all.first,
      );
    }
  }

  List<FontItem> _sortFonts(List<FontItem> fonts, FontItem? currentFont) {
    final favorites = fonts
        .where(
          (f) =>
              _isFavorite(f.identifier) &&
              f.identifier != currentFont?.identifier,
        )
        .toList();

    final others = fonts
        .where(
          (f) =>
              !_isFavorite(f.identifier) &&
              f.identifier != currentFont?.identifier,
        )
        .toList();

    final categoryHandwriting = _FontSelectionConstants.getCategoryHandwriting(
      context,
    );
    final categorySansSerif = _FontSelectionConstants.getCategorySansSerif(
      context,
    );

    final handwriting = others
        .where((f) => f.category == categoryHandwriting)
        .toList();
    final sansSerif = others
        .where((f) => f.category == categorySansSerif)
        .toList();
    final rest = others
        .where(
          (f) =>
              f.category != categoryHandwriting &&
              f.category != categorySansSerif,
        )
        .toList();

    return [
      if (currentFont != null) currentFont,
      ...favorites,
      ...handwriting,
      ...sansSerif,
      ...rest,
    ];
  }

  // ==========================================
  // UI 빌드
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final isEnglish = EditorTranslations.currentLocale == EditorLocale.english;

    final fonts = _getFilteredFonts(isEnglish);
    final currentFont = _findCurrentFont(fonts, isEnglish);
    final sortedFonts = _sortFonts(fonts, currentFont);

    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),

          _buildSearchBar(context, theme, isEnglish),
          const SizedBox(height: 4),
          _buildFontList(context, theme, sortedFonts, currentFont, isEnglish),
        ],
      ),
    );
  }

  Widget _buildSearchBar(
    BuildContext context,
    ColorScheme theme,
    bool isEnglish,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              cursorColor: theme.onSurface,
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              style: TextStyle(color: theme.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: FontSelectionLocalizations.translate(
                  'search_hint',
                  isEnglish: isEnglish,
                ),
                hintStyle: TextStyle(
                  color: theme.onSurface.withOpacity(0.5),
                  fontSize: 14,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(20),
                ),
                filled: true,
                fillColor: theme.onSurface.withOpacity(0.05),
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
              color: theme.onSurface.withOpacity(0.5),
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _buildFontList(
    BuildContext context,
    ColorScheme theme,
    List<FontItem> fonts,
    FontItem? currentFont,
    bool isEnglish,
  ) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > _FontSelectionConstants.maxContentWidth
              ? _FontSelectionConstants.maxContentWidth
              : constraints.maxWidth;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: RawScrollbar(
                controller: widget.scrollController ?? _scrollController,
                thumbVisibility: true,
                thickness: _FontSelectionConstants.scrollbarThickness,
                radius: const Radius.circular(10),
                thumbColor: theme.onSurface.withOpacity(0.3),
                trackColor: theme.onSurface.withOpacity(0.05),
                child: ListView.separated(
                  controller: widget.scrollController ?? _scrollController,
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                  itemCount: fonts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, index) {
                    final font = fonts[index];
                    final isCurrent =
                        font.identifier == (currentFont?.identifier ?? '');

                    return _FontTile(
                      font: font,
                      isCurrent: isCurrent,
                      isFavorite: _isFavorite(font.identifier),
                      onTap: () => _handleFontSelection(font),
                      onToggleFavorite: () => _toggleFavorite(font.identifier),
                      onSurface: theme.onSurface,
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 폰트 타일 위젯
// ==========================================

class _FontTile extends StatelessWidget {
  final FontItem font;
  final bool isCurrent;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final Color onSurface;

  const _FontTile({
    required this.font,
    required this.isCurrent,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassTile(
      onTap: onTap,
      highlighted: isCurrent,
      child: Padding(
        padding: const EdgeInsets.only(left: 5, right: 10, top: 8, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    font.displayName,
                    style: TextStyle(
                      color: isCurrent ? onSurface : onSurface.withOpacity(0.5),
                      fontSize: isCurrent
                          ? _FontSelectionConstants.fontSizeCurrent
                          : _FontSelectionConstants.fontSizeNormal,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _FontPreviewText(
                    fontItem: font,
                    isCurrent: isCurrent,
                    onSurface: onSurface,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onToggleFavorite,
              child: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                size: 20,
                color: isFavorite
                    ? Colors.redAccent
                    : onSurface.withOpacity(0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 폰트 미리보기 위젯
// ==========================================

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
    if (widget.fontItem.googleFont == null) {
      _applyLocalFont();
      return;
    }

    try {
      final preloadService = FontPreloadService();
      final isPreloaded = preloadService.isPreloaded(
        widget.fontItem.identifier,
      );

      if (isPreloaded) {
        _applyCachedStyle();
        return;
      }

      // Google Font 로드
      final style = widget.fontItem.googleFont!(
        fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
        fontSize: widget.isCurrent
            ? _FontSelectionConstants.fontSizePreviewCurrent
            : _FontSelectionConstants.fontSizePreviewNormal,
      );

      await Future.delayed(
        Duration(
          milliseconds: isPreloaded
              ? _FontSelectionConstants.fontLoadDelayPreloaded.toInt()
              : _FontSelectionConstants.fontLoadDelayNotPreloaded.toInt(),
        ),
      );

      if (mounted) {
        setState(() {
          _cachedStyle = style.copyWith(
            color: widget.isCurrent
                ? widget.onSurface
                : widget.onSurface.withOpacity(0.5),
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      _applyLocalFont();
    }
  }

  void _applyCachedStyle() {
    if (!mounted) return;

    setState(() {
      _cachedStyle = widget.fontItem.getTextStyle(
        fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
        fontSize: widget.isCurrent
            ? _FontSelectionConstants.fontSizePreviewCurrent
            : _FontSelectionConstants.fontSizePreviewNormal,
        color: widget.isCurrent
            ? widget.onSurface
            : widget.onSurface.withOpacity(0.5),
      );
      _isLoading = false;
    });
  }

  void _applyLocalFont() {
    if (!mounted) return;

    setState(() {
      _cachedStyle = widget.fontItem.getTextStyle(
        fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
        fontSize: widget.isCurrent
            ? _FontSelectionConstants.fontSizePreviewCurrent
            : _FontSelectionConstants.fontSizePreviewNormal,
        color: widget.isCurrent
            ? widget.onSurface
            : widget.onSurface.withOpacity(0.5),
      );
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewText = widget.fontItem.supportsKorean
        ? FontSelectionLocalizations.translate(
            'preview_korean',
            isEnglish: false,
          )
        : FontSelectionLocalizations.translate(
            'preview_english',
            isEnglish: false,
          );

    if (_isLoading || _cachedStyle == null) {
      return Text(
        previewText,
        style: TextStyle(
          fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
          fontSize: widget.isCurrent
              ? _FontSelectionConstants.fontSizePreviewCurrent
              : _FontSelectionConstants.fontSizePreviewNormal,
          color: widget.isCurrent
              ? widget.onSurface
              : widget.onSurface.withOpacity(0.5),
        ),
      );
    }

    return Text(previewText, style: _cachedStyle);
  }
}

// ==========================================
// 유틸리티 위젯
// ==========================================

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
