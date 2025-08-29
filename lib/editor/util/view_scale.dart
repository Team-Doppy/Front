import 'package:flutter/widgets.dart';

class EditorViewScale extends InheritedWidget {
  final double scale;

  const EditorViewScale({super.key, required this.scale, required Widget child})
    : super(child: child);

  static double of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<EditorViewScale>();
    return widget?.scale ?? 1.0;
  }

  @override
  bool updateShouldNotify(covariant EditorViewScale oldWidget) {
    return oldWidget.scale != scale;
  }
}
