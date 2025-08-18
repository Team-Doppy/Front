import 'package:flutter/material.dart';

class OvalChoiceBar extends StatefulWidget {
  @override
  State<OvalChoiceBar> createState() => _OvalChoiceBarState();
}

class _OvalChoiceBarState extends State<OvalChoiceBar> {
  int selected = 0;
  final List<String> choices = ['한다리', '두다리', '세다리'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedBg =
        isDark
            ? const Color.fromARGB(255, 255, 255, 255)
            : const Color.fromARGB(255, 137, 147, 255);
    final selectedText = isDark ? Colors.black : Colors.white;
    final unselectedBg =
        isDark
            ? const Color.fromARGB(255, 130, 138, 255)
            : const Color(0xFFF2F2F2);
    final unselectedText = isDark ? Colors.white70 : Colors.grey[700];
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(choices.length, (idx) {
        final isSelected = selected == idx;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white, // 항상 흰색
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 0),
                  child: Text(
                    choices[idx],
                    style: TextStyle(
                      color: isSelected ? selectedText : unselectedText,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            selected: isSelected,
            onSelected: (_) => setState(() => selected = idx),
            backgroundColor: unselectedBg,
            selectedColor: selectedBg,
            shape: StadiumBorder(
              side: BorderSide(
                color: isSelected ? selectedBg : unselectedBg,
                width: 1.2,
              ),
            ),
            elevation: 0,
            shadowColor: Colors.transparent,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            showCheckmark: false, // 기본 체크 표시 끔
          ),
        );
      }),
    );
  }
}
