/// 홈 인삿말(홈 텍스트) 모델
/// ✅ 서버에서 인사말 2줄을 받아서 사용
class HomeGreetingChunk {
  final String text;
  final bool bold;

  const HomeGreetingChunk(this.text, {this.bold = false});
}

class HomeGreetingMessage {
  final List<HomeGreetingChunk> line1;
  final List<HomeGreetingChunk> line2;

  const HomeGreetingMessage({required this.line1, required this.line2});
}
