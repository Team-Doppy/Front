import 'package:flutter/material.dart';

/// 홈 화면 모드 (검색 / 일반)
enum HomeViewMode { normal, search }

/// 홈 화면 검색 모드용 검색 필드
/// - 키보드 바로 위에 위치 (MediaQuery.viewInsets.bottom 활용)
/// - 자동 포커스로 키보드 표시
class HomeSearchField extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String>? onSubmitted;

  const HomeSearchField({super.key, required this.onClose, this.onSubmitted});

  @override
  State<HomeSearchField> createState() => _HomeSearchFieldState();
}

class _HomeSearchFieldState extends State<HomeSearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomInset,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          12,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(color: Colors.transparent),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  cursorColor: Theme.of(context).colorScheme.onSurface,
                  decoration: InputDecoration(
                    hintText: '검색어를 입력하세요',
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    fillColor:
                        isDark
                            ? Theme.of(context).colorScheme.background
                            : Theme.of(context).colorScheme.surfaceVariant,
                    filled: true,
                  ),
                  onSubmitted: widget.onSubmitted,
                  textInputAction: TextInputAction.search,
                ),
              ),

              const SizedBox(width: 12),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.keyboard_arrow_down, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
