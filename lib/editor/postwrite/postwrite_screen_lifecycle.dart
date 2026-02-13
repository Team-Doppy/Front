import 'dart:async';
import 'package:flutter/material.dart';
import '../../editor/component/clip_component.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/style/text_styling_service.dart';

/// PostwriteScreen의 lifecycle 관련 기능을 분리한 mixin
mixin PostwriteScreenLifecycle<T extends StatefulWidget> on State<T> {
  // Required getters - State 클래스에서 제공해야 함
  Timer? get autoSaveTimer;
  FocusNode get editorFocusNode;
  EditorService get editorService;
  TextStylingService get textStylingService;
  ValueNotifier<bool> get keyboardVisibleNotifier;
  NodeComponentService get nodeComponentService;
  VoidCallback get onNodeSelectionChangedCallback;

  @override
  void dispose() {
    autoSaveTimer?.cancel();
    editorFocusNode.dispose();

    cleanupAllVideoPlayers();
    editorService.dispose();
    textStylingService.dispose();
    keyboardVisibleNotifier.dispose();
    nodeComponentService.clearSelectionSilently();
    nodeComponentService.clearHighlightedSelectionSilently();
    nodeComponentService.removeListener(onNodeSelectionChangedCallback);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // setContext는 MultiProvider 하위 Builder에서 호출 (Provider 접근을 위해)
    editorService.setEditorFocusNode(editorFocusNode);
  }
}
