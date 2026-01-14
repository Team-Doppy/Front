import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/data/models/post_data.dart';

/// 블러 오버레이 타입
enum BlurOverlayType {
  longPress, // 길게 누르기 미리보기
  weekPostList, // 주차별 포스트 리스트
}

/// 전역 블러 오버레이 상태 관리 Provider
class BlurOverlayProvider with ChangeNotifier {
  BlurOverlayType? _overlayType;
  int? _longPressedWeek;
  int? _longPressedYear;
  Offset? _longPressPosition;
  Offset? _cellStartPosition; // 셀의 시작 위치 (Hero 애니메이션용)
  AnimationController? _animationController;
  List<PostData>? _filteredPosts; // 필터링된 포스트 리스트

  BlurOverlayType? get overlayType => _overlayType;
  int? get longPressedWeek => _longPressedWeek;
  int? get longPressedYear => _longPressedYear;
  Offset? get longPressPosition => _longPressPosition;
  Offset? get cellStartPosition => _cellStartPosition;
  AnimationController? get animationController => _animationController;
  List<PostData>? get filteredPosts => _filteredPosts;

  /// 블러 오버레이 표시 (길게 누르기 미리보기)
  void showBlurOverlay({
    required int weekNumber,
    required int year,
    Offset? position,
    Offset? cellStartPosition,
    required AnimationController controller,
  }) {
    _overlayType = BlurOverlayType.longPress;
    _longPressedWeek = weekNumber;
    _longPressedYear = year;
    _longPressPosition = position;
    _cellStartPosition = cellStartPosition ?? position;
    _animationController = controller;
    notifyListeners();
  }

  /// 주차별 포스트 리스트 오버레이 표시
  void showWeekPostListOverlay({
    required int weekNumber,
    required int year,
    required AnimationController controller,
    List<PostData>? filteredPosts,
  }) {
    _overlayType = BlurOverlayType.weekPostList;
    _longPressedWeek = weekNumber;
    _longPressedYear = year;
    _longPressPosition = null;
    _cellStartPosition = null;
    _animationController = controller;
    _filteredPosts = filteredPosts;
    notifyListeners();
  }

  /// 블러 오버레이 업데이트 (손가락 위치만 변경)
  void updateBlurPosition(Offset? position) {
    _longPressPosition = position;
    notifyListeners();
  }

  /// 블러 오버레이 숨기기
  void hideBlurOverlay() {
    _overlayType = null;
    _longPressedWeek = null;
    _longPressedYear = null;
    _longPressPosition = null;
    _cellStartPosition = null;
    _animationController = null;
    _filteredPosts = null;
    notifyListeners();
  }

  /// 블러 오버레이 활성화 여부
  bool get isVisible => _overlayType != null;
}
