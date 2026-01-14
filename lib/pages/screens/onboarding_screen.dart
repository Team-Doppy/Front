import 'package:doppy/pages/screens/join_screen.dart';
import 'package:doppy/pages/screens/find_id_screen.dart';
import 'package:doppy/pages/screens/splash_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:math' as math;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _typingController;
  late AnimationController _fadeController;

  // 로그인 필드 컨트롤러
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _loginPasswordFocusNode = FocusNode();

  // 비밀번호 표시 여부
  bool _obscurePassword = true;
  bool _isLoggingIn = false;
  bool _isFadingOut = false; // 로고 페이드아웃 상태

  @override
  void initState() {
    super.initState();
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400), // 느린 회전
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _typingController.dispose();
    _fadeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _loginPasswordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 키보드가 올라왔는지 확인
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // 여백을 누르면 키보드 내리기
            if (isKeyboardVisible) {
              FocusScope.of(context).unfocus();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Spacer(flex: 2),

              // Doppy 로딩 로고 스타일 제목 - 키보드 올라올 때 또는 로그인 중일 때 숨기기
              AnimatedOpacity(
                opacity: (isKeyboardVisible || _isFadingOut) ? 0.0 : 1.0,
                duration:
                    _isFadingOut
                        ? const Duration(milliseconds: 150) // 페이드아웃은 더 빠르게
                        : const Duration(milliseconds: 300),
                curve: _isFadingOut ? Curves.easeOut : Curves.easeInOut,
                child: AnimatedContainer(
                  duration:
                      _isFadingOut
                          ? const Duration(milliseconds: 150)
                          : const Duration(milliseconds: 300),
                  curve: _isFadingOut ? Curves.easeOut : Curves.easeInOut,
                  transform: Matrix4.translationValues(
                    0,
                    (isKeyboardVisible || _isFadingOut) ? -50 : 0,
                    0,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedBuilder(
                      animation: _typingController,
                      builder: (context, child) {
                        return _buildTitleText(
                          context,
                          "doppy",
                          ValueKey("doppy"),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // 로그인 입력 필드
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    // UserId 입력 필드
                    TextField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      cursorColor: Theme.of(context).colorScheme.onSurface,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 18,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: context.tr('login_id_hint'),
                        hintStyle: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(1),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 30,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: Icon(
                          Icons.alternate_email_rounded,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                          size: 20,
                        ),
                      ),
                      onChanged: (_) {
                        setState(() {}); // 버튼 활성화 상태 업데이트
                      },
                      onSubmitted: (_) {
                        FocusScope.of(
                          context,
                        ).requestFocus(_loginPasswordFocusNode);
                      },
                    ),

                    const SizedBox(height: 6),

                    // Password 입력 필드
                    TextField(
                      controller: _passwordController,
                      focusNode: _loginPasswordFocusNode,
                      obscureText: _obscurePassword,
                      cursorColor: Theme.of(context).colorScheme.onSurface,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 18,
                      ),
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 30,
                        ),
                        hintText: context.tr('password_hint'),
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                          ),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                          ),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                          ),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.lock_outline_rounded
                                : Icons.lock_open_outlined,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.5),
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      onChanged: (_) {
                        setState(() {}); // 버튼 활성화 상태 업데이트
                      },
                      onSubmitted: (_) {
                        if (_emailController.text.trim().isNotEmpty &&
                            _passwordController.text.isNotEmpty &&
                            !_isLoggingIn) {
                          _handleLogin();
                        }
                      },
                    ),
                  ],
                ),
              ),

              // 아이디/비밀번호 찾기 링크 - 키보드 올라올 때 숨기기
              AnimatedOpacity(
                opacity: isKeyboardVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,

                  child: Center(
                    child: GestureDetector(
                      onTap: () async {
                        // 키보드 먼저 내리기
                        FocusScope.of(context).unfocus();
                        // FindIdScreen으로 이동하고 돌아올 때까지 대기
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const FindIdScreen(),
                          ),
                        );
                        // 돌아왔을 때 키보드가 내린 상태로 유지
                        FocusScope.of(context).unfocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Text(
                          context.tr('forgot_id_password'),
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // 로그인 버튼 - 키보드 올라올 때 숨기기
              AnimatedOpacity(
                opacity: isKeyboardVisible ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  transform: Matrix4.translationValues(
                    0,
                    isKeyboardVisible ? 50 : 0,
                    0,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 75),
                    child: SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40),
                          ),
                          backgroundColor:
                              (_emailController.text.trim().isNotEmpty &&
                                      _passwordController.text.isNotEmpty &&
                                      !_isLoggingIn)
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.grey[400],
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        onPressed:
                            (_emailController.text.trim().isNotEmpty &&
                                    _passwordController.text.isNotEmpty &&
                                    !_isLoggingIn)
                                ? _handleLogin
                                : null,
                        child:
                            _isLoggingIn
                                ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                )
                                : Text(
                                  context.tr('login_button'),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        (_emailController.text
                                                    .trim()
                                                    .isNotEmpty &&
                                                _passwordController
                                                    .text
                                                    .isNotEmpty &&
                                                !_isLoggingIn)
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.surface
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                                .withOpacity(0.7),
                                  ),
                                ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Sign up 링크 - 키보드 올라올 때 숨기기
              AnimatedOpacity(
                opacity: isKeyboardVisible ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  transform: Matrix4.translationValues(
                    0,
                    isKeyboardVisible ? 50 : 0,
                    0,
                  ),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        // 🎯 Material page push 방식으로 회원가입 화면 이동
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (context) =>
                                    JoinScreen(skipModeSelection: true),
                          ),
                        );
                      },

                      child: Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Text(
                          context.tr('signup_link'),
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    // 로고 즉시 페이드아웃
    setState(() {
      _isFadingOut = true;
      _isLoggingIn = true;
    });

    // 페이드아웃 애니메이션 완료 대기
    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted) return;

    final username = _emailController.text.trim();
    final password = _passwordController.text;
    final region = context.read<LocaleProvider>().regionCode;

    final success = await AuthProvider().login(
      username,
      password,
      region: region,
    );

    if (!mounted) return;

    if (success) {
      // 로그인 후 스플래시로 부드럽게 페이드 전환
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SplashScreen(),
          transitionDuration: const Duration(milliseconds: 250), // 더 빠르게
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut, // 더 빠른 전환
              ),
              child: child,
            );
          },
        ),
        (route) => false,
      );
    } else {
      // 로그인 실패 시 페이드아웃 상태 해제
      setState(() {
        _isFadingOut = false;
        _isLoggingIn = false;
      });
      ErrorHandler.showError(
        context,
        context.tr('login_failed_invalid_credentials'),
      );
    }
  }

  // Doppy 로딩 로고 스타일 제목 (o에 스핀)
  Widget _buildTitleText(BuildContext context, String text, Key key) {
    return Container(
      key: key,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "D"
          Text(
            "D",
            style: TextStyle(
              fontSize: 53,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: -2,
            ),
          ),

          // "o" - 회전하는 스피너 (Painter 사용)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: 34,
              height: 34,
              child: CustomPaint(
                painter: _DoppyOSpinnerPainter(
                  progress: _typingController.value,
                  color: Theme.of(context).colorScheme.primary,
                  strokeWidth: 8,
                ),
              ),
            ),
          ),
          // "ppy"
          Text(
            "ppy",
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedORing extends StatefulWidget {
  final double size;
  const AnimatedORing({this.size = 80, super.key});

  @override
  _AnimatedORingState createState() => _AnimatedORingState();
}

class _AnimatedORingState extends State<AnimatedORing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: ORingPainter(_controller.value),
          size: Size(widget.size, widget.size),
        );
      },
    );
  }
}

class ORingPainter extends CustomPainter {
  final double t; // 0~1
  ORingPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    // 기본 링 (연한 베이스)
    final basePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = Colors.grey.withOpacity(0.25);
    canvas.drawCircle(center, radius - 5, basePaint);

    // 메인 컬러의 hue를 시간에 따라 회전시키기
    final baseHue = (t * 360) % 360;
    Color _h(double h, double s, double v) =>
        HSVColor.fromAHSV(1, (h % 360), s, v).toColor();

    // sweep을 살짝 숨쉬듯 변화 (0.6π ~ 1.0π)
    final sweep = math.pi * (0.6 + 0.4 * math.sin(2 * math.pi * t)); // rad

    // 기본 시작각 (시간에 따라 한 바퀴 회전)
    final startAngle = 2 * math.pi * t;

    final rect = Rect.fromCircle(center: center, radius: radius - 5);

    // 여러 개의 라이트 스트로크를 겹쳐서 역동감 Up
    for (int i = 0; i < 3; i++) {
      final localT = (t + i * 0.25) % 1.0;
      final hue = baseHue + i * 40;

      final paint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                6 -
                i
                    .toDouble() // 바깥에서 안쪽으로 살짝 가늘어지게
            ..strokeCap = StrokeCap.round
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              4,
            ) // 약간의 블러로 글로우 느낌
            ..shader = SweepGradient(
              startAngle: 0,
              endAngle: 2 * math.pi,
              colors: [
                _h(hue, 0.9, 1.0),
                _h(hue + 40, 0.9, 1.0),
                _h(hue + 80, 0.9, 1.0),
              ],
            ).createShader(rect);

      final localStart =
          startAngle + localT * 0.8; // 약간씩 위상 차이를 줘서 서로 다른 속도로 도는 느낌

      canvas.drawArc(
        rect,
        localStart,
        sweep * (0.9 - i * 0.2), // 안쪽으로 갈수록 조금 짧게
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 🐌 느린 속도의 CircularProgressIndicator
class _SlowCircularProgressIndicator extends StatefulWidget {
  final Color color;
  final double strokeWidth;

  const _SlowCircularProgressIndicator({
    required this.color,
    required this.strokeWidth,
  });

  @override
  State<_SlowCircularProgressIndicator> createState() =>
      _SlowCircularProgressIndicatorState();
}

class _SlowCircularProgressIndicatorState
    extends State<_SlowCircularProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 🎯 기본 CircularProgressIndicator보다 2배 느리게 (기본 1.2초 → 2.4초)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(48, 48), // 기본 CircularProgressIndicator 크기
          painter: _SlowCircularProgressPainter(
            progress: _controller.value,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        );
      },
    );
  }
}

class _SlowCircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _SlowCircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 🎯 반지름을 더 작게 (기본의 0.75배)
    final radius = ((size.width - strokeWidth) / 2) * 0.8;

    // 배경 원
    final backgroundPaint =
        Paint()
          ..color = Colors.grey.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, backgroundPaint);

    // 진행 원호
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

    // 0.75 바퀴 (270도) 길이의 원호
    const sweepAngle = 3 * math.pi / 2; // 270도
    final startAngle = -math.pi / 2 + (progress * 2 * math.pi);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SlowCircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Doppy "o" 스피너 Painter (감각적인 스타일)
class _DoppyOSpinnerPainter extends CustomPainter {
  final double progress; // 0~1
  final Color color;
  final double strokeWidth;

  _DoppyOSpinnerPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 기본 원형 스피너
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt;

    // 270도 (3/4 원) 길이의 원호
    const sweepAngle = 3 * math.pi / 2; // 270도
    final startAngle = -math.pi / 2 + (progress * 2 * math.pi);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_DoppyOSpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
