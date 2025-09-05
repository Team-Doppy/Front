import 'package:flutter/material.dart';

/// 이미지 상태를 관리하는 서비스
class ImageService extends ChangeNotifier {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  // 현재 선택된 이미지 정보
  String? _selectedImageId;

  // Getters
  String? get selectedImageId => _selectedImageId;

  bool get hasSelectedImage => _selectedImageId != null;

  /// 이미지 선택
  void selectImage(String imageId) {
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
}
