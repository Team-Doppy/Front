import 'package:flutter/material.dart';

/// 그래프 뷰의 카메라만 담당. layout 좌표계만 다룸 (spread/warp 없음).
///
/// - [pan], [zoomTo], [setTransform]로 즉시 반영
/// - [animateTo]로 스냅/복귀 시 부드럽게 이동
/// - InteractiveViewer 없이 단일 Matrix로 제어해 재계산 충돌 제거
class GraphCameraController extends ChangeNotifier {
  GraphCameraController({required TickerProvider vsync})
      : _vsync = vsync,
        _matrix = Matrix4.identity() {
    _animController = AnimationController(
      vsync: _vsync,
      duration: const Duration(milliseconds: 400),
    )..addListener(_onAnimTick);
  }

  final TickerProvider _vsync;
  final Matrix4 _matrix;
  late final AnimationController _animController;
  Animation<Matrix4>? _anim;

  Matrix4 get value => Matrix4.copy(_matrix);
  double get scale => _matrix.getMaxScaleOnAxis();
  Offset get translation => Offset(_matrix.storage[12], _matrix.storage[13]);

  bool get isAnimating => _animController.isAnimating;

  void stopAnimation() {
    if (_animController.isAnimating) {
      _animController.stop();
      _anim = null;
    }
  }

  void _onAnimTick() {
    final a = _anim;
    if (a != null) {
      _matrix.setFrom(a.value);
      notifyListeners();
    }
  }

  /// 즉시 변환 설정 (애니메이션 없음)
  void setTransform(Matrix4 m) {
    _matrix.setFrom(m);
    notifyListeners();
  }

  /// pan: translation만 이동 (scale 유지)
  void pan(Offset delta) {
    _matrix.storage[12] += delta.dx;
    _matrix.storage[13] += delta.dy;
    notifyListeners();
  }

  /// focal 지점을 화면에서 고정한 채 scale만 변경
  void zoomTo(double newScale, Offset focalLocal, Size screenSize) {
    final s = scale;
    if (s <= 0) return;
    final tx = _matrix.storage[12];
    final ty = _matrix.storage[13];
    final sceneX = (focalLocal.dx - tx) / s;
    final sceneY = (focalLocal.dy - ty) / s;
    final newTx = focalLocal.dx - sceneX * newScale;
    final newTy = focalLocal.dy - sceneY * newScale;
    _matrix.setIdentity();
    _matrix.storage[0] = newScale;
    _matrix.storage[5] = newScale;
    _matrix.storage[10] = newScale;
    _matrix.storage[12] = newTx;
    _matrix.storage[13] = newTy;
    notifyListeners();
  }

  /// 현재 matrix를 기준으로 target Matrix까지 애니메이션
  void animateTo(
    Matrix4 target, {
    Curve curve = Curves.easeOutCubic,
    Duration? duration,
  }) {
    if (_animController.isAnimating) _animController.stop();
    if (duration != null) _animController.duration = duration;
    _anim = Matrix4Tween(begin: value, end: target).animate(
      CurvedAnimation(parent: _animController, curve: curve),
    );
    _animController
      ..reset()
      ..forward();
  }

  /// 애니메이션 종료 시 정리 (애니 완료 시 호출해도 됨)
  void disposeAnim() {
    _animController.removeListener(_onAnimTick);
    _animController.dispose();
  }

  /// local 좌표 → scene(layout) 좌표. scale·translation만 적용.
  Offset toScene(Offset local) {
    final s = scale;
    if (s <= 0) return local;
    return Offset(
      (local.dx - _matrix.storage[12]) / s,
      (local.dy - _matrix.storage[13]) / s,
    );
  }
}
