import 'dart:ui' as ui;
import 'package:doppy/editor/overlay/drawing_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/editor/image/gallery_bottom_sheet.dart';
import 'package:doppy/editor/image/custom_image_editor_screen.dart';
import 'package:doppy/theme/app_colors.dart';

enum StickerKind { text, emoji, image, draw }

class StickerOverlay extends StatefulWidget {
  const StickerOverlay({
    super.key,
    required this.onSubmit,
    this.initialKind,
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
  final StickerKind? initialKind;
  final String? initialText;
  final String? initialEmoji;
  final Uint8List? initialImage;

  @override
  State<StickerOverlay> createState() => _StickerOverlayState();
}

class _StickerOverlayState extends State<StickerOverlay> {
  StickerKind? _kind; // 처음엔 어떤 항목도 선택되지 않음
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _emoji = '😀';
  Uint8List? _imageBytes;
  bool _editing = false;
  // 텍스트 스타일 상태
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
  // 하단 토글 패널 상태
  bool _showFontPanel = false;
  bool _showColorPanel = false;
  // 개별 토글 제거로 더 이상 사용되지 않음 (프리셋 내부에서만 상태 사용)
  // bool _bgBox = false; // A 배경
  // bool _glow = false; // 점선 A 느낌의 글로우

  @override
  void initState() {
    super.initState();
    // 초기 편집 값 주입(스티커 수정 진입)
    if (widget.initialKind != null) {
      _kind = widget.initialKind;
      if (widget.initialText != null) {
        _text.text = widget.initialText!;
      }
      if (widget.initialEmoji != null) {
        _emoji = widget.initialEmoji!;
      }
      if (widget.initialImage != null) {
        _imageBytes = widget.initialImage!;
      }
      _editing = true;
    }
    // 이미지 모드로 진입했는데 초기 이미지가 없다면, 갤러리를 바로 연다
    if (_kind == StickerKind.image && _imageBytes == null) {
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
        return _imageBytes != null;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 배경 블러 + 반투명
          Positioned.fill(
            child: GestureDetector(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: const ui.Color.fromARGB(182, 144, 144, 144),
                ),
              ),
            ),
          ),

          // 중앙 프리뷰/에디터 (텍스트는 인라인 에디터)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child:
                  _kind == null
                      ? const SizedBox.shrink()
                      : (_kind == StickerKind.text
                          ? _buildEditor()
                          : _buildPreview()),
            ),
          ),

          Positioned(
            top: 82,
            left: 16,
            right: 16,
            child: Center(
              child: Text(
                '스티커',
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          if (_kind == null)
            Positioned(
              top: 80,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(Icons.close, color: Colors.white.withOpacity(0.8)),
              ),
            )
          else
            Positioned(
              top: 80,
              left: 16,
              child: GestureDetector(
                onTap: () {
                  _focus.unfocus();
                  setState(() {
                    _editing = false;
                    _showFontPanel = false;
                    _showColorPanel = false;
                    _kind = null; // 뒤로가기 → 종류 선택 화면으로
                  });
                },
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white.withOpacity(0.9),
                  size: 20,
                ),
              ),
            ),
          // 상단 우측: 완료(가능 시) 또는 닫기
          if (_kind != null)
            Positioned(
              top: 74,
              right: 10,
              child:
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
                      : GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Icon(
                          Icons.close,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
            ),

          // 플로팅 편집 컨트롤 (바텀시트 제거)
          // 상단 종류 선택 완료 버튼은 제거 (이미지에서 none으로만 바뀌는 문제 방지)
          if (!_editing && _kind == null)
            Positioned(
              left: 0,
              right: 0,
              top: 100,
              bottom: 100,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildKindSelector(),
                ),
              ),
            ),
          // 텍스트 편집 하단 2-버튼 바 + 펼쳐지는 패널들
          if (_kind == StickerKind.text)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
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
                                  ]) ...[
                                    _colorDot(c),
                                    const SizedBox(width: 8),
                                  ],
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
          // 이모지/이미지 편집 컨트롤(텍스트는 중앙 인라인 편집이므로 제외)
          if (_kind != StickerKind.text && _kind != null && !_editing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 150,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildEditor(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKindSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _kindChip(Icons.text_fields, '텍스트', StickerKind.text),
        const SizedBox(width: 8),
        _kindChip(Icons.image_outlined, '이미지', StickerKind.image),
        const SizedBox(width: 8),
        _kindChip(Icons.emoji_emotions_outlined, '이모지', StickerKind.emoji),
        const SizedBox(width: 8),
        _kindChip(Icons.brush_outlined, '그리기', StickerKind.draw),
      ],
    );
  }

  Widget _kindChip(IconData icon, String label, StickerKind kind) {
    final Widget chip = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.darkBackground.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 20, height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return GestureDetector(
      onTap: () async {
        if (kind == StickerKind.draw) {
          // 드로잉은 별도 풀스크린로 진입하고, 완료 후 현재 오버레이까지 닫음
          await Navigator.of(context).push(
            PageRouteBuilder(
              opaque: false,
              barrierDismissible: true,
              pageBuilder:
                  (_, __, ___) => DrawingOverlay(
                    onSubmitImage: (Uint8List png) {
                      widget.onSubmit(text: '', image: png);
                    },
                  ),
            ),
          );
          if (mounted) Navigator.of(context).pop();
          return;
        }

        setState(() => _kind = kind);
        if (kind == StickerKind.text) {
          Future.delayed(
            const Duration(milliseconds: 50),
            () => _focus.requestFocus(),
          );
        } else if (kind == StickerKind.image) {
          // 이미지 선택 칩을 누르면 즉시 갤러리 열기
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _pickImageFromGallery();
          });
        }
      },
      child: chip,
    );
  }

  Widget _buildEditor() {
    switch (_kind) {
      case null:
        return const SizedBox.shrink();
      case StickerKind.text:
        return TextField(
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
        );
      case StickerKind.emoji:
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
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(emojis.length, (i) {
            final e = emojis[i];
            final sel = e == _emoji;
            return GestureDetector(
              onTap: () => setState(() => _emoji = e),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(e, style: const TextStyle(fontSize: 26)),
              ),
            );
          }),
        );
      case StickerKind.image:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _pickImageFromGallery,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: AppColors.darkBackground,
                    backgroundColor: Colors.white,
                  ),
                  child: const Text('갤러리에서 선택'),
                ),
                const SizedBox(width: 8),
                if (_imageBytes != null)
                  OutlinedButton(
                    onPressed: () async {
                      final edited = await _openEditorFor(_imageBytes!);
                      if (!mounted) return;
                      if (edited != null) setState(() => _imageBytes = edited);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.darkBackground,
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '편집',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                const SizedBox(width: 8),
                if (_imageBytes != null)
                  OutlinedButton(
                    onPressed: () => setState(() => _imageBytes = null),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: AppColors.darkBackground,
                      backgroundColor: Colors.white,
                    ),
                    child: const Text('지우기'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_imageBytes == null)
              const Text('이미지를 선택하세요', style: TextStyle(color: Colors.white60)),
          ],
        );
      case StickerKind.draw:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPreview() {
    switch (_kind) {
      case null:
        return const SizedBox.shrink();
      case StickerKind.text:
        final t = _text.text.trim();
        return t.isEmpty
            ? const SizedBox.shrink()
            : Text(
              t,
              textAlign: TextAlign.center,
              style: _currentTextStyle().copyWith(fontSize: (_fontSize + 6)),
            );
      case StickerKind.emoji:
        return Text(_emoji, style: const TextStyle(fontSize: 64));
      case StickerKind.image:
        if (_imageBytes == null) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
            child: Image.memory(
              _imageBytes!,
              fit: BoxFit.contain, // 원본 비율 유지
            ),
          ),
        );
      case StickerKind.draw:
        return const SizedBox.shrink();
    }
  }

  void _submit() {
    switch (_kind) {
      case null:
        return;
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
        widget.onSubmit(text: '', image: _imageBytes);
        break;
      case StickerKind.draw:
        return;
    }
    Navigator.of(context).pop();
  }

  // ===== Helpers =====
  Future<void> _pickImageFromGallery() async {
    try {
      // 커스텀 갤러리로 대체됨: 여전히 직접 호출될 수 있으니 동일 동작 수행
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
                setState(() => _imageBytes = bytes);
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

  Future<Uint8List?> _openEditorFor(Uint8List bytes) async {
    try {
      final editedBytes = await openImageEditorPlus(context, imageBytes: bytes);
      return editedBytes;
    } catch (e) {
      return null;
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
