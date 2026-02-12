/// 노드 개수에 따른 동적 값들 (lodThreshold 4등분)
class NodeCountUtils {
  NodeCountUtils._();

  static const int lodThreshold = 70;

  static int _q(int i) => (lodThreshold * i / 4).round();

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

  /// 씬 기준 반지름. 노드 수가 적을수록 최대축소에서 더 크게 보이도록.
  static double nodeRadius(int n) {
    if (n <= 5) return 26.0;
    if (n <= 12) return 22.0;
    if (n <= 22) return 19.0;
    if (n <= _q(1)) return 17.0;
    if (n <= _q(2)) return 16.0;
    if (n <= _q(3)) return 15.0;
    if (n <= _q(4)) return 15.0;
    return 15.0;
  }

  static double strokeWidthFactor(int n) {
    if (n <= _q(1)) return 1.2;
    if (n <= _q(2)) return 1.0;
    if (n <= _q(3)) return 0.9;
    if (n <= _q(4)) return 0.8;
    return 0.7;
  }
}
