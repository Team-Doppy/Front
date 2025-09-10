import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 이미지 상태를 관리하는 서비스
class ImageService extends ChangeNotifier {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  // 현재 선택된 이미지 정보
  String? _selectedImageId;
  // 편집된 이미지 바이트 저장소 (nodeId -> bytes)
  final Map<String, Uint8List> _editedBytesByNodeId = <String, Uint8List>{};

  // Getters
  String? get selectedImageId => _selectedImageId;
  Uint8List? getEditedBytes(String nodeId) => _editedBytesByNodeId[nodeId];

  bool get hasSelectedImage => _selectedImageId != null;

  /// 이미지 선택
  void selectImage(String? imageId) {
    if (imageId == _selectedImageId) {
      // 이미지 선택 취소
      _selectedImageId = null;
    } else {
      _selectedImageId = imageId;
    }

    notifyListeners();
  }

  /// 선택 상태 해제
  void clearSelection() {
    _selectedImageId = null;
    notifyListeners();
  }

  /// 편집 결과 반영: 해당 이미지 노드에 편집된 바이트를 저장한다
  void applyEditedBytes({required String nodeId, required Uint8List bytes}) {
    _editedBytesByNodeId[nodeId] = bytes;
    notifyListeners();
  }

  /// 편집 결과 제거(원본으로 복귀)
  void clearEditedBytes(String nodeId) {
    if (_editedBytesByNodeId.remove(nodeId) != null) {
      notifyListeners();
    }
  }
}
