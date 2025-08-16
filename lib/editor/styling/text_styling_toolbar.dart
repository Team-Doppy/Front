import 'package:flutter/material.dart';
import 'text_styling_service.dart';

/// 4개의 기본 아이콘만 보이고, 탭 시 옆으로 세부 기능이 펼쳐지는 툴바
class TextStylingToolbar extends StatefulWidget {
  final TextStylingSystem stylingSystem;
  final VoidCallback? onInsertImage;

  const TextStylingToolbar(
      {Key? key, required this.stylingSystem, this.onInsertImage})
      : super(key: key);

  @override
  State<TextStylingToolbar> createState() => _TextStylingToolbarState();
}

enum ToolbarSection { none, image, insert, text, align }

class _TextStylingToolbarState extends State<TextStylingToolbar> {
  Map<String, bool> _currentStyles = {
    'bold': false,
    'italic': false,
    'underline': false,
    'strikethrough': false,
  };

  TextAlign _currentAlignment = TextAlign.center;
  ToolbarSection _expanded = ToolbarSection.none;

  @override
  void initState() {
    super.initState();
    _updateStyles();
  }

  void _updateStyles() {
    setState(() {
      _currentStyles = widget.stylingSystem.getCurrentStyles();
      _currentAlignment = widget.stylingSystem.getCurrentAlignment();
    });
  }

  void _toggle(ToolbarSection section) {
    setState(() {
      _expanded = _expanded == section ? ToolbarSection.none : section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Container(
      height: 64,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 이미지 섹션
              _buildMainIcon(
                icon: Icons.image_outlined,
                isActive: _expanded == ToolbarSection.image,
                onTap: () => _toggle(ToolbarSection.image),
              ),
              if (_expanded == ToolbarSection.image) ...[
                const SizedBox(width: 8),
                _buildChip(
                  icon: Icons.add_photo_alternate_outlined,
                  label: '이미지 삽입',
                  onTap: widget.onInsertImage,
                ),
              ],

              const SizedBox(width: 10),
              _buildDivider(),
              const SizedBox(width: 10),

              // 추가(플러스) 섹션
              _buildMainIcon(
                icon: Icons.add_box_outlined,
                isActive: _expanded == ToolbarSection.insert,
                onTap: () => _toggle(ToolbarSection.insert),
                activeColor: Colors.teal,
              ),
              if (_expanded == ToolbarSection.insert) ...[
                const SizedBox(width: 8),
                _buildColorDot(Colors.red, () {
                  widget.stylingSystem.applyTextColor(Colors.red);
                  _updateStyles();
                }),
                const SizedBox(width: 6),
                _buildColorDot(Colors.blue, () {
                  widget.stylingSystem.applyTextColor(Colors.blue);
                  _updateStyles();
                }),
                const SizedBox(width: 6),
                _buildColorDot(Colors.green, () {
                  widget.stylingSystem.applyTextColor(Colors.green);
                  _updateStyles();
                }),
                const SizedBox(width: 10),
                _buildMiniButton('12', () {
                  widget.stylingSystem.changeFontSize(12);
                  _updateStyles();
                }),
                const SizedBox(width: 6),
                _buildMiniButton('16', () {
                  widget.stylingSystem.changeFontSize(16);
                  _updateStyles();
                }),
                const SizedBox(width: 6),
                _buildMiniButton('20', () {
                  widget.stylingSystem.changeFontSize(20);
                  _updateStyles();
                }),
                const SizedBox(width: 6),
                _buildMiniButton('24', () {
                  widget.stylingSystem.changeFontSize(24);
                  _updateStyles();
                }),
              ],

              const SizedBox(width: 10),
              _buildDivider(),
              const SizedBox(width: 10),

              // 텍스트 스타일 섹션 (A)
              _buildMainIcon(
                icon: Icons.text_fields,
                isActive: _expanded == ToolbarSection.text,
                onTap: () => _toggle(ToolbarSection.text),
              ),
              if (_expanded == ToolbarSection.text) ...[
                const SizedBox(width: 8),
                _buildToggleIcon(
                  icon: Icons.format_bold,
                  isActive: _currentStyles['bold'] ?? false,
                  onTap: () {
                    widget.stylingSystem.toggleBold();
                    _updateStyles();
                  },
                ),
                const SizedBox(width: 6),
                _buildToggleIcon(
                  icon: Icons.format_italic,
                  isActive: _currentStyles['italic'] ?? false,
                  onTap: () {
                    widget.stylingSystem.toggleItalic();
                    _updateStyles();
                  },
                ),
                const SizedBox(width: 6),
                _buildToggleIcon(
                  icon: Icons.format_underlined,
                  isActive: _currentStyles['underline'] ?? false,
                  onTap: () {
                    widget.stylingSystem.toggleUnderline();
                    _updateStyles();
                  },
                ),
                const SizedBox(width: 6),
                _buildToggleIcon(
                  icon: Icons.format_strikethrough,
                  isActive: _currentStyles['strikethrough'] ?? false,
                  onTap: () {
                    widget.stylingSystem.toggleStrikethrough();
                    _updateStyles();
                  },
                ),
              ],

              const SizedBox(width: 10),
              _buildDivider(),
              const SizedBox(width: 10),

              // 정렬 섹션
              _buildMainIcon(
                icon: Icons.format_align_left,
                isActive: _expanded == ToolbarSection.align,
                onTap: () => _toggle(ToolbarSection.align),
              ),
              if (_expanded == ToolbarSection.align) ...[
                const SizedBox(width: 8),
                _buildToggleIcon(
                  icon: Icons.format_align_left,
                  isActive: _currentAlignment == TextAlign.left,
                  onTap: () {
                    widget.stylingSystem.applyTextAlignment(TextAlign.left);
                    _updateStyles();
                  },
                ),
                const SizedBox(width: 6),
                _buildToggleIcon(
                  icon: Icons.format_align_center,
                  isActive: _currentAlignment == TextAlign.center,
                  onTap: () {
                    widget.stylingSystem.applyTextAlignment(TextAlign.center);
                    _updateStyles();
                  },
                ),
                const SizedBox(width: 6),
                _buildToggleIcon(
                  icon: Icons.format_align_right,
                  isActive: _currentAlignment == TextAlign.right,
                  onTap: () {
                    widget.stylingSystem.applyTextAlignment(TextAlign.right);
                    _updateStyles();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final color =
        isActive ? (activeColor ?? Colors.black) : Colors.grey.shade700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }

  Widget _buildToggleIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isActive ? Colors.blue.shade100 : Colors.transparent,
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
            color: isActive ? Colors.blue.shade700 : Colors.grey.shade800,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 28, color: Colors.grey.shade300);
  }

  Widget _buildColorDot(Color color, VoidCallback onTap) {
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
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniButton(String label, VoidCallback onTap) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(
      {required IconData icon, required String label, VoidCallback? onTap}) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.grey.shade900),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // legacy helpers (not used in the new expandable UI)
  // kept here intentionally commented out for reference
  // Widget _buildColorButton(...) {}

  // Widget _buildAlignmentButton(...) {}

  // Widget _buildFontSizeButton(...) {}
}
