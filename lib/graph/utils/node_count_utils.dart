/// 노드 개수에 따른 확대 모드
/// - 1개: 최대축소, 줌2만 (프레지 불가)
/// - 2~10개: 최대축소 - 줌2 - 프레지 (줌1 단계 없음)
/// - 11개 이상: 최대축소 - 줌1 - 줌2 - 프레지
enum ZoomMode { minZoom2Only, minZoom2Prezi, full }

/// 줌 배율 구간 (노드 수 상한, zoom1 배율, zoom2 배율)
/// 한 곳에서 구간·배율 정의 → zoom1Multiplier/zoom2Multiplier에서 사용
class _ZoomTier {
  const _ZoomTier(this.maxNodes, this.zoom1, this.zoom2);
  final int maxNodes;
  final double zoom1;
  final double zoom2;
}

/// 노드 개수에 따른 동적 값들 (lodThreshold 4등분)
class NodeCountUtils {
  NodeCountUtils._();

  static const int lodThreshold = 50;

  /// 대량 그래프(노드 수 많을 때) 최소 줌에서 그릴 최대 노드 수 (버벅임 방지)
  static int maxLodNodesAtMinZoom(int nodeCount) {
    if (nodeCount <= 80) return lodThreshold;
    if (nodeCount <= 150) return 45;
    return 40;
  }

  static int _q(int i) => (lodThreshold * i / 4).round();

  // --- 줌 모드·배율: 4구간만 사용 (가독성·유지보수용 단일 정의) ---
  // 1개 | 2~10 | 11~19 | 20+
  static const List<_ZoomTier> _zoomTiers = [
    _ZoomTier(1, 1.25, 2.0), // minZoom2Only, 현행 유지
    _ZoomTier(10, 1.2, 1.8), // minZoom2Prezi, 배율 많이 줄임
    _ZoomTier(19, 1.45, 3.0), // full, 배율 좀 줄임
    _ZoomTier(999999, 1.55, 3.5), // 20+, 현행 유지
  ];

  static _ZoomTier _zoomTierFor(int n) {
    for (final t in _zoomTiers) {
      if (n <= t.maxNodes) return t;
    }
    return _zoomTiers.last;
  }

  /// 노드 수에 따른 확대 모드
  static ZoomMode zoomMode(int n) {
    if (n <= 1) return ZoomMode.minZoom2Only;
    if (n <= 10) return ZoomMode.minZoom2Prezi;
    return ZoomMode.full;
  }

  /// 프레지(노드 포커스 줌인) 허용 여부. 1개일 때는 불가.
  static bool preziAllowed(int n) => n > 1;

  /// 줌1 단계 사용 여부. 10개 초과일 때만 적용.
  static bool hasZoom1Step(int n) => n > 10;

  /// 줌1 단계 배율 (minScale 대비). _zoomTiers 기준.
  static double zoom1Multiplier(int n) => _zoomTierFor(n).zoom1;

  /// 줌2(최대 핀치) 단계 배율 (minScale 대비). _zoomTiers 기준.
  static double zoom2Multiplier(int n) => _zoomTierFor(n).zoom2;

  static double fitMargin(int n) {
    if (n <= _q(1)) return 64;
    if (n <= _q(2)) return 56;
    if (n <= _q(3)) return 48;
    if (n <= _q(4)) return 40;
    return 32;
  }

  static int effectiveCountForRendering(int n) {
    if (n <= lodThreshold) return n;
    return lodThreshold;
  }

  /// 씬 기준 반지름. 노드 수가 적을수록 크게, 30개 이상부터는 더 작게.
  /// 0~1개: 가운데 노드 하나 표시용으로 약 50px 직경(반지름 25).
  static double nodeRadius(int n) {
    if (n <= 1) return 10.0;
    if (n <= 5) return 60.0;
    if (n <= 12) return 50.0;
    if (n <= 22) return 28.0;
    if (n <= 40) return 22.0;
    if (n <= _q(2)) return 18.0;
    if (n <= _q(3)) return 16.0;
    if (n <= _q(4)) return 15.0;
    return 14.0;
  }

  static double strokeWidthFactor(int n) {
    if (n <= _q(1)) return 1.2;
    if (n <= _q(2)) return 1.0;
    if (n <= _q(3)) return 0.9;
    if (n <= _q(4)) return 0.8;
    return 0.7;
  }

  /// 노드 수에 따른 라벨 폰트 크기. 적을수록 크게, 많을수록 작게 (가독성·밀도)
  static double labelFontSize(int n) {
    if (n <= 1) return 38.0;
    if (n <= 5) return 100.0;
    if (n <= 12) return 80.0;
    if (n <= 22) return 50.0;
    if (n <= 40) return 35.0;

    return 40.0;
  }
}
