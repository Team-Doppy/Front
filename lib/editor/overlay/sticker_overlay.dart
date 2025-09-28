import 'dart:ui' as ui;
import 'package:doppy/editor/overlay/drawing_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/editor/image/gallery_bottom_sheet.dart';
import 'package:doppy/theme/app_colors.dart';

enum StickerKind { text, emoji, image, draw }

class StickerOverlay extends StatefulWidget {
  const StickerOverlay({
    super.key,
    required this.onSubmit,
    required this.initialKind,
    this.initialText,
    this.initialEmoji,
    this.initialImage,
  });

  final void Function({
    required String text,
    String? emoji,
    Uint8List? image,
    Map<String, dynamic>? textStyle,
  })
  onSubmit;
  final StickerKind initialKind;
  final String? initialText;
  final String? initialEmoji;
  final Uint8List? initialImage;

  @override
  State<StickerOverlay> createState() => _StickerOverlayState();
}

class _StickerOverlayState extends State<StickerOverlay> {
  late StickerKind _kind; // 툴바에서 항상 초기 종류가 제공됨
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _emoji = '😀';
  bool _editing = false;
  double _fontSize = 40;
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  Color _textColor = Colors.white;
  TextAlign _textAlign = TextAlign.center;
  String _stylePreset = 'Strong';
  double _letterSpacing = 0;
  bool _useNeon = false;
  Color _neonColor = Colors.cyanAccent;
  bool _showFontPanel = false;
  bool _showColorPanel = false;

  @override
  void initState() {
    super.initState();
    // 툴바에서 항상 initialKind가 제공됨
    _kind = widget.initialKind;

    // 초기 편집 값 주입(스티커 수정 진입)
    if (widget.initialText != null) {
      _text.text = widget.initialText!;
    }
    if (widget.initialEmoji != null) {
      _emoji = widget.initialEmoji!;
    }
    _editing = true;

    // 텍스트 종류인 경우 자동으로 포커스
    if (_kind == StickerKind.text) {
      Future.delayed(
        const Duration(milliseconds: 100),
        () => _focus.requestFocus(),
      );
    }
    // 이미지 모드로 진입했을 때 갤러리를 바로 연다
    if (_kind == StickerKind.image) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickImageFromGallery();
      });
    }
    // 오버레이 진입 시 텍스트 기본 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_kind == StickerKind.text)) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    switch (_kind) {
      case StickerKind.text:
        return _text.text.trim().isNotEmpty;
      case StickerKind.emoji:
        return _emoji.isNotEmpty;
      case StickerKind.image:
        return false; // 이미지는 갤러리에서 바로 선택하므로 완료 버튼 불필요
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        // 드래그 중에는 아무것도 하지 않음 (시각적 피드백만)
      },
      onPanEnd: (details) {
        // 드래그 방향에 따라 오버레이 닫기
        final velocity = details.velocity.pixelsPerSecond;
        if (velocity.dy.abs() > velocity.dx.abs()) {
          // 세로 드래그 (아래로)
          if (velocity.dy > 300) {
            Navigator.of(context).pop();
          }
        } else {
          // 가로 드래그 (좌우)
          if (velocity.dx.abs() > 300) {
            Navigator.of(context).pop();
          }
        }
      },
      child:
          _kind == StickerKind.draw
              ? _buildDrawEditor()
              : Scaffold(
                backgroundColor: Colors.transparent,

                body: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const ui.Color.fromARGB(182, 144, 144, 144),
                            const ui.Color.fromARGB(200, 100, 100, 100),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).padding.top + 50,
                              child: Row(
                                children: [
                                  const SizedBox(width: 20),
                                  GestureDetector(
                                    onTap: () {
                                      _focus.unfocus();

                                      _editing = false;
                                      _showFontPanel = false;
                                      _showColorPanel = false;

                                      Navigator.of(context).pop();
                                    },
                                    child: Icon(
                                      Icons.arrow_back_ios_new,
                                      color: Colors.white.withOpacity(0.9),
                                      size: 20,
                                    ),
                                  ),
                                  Spacer(),
                                  _canSubmit
                                      ? TextButton(
                                        onPressed: _submit,
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text(
                                          '완료',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      )
                                      : Padding(
                                        padding: const EdgeInsets.only(
                                          right: 20,
                                        ),
                                        child: GestureDetector(
                                          onTap:
                                              () => Navigator.of(context).pop(),
                                          child: Icon(
                                            Icons.close,
                                            color: Colors.white.withOpacity(
                                              0.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),

                            // 중앙 프리뷰/에디터 영역
                            Expanded(
                              flex: 3,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: _buildEditor(),
                                ),
                              ),
                            ),

                            // 이모지 편집 컨트롤 (이미지는 갤러리에서 바로 선택)
                            if (_kind == StickerKind.emoji && !_editing)
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: _buildEditor(),
                                  ),
                                ),
                              ),

                            // 텍스트 편집 하단 컨트롤
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
    );
  }

  Widget _buildEditor() {
    switch (_kind) {
      case StickerKind.text:
        return _buildTextEditor();
      case StickerKind.emoji:
        return _buildEmojiEditor();
      case StickerKind.image:
        return const SizedBox.shrink(); // 이미지는 갤러리에서 바로 선택하므로 UI 불필요
      case StickerKind.draw:
        return const SizedBox.shrink(); // 드로잉은 오버레이에서 처리
    }
  }

  Widget _buildDrawEditor() {
    return DrawingOverlay(
      onSubmitImage: (image) {
        widget.onSubmit(text: '', image: image);
      },
    );
  }

  Widget _buildTextEditor() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              cursorColor: AppColors.darkTextPrimary,
              style: _currentTextStyle(),
              textAlign: _textAlign,
              decoration: InputDecoration(
                hintText: _hintText(),
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 50),
                border: const OutlineInputBorder(borderSide: BorderSide.none),
              ),
              onTap: () => setState(() => _editing = true),
              onChanged: (_) => setState(() => _editing = true),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 패널: 폰트 프리셋
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child:
                    !_showFontPanel
                        ? const SizedBox.shrink()
                        : Container(
                          key: const ValueKey('font_panel'),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.28),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final p in const [
                                  'Strong',
                                  'Meme',
                                  'Elegant',
                                  'Cute',
                                  'Handwrite',
                                  'Comic',
                                  'Neon',
                                  'Shadow',
                                  'Underline',
                                  'Thin',
                                  'Wide',
                                  'Tight',
                                  'Directional',
                                  'Literal',
                                ]) ...[
                                  _styleChip(
                                    p,
                                    onTap: () {
                                      setState(() {
                                        _stylePreset = p;
                                        _applyPreset(p);
                                      });
                                    },
                                    selected: _stylePreset == p,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                        ),
              ),

              // 패널: 색상 팔레트
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child:
                    !_showColorPanel
                        ? const SizedBox.shrink()
                        : Container(
                          key: const ValueKey('color_panel'),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.28),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final c in const [
                                Colors.white,
                                Colors.black,
                                Colors.yellow,
                                Colors.redAccent,
                                Colors.orangeAccent,
                                Colors.lightBlueAccent,
                                Colors.greenAccent,
                                Colors.purpleAccent,
                                Colors.pinkAccent,
                                Colors.cyanAccent,
                              ]) ...[_colorDot(c), const SizedBox(width: 8)],
                            ],
                          ),
                        ),
              ),

              // 하단 2-버튼 바
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _bottomGlassButton(
                    icon: Icons.text_fields,
                    label: _stylePreset.isEmpty ? '기본' : _stylePreset,
                    active: _showFontPanel,
                    onTap:
                        () => setState(() {
                          _showFontPanel = !_showFontPanel;
                          if (_showFontPanel) _showColorPanel = false;
                        }),
                  ),
                  const SizedBox(width: 12),
                  _bottomGlassButton(
                    icon: Icons.color_lens_outlined,
                    label: '색상',
                    active: _showColorPanel,
                    sampleColor: _textColor,
                    onTap:
                        () => setState(() {
                          _showColorPanel = !_showColorPanel;
                          if (_showColorPanel) _showFontPanel = false;
                        }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiEditor() {
    const emojis = [
      '😀',
      '😎',
      '🔥',
      '❤️',
      '🎉',
      '🤣',
      '🤔',
      '🤨',
      '🤯',
      '🤠',
      '🤡',
      '🤥',
      '🤤',
      '🤫',
      '🤭',
      '🤮',
      '🤯',
      '🤰',
      '🤱',
      '🤲',
      '🤳',
      '🤴',
      '🤵',
      '🤶',
      '🤷',
      '🤸',
      '🤹',
      '🤺',
      '🤻',
      '🤼',
      '🤽',
      '🤾',
      '🤿',
      '🤹',
      '🤺',
      '🤻',
      '🤼',
      '🤽',
      '🤾',
      '🤿',
    ];
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(_emoji, style: const TextStyle(fontSize: 100)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 3,
          child: SizedBox(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // 3열
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
                childAspectRatio: 1.2, // 정사각형에 가깝게
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                final e = emojis[index];
                final sel = e == _emoji;
                return GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: Container(
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel ? AppColors.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 32)),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop();
    switch (_kind) {
      case StickerKind.text:
        widget.onSubmit(
          text: _text.text.trim(),
          textStyle: {
            'preset': _stylePreset,
            'bold': _isBold,
            'italic': _isItalic,
            'underline': _isUnderline,
            'color':
                '#${_textColor.value.toRadixString(16).padLeft(8, '0').toUpperCase()}',
            'letterSpacing': _letterSpacing,
            'neon': _useNeon,
            'fontSize': 20,
            'align': _textAlign.name,
          },
        );
        break;
      case StickerKind.emoji:
        widget.onSubmit(text: '', emoji: _emoji);
        break;
      case StickerKind.image:
        // 이미지는 갤러리에서 바로 선택하므로 여기서는 처리하지 않음
        break;
      case StickerKind.draw:
        return;
    }
  }

  // ===== Helpers =====
  Future<void> _pickImageFromGallery() async {
    try {
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder:
            (sheetContext) => GalleryBottomSheet(
              onImagesSelected: (files) async {
                if (files.isEmpty) return;
                final bytes = await files.first.readAsBytes();
                if (!mounted) return;

                // 이미지 선택 시 바로 스티커로 추가하고 오버레이 닫기
                widget.onSubmit(text: '', image: bytes);
                Navigator.of(context).pop();
              },
            ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('이미지를 불러올 수 없습니다: $e')));
    }
  }

  // (unused helper removed)

  String _hintText() {
    final hex =
        '#${_textColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final preset = _stylePreset.isEmpty ? '기본' : _stylePreset;
    return '텍스트 입력 ($preset · $hex)';
  }

  TextStyle _currentTextStyle() {
    final shadows =
        _useNeon
            ? [
              Shadow(
                color: _neonColor.withOpacity(0.9),
                blurRadius: 14,
                offset: const Offset(0, 0),
              ),
              Shadow(
                color: _neonColor.withOpacity(0.5),
                blurRadius: 28,
                offset: const Offset(0, 0),
              ),
            ]
            : const <Shadow>[];

    return const TextStyle(color: Colors.white).copyWith(
      color: _textColor,
      fontSize: _fontSize,
      fontWeight: _isBold ? FontWeight.w800 : FontWeight.w500,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: _isUnderline ? TextDecoration.underline : TextDecoration.none,
      letterSpacing: _letterSpacing,
      shadows: shadows,
    );
  }

  void _applyPreset(String p) {
    // 프리셋 기본값 초기화
    _isBold = false;
    _isItalic = false;
    _isUnderline = false;
    _letterSpacing = 0;
    _useNeon = false;
    _textAlign = TextAlign.center;
    _fontSize = 50;
    _textColor = Colors.white;

    switch (p) {
      case 'Strong':
        _isBold = true;
        _fontSize = 34;
        break;
      case 'Meme':
        _isBold = true;
        _isItalic = true;
        _letterSpacing = 0.5;
        _fontSize = 34;
        break;
      case 'Elegant':
        _isItalic = true;
        _letterSpacing = 0.6;
        _fontSize = 32;
        break;
      case 'Cute':
        _isBold = true;
        _letterSpacing = 0.4;
        _fontSize = 34;
        break;
      case 'Handwrite':
        _isItalic = true;
        _letterSpacing = 0.2;
        _fontSize = 32;
        break;
      case 'Comic':
        _isBold = true;
        _letterSpacing = 0.8;
        _fontSize = 34;
        break;
      case 'Neon':
        _isBold = true;
        _useNeon = true;
        _neonColor = Colors.cyanAccent;
        _textColor = Colors.white;
        _letterSpacing = 0.6;
        _fontSize = 34;
        break;
      case 'Shadow':
        _isBold = true;
        _letterSpacing = 0.4;
        _fontSize = 34;
        break;
      case 'Underline':
        _isUnderline = true;
        _fontSize = 32;
        break;
      case 'Thin':
        _isBold = false;
        _letterSpacing = 0.2;
        _fontSize = 50;
        break;
      case 'Wide':
        _isBold = true;
        _letterSpacing = 1.6;
        _fontSize = 34;
        break;
      case 'Tight':
        _isBold = true;
        _letterSpacing = -0.2;
        _fontSize = 32;
        break;
      case 'Directional':
        _textAlign = TextAlign.center;
        break;
      case 'Literal':
        // 기본값 유지
        break;
    }
  }

  Widget _styleChip(
    String label, {
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected
                  ? Colors.white.withOpacity(0.20)
                  : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _bottomGlassButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    Color? sampleColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:
                  active
                      ? Colors.white.withOpacity(0.18)
                      : Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? AppColors.primary : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label.isEmpty ? '기본' : label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sampleColor != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: sampleColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white38),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorDot(Color c) {
    final bool sel = _textColor.value == c.value;
    return GestureDetector(
      onTap: () => setState(() => _textColor = c),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: sel ? AppColors.primary : Colors.white24,
            width: sel ? 2 : 1,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
