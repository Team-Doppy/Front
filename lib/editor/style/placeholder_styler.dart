import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../service/drag_service.dart';

class PlaceholderStyler extends SingleColumnLayoutStylePhase {
  PlaceholderStyler({required DragService dragService})
    : _dragService = dragService {
    _dragService.addListener(_onDragChanged);
  }

  final DragService _dragService;

  void _onDragChanged() {
    markDirty();
  }

  @override
  void dispose() {
    _dragService.removeListener(_onDragChanged);
    super.dispose();
  }

  @override
  SingleColumnLayoutViewModel style(
    Document document,
    SingleColumnLayoutViewModel viewModel,
  ) {
    final dropIndex = _dragService.dropIndex;
    final draggingId = _dragService.draggingNodeId;

    if (dropIndex == null || draggingId == null) {
      return viewModel;
    }

    final components = List<SingleColumnLayoutComponentViewModel>.from(
      viewModel.componentViewModels,
    )..removeWhere((vm) => vm is PlaceholderViewModel);

    // 유효 인덱스 계산
    final clampedIndex = dropIndex.clamp(0, components.length);

    // placeholder 삽입
    components.insert(
      clampedIndex,
      PlaceholderViewModel(
        nodeId: '__placeholder__',
        createdAt: DateTime.now(),
        padding: EdgeInsets.zero,
      ),
    );

    // 끌던 항목은 뷰모델에는 남기지 않음 (미리보기는 Overlay)

    return SingleColumnLayoutViewModel(
      componentViewModels: components,
      padding: viewModel.padding,
    );
  }
}

/// Placeholder 렌더링용 뷰모델 (가느다란 라인 등)
class PlaceholderViewModel extends SingleColumnLayoutComponentViewModel {
  PlaceholderViewModel({
    required super.nodeId,
    required super.createdAt,
    required super.padding,
  });

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return PlaceholderViewModel(
      nodeId: nodeId,
      createdAt: createdAt,
      padding: padding,
    );
  }
}
