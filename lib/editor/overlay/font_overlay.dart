import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:doppy/data/services/font_prefs_service.dart';
import 'package:doppy/editor/style/font_catalog.dart';

/// 폰트 선택 오버레이 (mention_overlay와 유사한 구조)
class FontOverlay extends StatefulWidget {
  final void Function(FontItem fontItem) onSelect;
  final VoidCallback? onClose;

  const FontOverlay({super.key, required this.onSelect, this.onClose});

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
  }

  Future<void> _loadPrefs() async {
    final fav = await _prefs.loadFavorites();
    final cur = await _prefs.loadCurrentFont();
    if (!mounted) return;
    setState(() {
      _favorites = fav.toSet();
      _current = cur;
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

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    // 전체 폰트 리스트
    List<FontItem> allFonts = FontCatalog.all;

    // 카테고리 필터링
    if (_selectedCategory != '전체') {
      allFonts =
          allFonts.where((f) => f.category == _selectedCategory).toList();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,

      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: const Color.fromARGB(182, 86, 86, 86),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 55),
              // 상단 바 (뒤로가기 + 검색)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    // 뒤로가기 버튼
                    GestureDetector(
                      onTap: () {
                        if (widget.onClose != null) {
                          widget.onClose!();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 검색창
                    Expanded(
                      child: TextField(
                        cursorColor: onSurface,
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(color: onSurface, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '폰트 검색',
                          hintStyle: TextStyle(
                            color: onSurface.withOpacity(0.5),
                            fontSize: 14,
                          ),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          filled: true,
                          fillColor: onSurface.withOpacity(0.1),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 0,
                          ),
                          suffixIcon: Icon(
                            Icons.search,
                            color: onSurface.withOpacity(0.7),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

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
                      currentChoice = filtered.firstWhere(
                        (f) => f.identifier == '기본 산세리프',
                        orElse:
                            () =>
                                filtered.isNotEmpty
                                    ? filtered.first
                                    : FontCatalog.all.first,
                      );
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

                    // 즐겨찾기와 기타로 분류
                    final favorites =
                        filtered
                            .where(
                              (f) =>
                                  _isFavorite(f.identifier) &&
                                  f.identifier != currentChoice?.identifier,
                            )
                            .toList();
                    final others =
                        filtered
                            .where(
                              (f) =>
                                  !_isFavorite(f.identifier) &&
                                  f.identifier != currentChoice?.identifier,
                            )
                            .toList();

                    final ordered = <FontItem>[
                      currentChoice,
                      ...favorites,
                      ...others,
                    ];

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: RawScrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          thickness: 6,
                          radius: const Radius.circular(10),
                          thumbColor: Colors.white.withOpacity(0.5),
                          trackColor: Colors.white.withOpacity(0.1),
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                            itemCount: ordered.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 4),
                            itemBuilder: (_, i) {
                              final f = ordered[i];
                              final bool isCurrent =
                                  f.identifier ==
                                  (currentChoice?.identifier ?? '');

                              return _GlassTile(
                                onTap: () async {
                                  // 에디터에 즉시 적용
                                  widget.onSelect(f);
                                  // 현재 폰트 저장 (다음 오픈 시 "현재 사용 중"으로 인식)
                                  await _prefs.saveCurrentFont(
                                    f.identifier,
                                    FontWeight.w400.index,
                                  );
                                  if (widget.onClose != null) {
                                    widget.onClose!();
                                  } else {
                                    Navigator.of(context).maybePop();
                                  }
                                },
                                highlighted: isCurrent,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 5,
                                    right: 10,
                                    top: 10,
                                    bottom: 10,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,

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
                                                    color: onSurface
                                                        .withOpacity(0.75),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                              ],
                                            ),

                                            Text(
                                              f.supportsKorean
                                                  ? '가나다 ABCD 1234'
                                                  : 'ABCD 1234 !?',
                                              style: f.getTextStyle(
                                                fontSize: 18,
                                                color: onSurface,
                                                fontWeight: FontWeight.w400,
                                              ),
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
                                                    ? Colors.pinkAccent
                                                    : onSurface.withOpacity(
                                                      0.6,
                                                    ),
                                          ),
                                        ),
                                        onTap:
                                            () => _toggleFavorite(f.identifier),
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
        ),
      ),
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
    return ClipRRect(
      child: Material(
        color:
            highlighted
                ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2)
                : Colors.transparent,

        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
