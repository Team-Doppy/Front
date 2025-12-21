import 'dart:async';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

enum DragType { none, reorder, imageRowMerge }

class DragService extends ChangeNotifier {
  final EditorService editorService;
  NodeComponentService? _imageService;
  ScrollController? scrollController;

  NodeComponentService? get imageService => _imageService;

  String? draggingNodeId;
  final ValueNotifier<String?> draggingNodeIdNotifier = ValueNotifier<String?>(
    null,
  );
  NodeType? draggingNodeType;
  String? targetNodeId;
  NodeType? targetNodeType;
  DragType dragMode = DragType.none;

  Offset? dragPosition;
  int? dropIndex;
  Offset? lastMovedPosition;

  // 🎯 드래그 오버레이에 표시할 이미지 URL (로드 없이 바로 표시)
  String? previewImageUrl;
  String? previewImageLocalPath; // 로컬 파일 경로 (ClipNode용)

  // 이미지 분리 정보
  String? _splitImageRowId;
  int? _splitImageIndex;
  // 이미지 행 타겟 삽입 정보
  String? _targetRowId;

  // Auto-scroll state
  Timer? _autoScrollTimer;
  double _autoScrollDirection = 0.0; // -1: up, 1: down, 0: none

  // ===== 레이아웃/좌표 유틸 및 성능 캐시 =====
  final Map<String, Rect> _nodeRectCache = {};
  void invalidateNodeRectCache() => _nodeRectCache.clear();

  Rect? getNodeGlobalRect(String nodeId) {
    try {
      final cached = _nodeRectCache[nodeId];
      if (cached != null) return cached;
      final layout =
          editorService.documentLayoutKey?.currentState as DocumentLayout?;
      if (layout == null) return null;
      final component = layout.getComponentByNodeId(nodeId);
      if (component == null) return null;

      final ro = component.context.findRenderObject();
      RenderBox? box;
      if (ro is RenderSliverToBoxAdapter) {
        box = ro.child;
      } else if (ro is RenderBox) {
        box = ro;
      }
      if (box == null) return null;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      _nodeRectCache[nodeId] = rect;
      return rect;
    } catch (_) {
      return null;
    }
  }

  Offset? globalToDocumentLocal(Offset global) {
    try {
      final ro =
          editorService.documentLayoutKey?.currentContext?.findRenderObject();
      RenderBox? renderBox;
      if (ro is RenderSliverToBoxAdapter) {
        renderBox = ro.child;
      } else if (ro is RenderBox) {
        renderBox = ro;
      }
      if (renderBox == null) return null;
      return renderBox.globalToLocal(global);
    } catch (_) {
      return null;
    }
  }

  /// 세로 노드 사이 클릭 감지. 감지 시 삽입 인덱스 반환
  int? detectVerticalGapAt(Offset globalPos, {double pad = 30.0}) {
    // 🎯 4.0 → 20.0 증가
    final layout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (layout == null) return null;

    final local = globalToDocumentLocal(globalPos);
    if (local == null) return null;

    DocumentPosition? nearest;
    try {
      nearest = layout.getDocumentPositionNearestToOffset(local);
    } catch (_) {
      return null;
    }
    if (nearest == null) return null;

    final doc = editorService.document;
    final idx = doc.getNodeIndexById(nearest.nodeId);
    if (idx < 0) return null;

    bool isGapBetween(int aIndex, int bIndex) {
      final a = doc.getNodeAt(aIndex);
      final b = doc.getNodeAt(bIndex);
      if (a == null || b == null) return false;
      final ra = getNodeGlobalRect(a.id);
      final rb = getNodeGlobalRect(b.id);
      if (ra == null || rb == null) return false;
      final y = globalPos.dy;
      return (y >= ra.bottom - pad && y <= rb.top + pad);
    }

    if (idx + 1 < doc.nodeCount && isGapBetween(idx, idx + 1)) {
      return idx + 1;
    }
    if (idx - 1 >= 0 && isGapBetween(idx - 1, idx)) {
      return idx;
    }
    return null;
  }

  DragService({
    required this.editorService,
    NodeComponentService? imageService,
    this.scrollController,
  }) : _imageService = imageService;

  void setImageService(NodeComponentService imageService) {
    _imageService = imageService;
  }

  bool get isDragging => draggingNodeId != null;
  bool get hasSplitImageInfo =>
      _splitImageRowId != null && _splitImageIndex != null;

  void attachScrollController(ScrollController controller) {
    scrollController = controller;
  }

  // 분리할 이미지 정보 설정
  void setSplitImageInfo(String rowId, int imageIndex) {
    _splitImageRowId = rowId;
    _splitImageIndex = imageIndex;
  }

  // 분리할 이미지 정보 가져오기
  Map<String, dynamic>? getSplitImageInfo() {
    if (_splitImageRowId != null && _splitImageIndex != null) {
      return {'rowId': _splitImageRowId, 'imageIndex': _splitImageIndex};
    }
    return null;
  }

  void startDrag(String nodeId, BuildContext context, Offset globalPosition) {
    // 🎯 업로드 중인 그룹 이미지는 드래그 불가
    final node = editorService.document.getNodeById(nodeId);
    if (node is ImageRowNode || node is PageViewImageNode) {
      final meta = (node as dynamic).metadata as Map<String, dynamic>?;
      if (meta != null && meta['isPlaceholder'] == true) {
        debugPrint('[DragService] ⚠️ 업로드 중인 그룹 이미지는 드래그할 수 없습니다');
        return; // 드래그 시작 차단
      }
    }

    draggingNodeId = nodeId;
    draggingNodeIdNotifier.value = nodeId;
    draggingNodeType = editorService.getNodeType(nodeId);
    dragPosition = globalPosition;
    lastMovedPosition = globalPosition;

    // 🎯 노드에서 이미지 URL 추출
    _extractImageUrl(nodeId);

    _stopAutoScroll();
    _autoScrollDirection = 0.0;

    final dropInfo = computeDropInfo(globalPosition);
    if (dropInfo != null) {
      dropIndex = dropInfo['dropIndex'] as int?;
    }

    // ClipNode 드래그 시작 시 모든 비디오 일시정지
    if (node is ClipNode) {
      _pauseAllVideos();
    }

    notifyListeners();
  }

  // 🎯 노드에서 이미지 URL 추출
  void _extractImageUrl(String nodeId) {
    try {
      final node = editorService.document.getNodeById(nodeId);
      if (node == null) {
        previewImageUrl = null;
        previewImageLocalPath = null;
        return;
      }

      previewImageUrl = null;
      previewImageLocalPath = null;

      if (node is ImageNode) {
        // 🚀 로컬-네트워크 혼용 구조: 로컬 경로인지 확인
        final imageUrl = node.imageUrl;
        if (imageUrl.isNotEmpty && !EditorService.isNetworkUrl(imageUrl)) {
          // 로컬 경로인 경우
          previewImageLocalPath = imageUrl;
        } else {
          // 네트워크 URL인 경우
          previewImageUrl = imageUrl;
        }
      } else if (node is ClipNode) {
        // ClipNode: thumbnailPath 우선, 없으면 metadata의 thumbnailUrl
        if (node.thumbnailPath.isNotEmpty) {
          previewImageLocalPath = node.thumbnailPath;
        } else if (node.localPath.isNotEmpty) {
          previewImageLocalPath = node.localPath;
        } else {
          final meta = node.metadata;
          if (meta['thumbnailUrl'] != null) {
            previewImageUrl = meta['thumbnailUrl'].toString();
          }
        }
      } else if (node is ImageRowNode) {
        // ImageRowNode: 첫 번째 이미지 URL 사용
        if (node.imageUrls.isNotEmpty) {
          final firstUrl = node.imageUrls.first;
          // 🚀 로컬-네트워크 혼용 구조: 로컬 경로인지 확인
          if (firstUrl.isNotEmpty && !EditorService.isNetworkUrl(firstUrl)) {
            previewImageLocalPath = firstUrl;
          } else {
            previewImageUrl = firstUrl;
          }
        }
      } else if (node is PageViewImageNode) {
        // PageViewImageNode: 첫 번째 이미지 URL 사용
        if (node.imageUrls.isNotEmpty) {
          final firstUrl = node.imageUrls.first;
          // 🚀 로컬-네트워크 혼용 구조: 로컬 경로인지 확인
          if (firstUrl.isNotEmpty && !EditorService.isNetworkUrl(firstUrl)) {
            previewImageLocalPath = firstUrl;
          } else {
            previewImageUrl = firstUrl;
          }
        }
      } else if (node is LinkNode) {
        previewImageUrl = node.thumbnailUrl;
      }
    } catch (_) {
      previewImageUrl = null;
      previewImageLocalPath = null;
    }
  }

  void updateDrag(Offset globalPosition, BuildContext context) {
    Map<String, dynamic>? dropInfo;
    dragPosition = globalPosition;
    lastMovedPosition = globalPosition;
    dropInfo = computeDropInfo(globalPosition);

    if (dropInfo != null) {
      if (dropInfo['dropIndex'] != null) {
        final newDropIndex = dropInfo['dropIndex'] as int;
        dropIndex = newDropIndex;
      } else {
        dropIndex = null;
      }
    }

    // computeDropInfo에서 이미 dragMode와 targetNodeId를 설정했으므로
    // dropIndex가 null이고 dragMode도 none일 때만 정리
    if (dropIndex == null && dragMode == DragType.none) {
      targetNodeId = null;
      targetNodeType = null;
    }
    // 그 외의 경우는 computeDropInfo에서 설정한 값을 그대로 사용

    debugPrint('최종 dragMode: $dragMode');
    debugPrint('최종 dropIndex: $dropIndex');
    debugPrint('최종 targetNodeId: $targetNodeId');
    debugPrint('=== updateDrag 끝 ===');

    // 항상 UI 업데이트 (드래그 오버레이 부드러운 이동을 위해)
    notifyListeners();

    // 가장자리 자동 스크롤
    _maybeAutoScroll(context);
  }

  void endDrag() {
    draggingNodeIdNotifier.value = null;
    previewImageUrl = null; // 🎯 이미지 URL 정리
    previewImageLocalPath = null;
    if (draggingNodeId == null) {
      _cleanup();
      return;
    }

    // 이미지 분리 예정이고, 원래 행으로 돌아왔으며 중앙 영역(=reorder) 드롭이면 분리 취소
    if (hasSplitImageInfo) {
      final backToOriginal =
          (targetNodeId != null && targetNodeId == _splitImageRowId) ||
          (_targetRowId != null && _targetRowId == _splitImageRowId);
      if (backToOriginal && dragMode != DragType.imageRowMerge) {
        _ensureSelectionCleared();
        _cleanup();
        return;
      }
    }

    // 이미지 분리 정보가 있으면 먼저 분리 실행
    bool handledBySplitInsertion = false;
    if (hasSplitImageInfo) {
      final rowId = _splitImageRowId;
      final imageIndex = _splitImageIndex;

      if (rowId != null && imageIndex != null) {
        // 🎯 분리 전 노드 존재 확인
        final rowNode = editorService.document.getNodeById(rowId);
        if (rowNode == null || rowNode is! ImageRowNode) {
          debugPrint('[DragService] ⚠️ 분리 대상 행이 존재하지 않음: $rowId');
          _cleanup();
          return;
        }

        // 🎯 이미지 인덱스 범위 확인
        if (imageIndex < 0 || imageIndex >= rowNode.imageUrls.length) {
          debugPrint(
            '[DragService] ⚠️ 이미지 인덱스가 범위를 벗어남: $imageIndex (행 이미지 수: ${rowNode.imageUrls.length})',
          );
          _cleanup();
          return;
        }

        // 🎯 dropIndex 유효성 검증
        final doc = editorService.document;
        final validDropIndex =
            (dropIndex != null && dropIndex! >= 0 && dropIndex! <= doc.length)
                ? dropIndex
                : null;

        // 분리 확정 시점: targetRowId가 있으면 그 행에 삽입, 없으면 기존 로우 근처 단독 삽입
        final splitImageId = editorService.splitImageFromRow(
          rowId,
          imageIndex,
          insertIndex: (dragMode == DragType.reorder) ? validDropIndex : null,
        );
        if (splitImageId != null) {
          draggingNodeId = splitImageId;
          draggingNodeType = editorService.getNodeType(splitImageId);
          handledBySplitInsertion =
              (dragMode == DragType.reorder && dropIndex != null);
          // 🎯 splitImageFromRow() 후 레이아웃이 완전히 업데이트된 후 캐시 무효화
          // 이미지 분리는 레이아웃 변경이 크므로 세 프레임을 기다려서 이미지 로딩 및 레이아웃 완전 안정화
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                invalidateNodeRectCache();
                // 🎯 레이아웃 안정화 후 선택 해제 확인
                _ensureSelectionCleared();
              });
            });
          });
        }
      }
    }

    // 실제 노드 이동 실행
    // 분리하면서 이미 원하는 위치로 삽입한 경우 추가 이동 불필요
    if (handledBySplitInsertion) {
      // 🎯 이미지 분리 후 추가로 한 번 더 셀렉션 클리어 (레이아웃 안정화 후)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            invalidateNodeRectCache();
            _ensureSelectionCleared();
          });
        });
      });
      _ensureSelectionCleared();
      _cleanup();
      return;
    }

    switch (dragMode) {
      case DragType.reorder:
        if (dropIndex != null && draggingNodeId != null) {
          // 🎯 null 체크 후 non-nullable 변수로 할당
          final nodeId = draggingNodeId!;
          final doc = editorService.document;
          final validDropIndex = dropIndex!.clamp(0, doc.length);

          // 🎯 드래그 중인 노드가 여전히 존재하는지 확인
          final draggingNode = doc.getNodeById(nodeId);
          if (draggingNode == null) {
            debugPrint('[DragService] ⚠️ 드래그 중인 노드가 존재하지 않음: $nodeId');
            _cleanup();
            return;
          }

          editorService.reorderNode(nodeId, validDropIndex);
          // 🎯 reorderNode() 후 레이아웃이 완전히 업데이트된 후 캐시 무효화
          // 즉시 무효화하면 레이아웃이 아직 업데이트되지 않아 잘못된 위치를 계산할 수 있음
          // addPostFrameCallback을 사용하여 레이아웃 업데이트 완료 후 캐시 무효화
          // 이미지 노드나 이미지로우 노드는 레이아웃 변경이 크므로 더 많은 프레임을 기다림
          final isImageNode =
              draggingNodeType == NodeType.image ||
              draggingNodeType == NodeType.imageRow;

          if (isImageNode) {
            // 이미지 노드: 세 프레임을 기다려서 이미지 로딩 및 레이아웃 완전 안정화
            WidgetsBinding.instance.addPostFrameCallback((_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  invalidateNodeRectCache();
                  // 🎯 레이아웃 안정화 후 선택 해제 확인
                  _ensureSelectionCleared();
                });
              });
            });
          } else {
            // 텍스트 노드 등: 두 프레임을 기다려서 레이아웃 안정화
            WidgetsBinding.instance.addPostFrameCallback((_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                invalidateNodeRectCache();
                // 🎯 레이아웃 안정화 후 선택 해제 확인
                _ensureSelectionCleared();
              });
            });
          }
        }
        break;
      case DragType.imageRowMerge:
        {
          final String? mergeTargetId = _targetRowId ?? targetNodeId;
          if (mergeTargetId != null && draggingNodeId != null) {
            // 🎯 null 체크 후 non-nullable 변수로 할당
            final nodeId = draggingNodeId!;
            final targetId = mergeTargetId;

            // 🎯 병합 전 노드 존재 확인
            final targetNode = editorService.document.getNodeById(targetId);
            if (targetNode == null) {
              debugPrint('[DragService] ⚠️ 병합 대상 노드가 존재하지 않음: $targetId');
              _cleanup();
              return;
            }

            // 🎯 타겟 노드가 이미지 타입인지 확인
            if (targetNode is! ImageRowNode && targetNode is! ImageNode) {
              debugPrint(
                '[DragService] ⚠️ 병합 대상 노드가 이미지 타입이 아님: ${targetNode.runtimeType}',
              );
              _cleanup();
              return;
            }

            // 🎯 드래그 중인 노드가 여전히 존재하는지 확인
            final draggingNode = editorService.document.getNodeById(nodeId);
            if (draggingNode == null) {
              debugPrint('[DragService] ⚠️ 드래그 중인 노드가 존재하지 않음: $nodeId');
              _cleanup();
              return;
            }

            editorService.mergeImagesIntoRow(
              nodeId,
              targetId,
              isFromLeft: isDraggingFromLeft,
            );
            // 🎯 mergeImagesIntoRow() 후 레이아웃이 완전히 업데이트된 후 캐시 무효화
            // 이미지 병합은 레이아웃 변경이 크므로 두 프레임을 기다려서 안정화
            WidgetsBinding.instance.addPostFrameCallback((_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                invalidateNodeRectCache();
                // 🎯 레이아웃 안정화 후 선택 해제 확인
                _ensureSelectionCleared();
              });
            });
          }
        }
        break;
      case DragType.none:
        break;
    }

    // 🎯 드래그 종료 후 명시적으로 모든 선택 해제
    _ensureSelectionCleared();

    _cleanup();
  }

  /// 🎯 선택 해제를 확실하게 보장하는 헬퍼 메서드
  void _ensureSelectionCleared() {
    imageService?.clearSelection();
    imageService?.clearHighlightedSelection();

    // 🎯 텍스트 선택도 해제
    try {
      editorService.editor.composer.clearSelection();
    } catch (e) {
      debugPrint('[DragService] 텍스트 선택 해제 실패: $e');
    }
  }

  void _cleanup() {
    _stopAutoScroll();
    draggingNodeId = null;
    draggingNodeType = null;
    targetNodeId = null;
    targetNodeType = null;
    dragMode = DragType.none;
    dropIndex = null;
    dragPosition = null;
    lastMovedPosition = null;

    // 분리 정보 초기화
    _splitImageRowId = null;
    _splitImageIndex = null;
    _targetRowId = null;

    // 🎯 cleanup 후에도 선택 해제 확인 (다른 로직에서 선택이 다시 설정되는 경우 대비)
    _ensureSelectionCleared();

    notifyListeners();
  }

  void _maybeAutoScroll(BuildContext context) {
    if (scrollController == null || dragPosition == null) return;
    if (!scrollController!.hasClients) return;

    final bounds = _viewportBounds();
    if (bounds == null) return;
    const edgeMargin = 72.0; // 가장자리 감지 영역
    final pos = dragPosition!;

    double direction = 0.0;
    if (pos.dy < bounds.top + edgeMargin) {
      direction = -1.0; // 위로 스크롤
    } else if (pos.dy > bounds.bottom - edgeMargin) {
      direction = 1.0; // 아래로 스크롤
    }

    if (direction == 0.0) {
      _autoScrollDirection = 0.0;
      _stopAutoScroll();
      return;
    }

    _autoScrollDirection = direction;
    _startAutoScrollTimer(edgeMargin);
  }

  void _startAutoScrollTimer(double edgeMargin) {
    if (_autoScrollTimer != null) return;
    const interval = Duration(milliseconds: 16); // ~60 FPS
    _autoScrollTimer = Timer.periodic(interval, (_) {
      if (scrollController == null || dragPosition == null) {
        _stopAutoScroll();
        return;
      }
      if (!scrollController!.hasClients) {
        _stopAutoScroll();
        return;
      }

      final bounds = _viewportBounds();
      if (bounds == null) {
        _stopAutoScroll();
        return;
      }

      final max = scrollController!.position.maxScrollExtent;
      final min = scrollController!.position.minScrollExtent;
      final current = scrollController!.offset;

      // 속도: 가장자리 근접할수록 빠르게
      final distanceToEdge =
          _autoScrollDirection < 0
              ? (dragPosition!.dy - bounds.top).clamp(0.0, edgeMargin)
              : (bounds.bottom - dragPosition!.dy).clamp(0.0, edgeMargin);
      final proximity = (edgeMargin - distanceToEdge) / edgeMargin; // 0..1
      const maxSpeed = 900.0; // px/s
      const minSpeed = 240.0; // px/s
      final speed = minSpeed + (maxSpeed - minSpeed) * proximity;
      final delta =
          speed * (interval.inMilliseconds / 1000.0) * _autoScrollDirection;

      double next = (current + delta).clamp(min, max);
      if (next == current) {
        _stopAutoScroll();
        return;
      }

      scrollController!.jumpTo(next);

      // 스크롤 후 드롭 인덱스 재계산
      final dropInfo = computeDropInfo(dragPosition!);
      if (dropInfo != null && dropInfo['dropIndex'] != null) {
        dropIndex = dropInfo['dropIndex'] as int;
      }
      notifyListeners();
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  Rect? _viewportBounds() {
    try {
      final position = scrollController?.position;
      final ctx =
          position?.context.notificationContext ??
          position?.context.storageContext;
      if (ctx == null) return null;
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null) return null;
      final topLeft = renderBox.localToGlobal(Offset.zero);
      return topLeft & renderBox.size;
    } catch (_) {
      return null;
    }
  }

  /// 드래그 방향을 계산 (왼쪽에서 오는지 오른쪽에서 오는지)
  bool get isDraggingFromLeft {
    if (dragPosition == null || targetNodeId == null) {
      return true; // 기본값은 왼쪽
    }

    // 타겟 노드의 컴포넌트를 찾아서 그 중앙을 기준으로 판정
    final documentLayout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) return true;

    final component = documentLayout.getComponentByNodeId(targetNodeId!);
    if (component == null) return true;

    final renderBox = component.context.findRenderObject() as RenderBox?;
    if (renderBox == null) return true;

    final targetCenter =
        renderBox.localToGlobal(Offset.zero) +
        Offset(renderBox.size.width / 2, renderBox.size.height / 2);

    final isFromLeft = dragPosition!.dx < targetCenter.dx;

    debugPrint('=== 드래그 방향 계산 ===');
    debugPrint('드래그 위치: ${dragPosition!}');
    debugPrint('타겟 중앙: $targetCenter');
    debugPrint('왼쪽에서 오는가: $isFromLeft');

    return isFromLeft;
  }

  /// 단순한 드롭 인덱스 계산
  Map<String, dynamic>? computeDropInfo(Offset globalPosition) {
    final documentLayout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) return null;

    // 글로벌 좌표를 문서의 로컬 좌표로 변환
    final renderObject =
        editorService.documentLayoutKey?.currentContext?.findRenderObject();
    if (renderObject == null) return null;

    RenderBox? renderBox;
    if (renderObject is RenderSliverToBoxAdapter) {
      renderBox = renderObject.child;
    } else if (renderObject is RenderBox) {
      renderBox = renderObject;
    }
    if (renderBox == null) return null;

    // 🎯 좌표 변환 및 유효성 검증
    Offset localPosition;
    try {
      localPosition = renderBox.globalToLocal(globalPosition);
      // 무한대 또는 NaN 값 체크
      if (!localPosition.dx.isFinite || !localPosition.dy.isFinite) {
        debugPrint('[DragService] ⚠️ 좌표가 유효하지 않음: $localPosition');
        return null;
      }

      // 🎯 문서 영역 범위 체크 및 클램핑
      final documentSize = renderBox.size;
      if (localPosition.dx < 0 ||
          localPosition.dx > documentSize.width ||
          localPosition.dy < 0 ||
          localPosition.dy > documentSize.height) {
        // 범위를 벗어나면 가장자리로 클램핑
        localPosition = Offset(
          localPosition.dx.clamp(0, documentSize.width),
          localPosition.dy.clamp(0, documentSize.height),
        );
        debugPrint('[DragService] 📍 좌표가 문서 범위를 벗어나 클램핑: $localPosition');
      }
    } catch (e) {
      debugPrint('[DragService] ⚠️ globalToLocal 변환 실패: $e');
      return null;
    }

    // 문서 끝 부분 감지를 위한 추가 처리
    final documentLength = editorService.document.length;

    // 🎯 빈 문서 처리
    if (documentLength == 0) {
      return {'dropIndex': 0};
    }

    // SuperEditor의 정확한 위치 계산 (로컬 좌표 사용)
    DocumentPosition? position;
    try {
      position = documentLayout.getDocumentPositionNearestToOffset(
        localPosition,
      );
    } catch (e) {
      debugPrint("DragService에서 getDocumentPositionNearestToOffset 오류: $e");
      return null;
    }

    if (position == null) return null;

    final node = editorService.document.getNodeById(position.nodeId);
    if (node == null) return null;

    // 노드 인덱스 찾기
    final nodeIndex = editorService.document.getNodeIndexById(node.id);
    if (nodeIndex == -1) return null;

    // 마지막 노드인지 확인
    final isLastNode = nodeIndex == documentLength - 1;

    // 타겟 노드 정보 업데이트
    final targetNodeType = editorService.getNodeType(node.id);
    targetNodeId = node.id;
    this.targetNodeType = targetNodeType;

    // 드래그 모드 결정
    // 이미지/이미지Row끼리일 때에도, 타겟의 좌/우 가장자리 근처에서만 병합 모드로 진입
    // 그 외 대부분 영역에서는 reorder가 되도록 한다.
    const double horizontalMergeEdgePx = 30.0; // 좌/우 가장자리 감지 폭

    if ((targetNodeType == NodeType.image ||
            targetNodeType == NodeType.imageRow) &&
        (draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.imageRow) &&
        draggingNodeId != node.id) {
      // 문서 좌표계에서 타겟 노드의 사각형을 구해 좌/우 에지 근처인지 판단
      final Rect? targetRect = documentLayout.getRectForPosition(position);

      bool nearHorizontalEdge = false;
      if (targetRect != null) {
        final double leftEdge = targetRect.left + horizontalMergeEdgePx;
        final double rightEdge = targetRect.right - horizontalMergeEdgePx;
        // localPosition은 동일 좌표계(문서 좌표) 기준
        nearHorizontalEdge =
            localPosition.dx <= leftEdge || localPosition.dx >= rightEdge;
      }

      // 병합 모드 점착성 유지: 한 번 병합 모드에 들어가면 드래그가 끝날 때까지 유지
      // 🎯 단, 타겟 노드 타입이 여전히 이미지인지 재확인
      if (dragMode == DragType.imageRowMerge) {
        // 병합 모드 유지 전 타겟 노드 타입 재확인
        if (targetNodeType != NodeType.image &&
            targetNodeType != NodeType.imageRow) {
          // 타겟이 이미지가 아니면 reorder 모드로 전환
          dragMode = DragType.reorder;
        } else {
          dragMode = DragType.imageRowMerge;
        }
      } else if (nearHorizontalEdge) {
        dragMode = DragType.imageRowMerge;
      } else {
        dragMode = DragType.reorder;
      }
    } else {
      dragMode = DragType.reorder;
    }

    // 드롭 인덱스 계산
    // 🎯 draggingNodeId null 체크 강화 (null assertion 제거)
    int? draggingNodeIndex;
    if (draggingNodeId != null) {
      // null 체크 후 non-nullable 변수로 할당
      final nodeId = draggingNodeId!;
      draggingNodeIndex = editorService.document.getNodeIndexById(nodeId);
    } else {
      // draggingNodeId가 null이면 일반 삽입 모드로 처리
      draggingNodeIndex = -1;
    }

    int? finalCandidate = nodeIndex;

    // 마지막 노드 처리
    if (isLastNode) {
      // 마지막 노드인 경우, 노드의 중간을 기준으로 위/아래 판단
      final Rect? targetRect = documentLayout.getRectForPosition(position);
      if (targetRect != null) {
        final nodeCenter = targetRect.center.dy;
        if (localPosition.dy > nodeCenter) {
          // 마지막 노드 아래쪽에 드롭 - 문서 끝에 삽입
          finalCandidate = documentLength;
        } else {
          // 마지막 노드 위쪽에 드롭 - 마지막 노드 앞에 삽입
          finalCandidate = nodeIndex;
        }
      } else {
        // targetRect를 가져올 수 없는 경우, 기본적으로 마지막 노드 앞에 삽입
        finalCandidate = nodeIndex;
      }
    } else if (draggingNodeId != null) {
      if (draggingNodeIndex != -1) {
        final bool isSplitDrag = hasSplitImageInfo; // 이미지 행에서 개별 이미지 분리 드래그 중인지

        if (isSplitDrag) {
          // 분리 드래그: 타겟 노드의 위/아래를 정확히 판단
          final Rect? targetRect = documentLayout.getRectForPosition(position);
          if (targetRect != null) {
            final nodeCenter = targetRect.center.dy;
            if (localPosition.dy < nodeCenter) {
              // 타겟 노드 위쪽에 드롭 - 타겟 노드 앞에 삽입
              finalCandidate = nodeIndex;
            } else {
              // 타겟 노드 아래쪽에 드롭 - 타겟 노드 뒤에 삽입
              finalCandidate = nodeIndex + 1;
            }
          } else {
            // targetRect를 가져올 수 없는 경우, 기본적으로 타겟 노드 앞에 삽입
            finalCandidate = nodeIndex;
          }
        } else {
          // 일반 드래그: 자기 자신과 바로 이웃한 위치 차단
          // 🎯 자기 자신 바로 위/아래로는 드롭 불가 (라인 숨김)
          if (nodeIndex == draggingNodeIndex) {
            // 자기 자신 위치
            finalCandidate = null;
          } else if (nodeIndex == draggingNodeIndex + 1) {
            // 자기 자신 바로 아래 위치
            finalCandidate = null;
          } else if (nodeIndex == draggingNodeIndex - 1) {
            // 자기 자신 바로 위 위치 (드래그 노드가 타겟 노드 바로 아래)
            // 이 경우 타겟 노드 위에 삽입하는 것이므로 허용
            finalCandidate = nodeIndex;
          } else if (draggingNodeIndex < nodeIndex) {
            // 드래그 중인 노드가 타겟 노드보다 앞에 있으면, 타겟 노드 앞에 삽입
            finalCandidate = nodeIndex;
          } else {
            // 드래그 중인 노드가 타겟 노드보다 뒤에 있으면, 타겟 노드 앞에 삽입
            finalCandidate = nodeIndex;
          }
        }
      }
    } else {
      finalCandidate = nodeIndex;
    }

    // 맨 위 삽입을 위한 특별 처리
    // 첫 행(타이틀 아래) 배치 허용: 타이틀을 건드리지 않되, 그 아래로는 허용
    // finalCandidate가 0이면 이후 타이틀 보정에서 +1 처리됨

    // 타이틀 고정: 타이틀(isTitle=true) 위로는 드롭 불가 → 항상 타이틀 바로 아래로 보정
    try {
      if (finalCandidate != null) {
        final doc = editorService.document;
        // 🎯 문서에 노드가 있는지 확인
        if (doc.nodeCount > 0) {
          int titleIndex = -1;
          final n = doc.getNodeAt(0);
          if (n is ParagraphNode && (n.metadata['isTitle'] == true)) {
            titleIndex = 0;
          }
          // 타이틀 바로 아래로 최소 보정. 타이틀 없으면 보정 생략
          if (titleIndex != -1 && finalCandidate <= titleIndex) {
            finalCandidate = titleIndex + 1;
          }
        }
      }
    } catch (e) {
      debugPrint('[DragService] ⚠️ 타이틀 노드 체크 중 오류: $e');
    }

    // 가로배치 모드일 때는 dropIndex를 null로 설정 (가로라인 표시 안함)
    if (dragMode == DragType.imageRowMerge) {
      finalCandidate = null;
    }

    // 분리 취소 감지(원래 행 + 중앙 영역) 시에도 드롭 라인을 표시하지 않음
    if (hasSplitImageInfo &&
        targetNodeId == _splitImageRowId &&
        dragMode == DragType.reorder) {
      finalCandidate = null;
    }

    // 디버그 로그
    /*
    debugPrint('=== 드롭 인덱스 계산 ===');
    debugPrint(
      '드래그 중인 노드: $draggingNodeId (인덱스: ${draggingNodeId != null ? getNodeIndex(draggingNodeId!) : -1})',
    );
    debugPrint('최종 드롭 인덱스: $finalCandidate');
    debugPrint('드래그 모드: $dragMode');
    */

    // 이미지 행 타겟에 대한 삽입 인덱스 계산 (분리/병합 판단에 활용)
    if (targetNodeType == NodeType.imageRow) {
      _targetRowId = node.id;
      // targetRect와 로컬 X로 삽입 위치 추정
      try {
        final Rect? targetRect = documentLayout.getRectForPosition(position);
        // rowNode 정보 없이도 좌표 기반으로 삽입 슬롯 계산 (폭 기준 균등 분할)
        if (targetRect != null) {
          final double localXWithinTarget = localPosition.dx - targetRect.left;
          const int slots = 8; // 보수적 기본 슬롯 수 (필요 시 컴포넌트에서 전달하도록 개선)
          final double slotW = (targetRect.width / slots).clamp(
            1.0,
            targetRect.width,
          );
          int idx = (localXWithinTarget / slotW).floor();
          idx = idx.clamp(0, slots - 1);
        }
      } catch (_) {}
    } else {
      _targetRowId = null;
    }

    // 🎯 빈 문단 자동 삭제를 고려한 드롭 인덱스 조정
    if (finalCandidate != null) {
      // 빈 문단을 건너뛰어 실제 삽입될 위치 계산
      final adjustedIndex = _adjustDropIndexForEmptyParagraphs(
        finalCandidate,
        documentLength,
      );

      // 범위 검증
      final validDropIndex = adjustedIndex.clamp(0, documentLength);
      if (validDropIndex != finalCandidate) {
        debugPrint(
          '[DragService] 📍 dropIndex 조정: $finalCandidate -> $validDropIndex (빈 문단 고려)',
        );
      }
      return {'dropIndex': validDropIndex};
    }

    return {'dropIndex': null};
  }

  /// 노드 ID로 현재 노드의 인덱스 찾기
  int getNodeIndex(String nodeId) {
    return editorService.document.getNodeIndexById(nodeId);
  }

  /// 🎯 빈 문단 자동 삭제를 고려한 드롭 인덱스 조정
  /// 빈 문단 위/아래로 드롭할 때, 드롭 후 빈 문단이 삭제되면
  /// 실제 삽입 위치가 예상과 다를 수 있으므로 미리 조정
  int _adjustDropIndexForEmptyParagraphs(
    int candidateIndex,
    int documentLength,
  ) {
    if (candidateIndex < 0 || candidateIndex > documentLength) {
      return candidateIndex;
    }

    final doc = editorService.document;

    // 🎯 드롭 위치 바로 위에 빈 문단이 있으면 건너뛰기
    // (빈 문단 위로 드롭하면 빈 문단이 삭제되고 그 위치에 삽입됨)
    if (candidateIndex > 0) {
      final prevNode = doc.getNodeAt(candidateIndex - 1);
      if (prevNode != null && NodeTypeChecker.isEmptyParagraph(prevNode)) {
        // 빈 문단 위로 드롭하는 경우, 빈 문단 위치로 조정
        return candidateIndex - 1;
      }
    }

    // 🎯 드롭 위치에 빈 문단이 있으면 그대로 유지
    // (빈 문단 위로 드롭하면 빈 문단이 삭제되고 그 위치에 삽입되므로
    //  빈 문단 위치가 실제 삽입 위치가 됨 - 조정 불필요)
    if (candidateIndex < documentLength) {
      final currentNode = doc.getNodeAt(candidateIndex);
      if (currentNode != null &&
          NodeTypeChecker.isEmptyParagraph(currentNode)) {
        // 빈 문단 위치로 드롭하는 경우, 그대로 유지 (빈 문단이 삭제되고 그 위치에 삽입)
        return candidateIndex;
      }
    }

    return candidateIndex;
  }

  /// ClipNode 클릭 처리 - 버튼 영역 판단 및 액션 반환
  String? handleClipNodeTap(String nodeId, Offset globalTapPosition) {
    final nodeRect = getNodeGlobalRect(nodeId);
    if (nodeRect == null) {
      debugPrint('[DragService] ClipNode: nodeRect가 null입니다');
      return null;
    }

    final localTap = Offset(
      globalTapPosition.dx - nodeRect.left,
      globalTapPosition.dy - nodeRect.top,
    );

    // 화면 가로 너비 (SuperEditor context 필요)
    final screenWidth = 400.0; // TODO: 실제 화면 너비 전달

    // 우측 하단 음소거 버튼 영역 확대 (하단 모서리까지)
    final muteButtonSize = 66.0; // 버튼 영역을 더 크게
    final buttonRight = screenWidth;
    final buttonLeft = buttonRight - muteButtonSize;
    final buttonBottom = nodeRect.height;
    final buttonTop = buttonBottom - muteButtonSize;

    debugPrint(
      '[DragService] ClipNode: nodeRect=$nodeRect, localTap=$localTap',
    );
    debugPrint(
      '[DragService] ClipNode: Button area: left=$buttonLeft, right=$buttonRight, top=$buttonTop, bottom=$buttonBottom',
    );

    final isMuteButtonArea =
        localTap.dx > buttonLeft &&
        localTap.dx < buttonRight &&
        localTap.dy > buttonTop &&
        localTap.dy < buttonBottom;

    debugPrint('[DragService] ClipNode: isMuteButtonArea=$isMuteButtonArea');

    if (isMuteButtonArea) {
      debugPrint('[DragService] ClipNode: 음소거 버튼 클릭!');
      return 'toggleMute';
    }

    // 중앙 다시보기 버튼 영역 체크
    final isCenterArea =
        localTap.dx > (screenWidth / 2 - 100) &&
        localTap.dx < (screenWidth / 2 + 100) &&
        localTap.dy > (nodeRect.height / 2 - 25) &&
        localTap.dy < (nodeRect.height / 2 + 25);

    debugPrint('[DragService] ClipNode: isCenterArea=$isCenterArea');

    if (isCenterArea) {
      // 비디오가 끝났는지 확인
      final clipNode = editorService.document.getNodeById(nodeId);
      if (clipNode is ClipNode) {
        final key = 'video_${clipNode.url.hashCode}';
        final controller = videoPlayerControllers[key];

        // 비디오가 완전히 끝났을 때만 다시보기 버튼 반응
        if (controller?.hasPlayedOnce != null && controller!.hasPlayedOnce!()) {
          debugPrint('[DragService] ClipNode: 다시보기 버튼 클릭!');
          return 'restartVideo';
        } else {
          debugPrint('[DragService] ClipNode: 비디오가 아직 끝나지 않음');
          return null;
        }
      }

      debugPrint('[DragService] ClipNode: 다시보기 버튼 클릭!');
      return 'restartVideo';
    }

    debugPrint('[DragService] ClipNode: 일반 영역 클릭');
    return null;
  }

  /// 모든 비디오 일시정지
  void _pauseAllVideos() {
    for (final entry in videoPlayerControllers.entries) {
      final controller = entry.value;
      if (controller.pause != null) {
        controller.pause!();
        debugPrint('[DragService] 비디오 일시정지: ${entry.key}');
      }
    }
  }
}
