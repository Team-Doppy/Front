import 'dart:math' as math;
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'join_screen.dart';

class WavePainter extends CustomPainter {
  final double animationValue;
  final Color primaryColor;

  WavePainter(this.animationValue, this.primaryColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = primaryColor.withOpacity(0.95) //파도 색상
          ..style = PaintingStyle.fill;

    final path = Path();

    // 첫 번째 물결
    path.moveTo(0, size.height * 0.75);
    for (double x = 0; x <= size.width; x += 1) {
      final y =
          size.height * 0.75 +
          math.sin(
                (x / size.width * 2 * math.pi) + animationValue * 2 * math.pi,
              ) *
              10;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);

    // 두 번째 물결 (더 작고 빠름)
    final path2 = Path();
    path2.moveTo(0, size.height * 0.85);
    for (double x = 0; x <= size.width; x += 1) {
      final y =
          size.height * 0.85 +
          math.sin(
                (x / size.width * 4 * math.pi) + animationValue * 3 * math.pi,
              ) *
              4;
      path2.lineTo(x, y);
    }
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();

    paint.color = primaryColor.withOpacity(0.12);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _pwController = TextEditingController();
  final _idFocus = FocusNode();
  final _pwFocus = FocusNode();

  bool _obscure = true;
  bool _canSubmit = false;
  bool _showLoginForm = false;

  // ✅ API 통신 중 로딩 상태를 표시하기 위한 변수 추가
  bool _isLoading = false;

  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _idController.addListener(_updateSubmitState);
    _pwController.addListener(_updateSubmitState);

    _waveController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _idController.dispose();
    _pwController.dispose();
    _idFocus.dispose();
    _pwFocus.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _updateSubmitState() {
    // ✅ 로딩 중일 때는 버튼 비활성화
    if (_isLoading) {
      if (_canSubmit) setState(() => _canSubmit = false);
      return;
    }
    final can =
        _idController.text.trim().isNotEmpty && _pwController.text.isNotEmpty;
    if (can != _canSubmit) setState(() => _canSubmit = can);
  }

  void _showLoginFormMethod() {
    setState(() {
      _showLoginForm = true;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    final id = _idController.text.trim();
    final pw = _pwController.text;

    final success = await AuthProvider().login(id, pw);

    // ✅ mounted 체크: 비동기 작업 후 위젯이 여전히 화면에 있는지 확인 (중요)
    if (!mounted) return;

    if (success) {
      // 로그인 직후 내 프로필을 선조회하여 초기 화면에서도 사용자 정보를 보장
      try {
        await context.read<UserProvider>().fetchMyProfile();
      } catch (_) {}

      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } else {
      // 로그인 실패 시 사용자에게 피드백 제공
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('아이디 또는 비밀번호가 일치하지 않습니다.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final double screenHeight = screen.height;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        children: [
          // 배경 이미지
          /*
          Positioned.fill(
            child: Image.asset('assets/images/feed3.png', fit: BoxFit.cover),
          ),
          // 블러 처리
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.purple.withOpacity(_showLoginForm ? 0.5 : 0.4),
              ),
            ),
          ),*/
          // 물결 애니메이션 오버레이
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return CustomPaint(
                  painter: WavePainter(
                    _waveController.value,
                    Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),
          // 메인 콘텐츠
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 여백
                SizedBox(height: screenHeight * 0.30),

                // 로고/타이틀 영역
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      // 로그인 모드가 활성화되어 있으면 취소
                      if (_showLoginForm) {
                        setState(() {
                          _showLoginForm = false;
                          _idController.clear();
                          _pwController.clear();
                        });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 34),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 로고 또는 타이틀
                          Text(
                            'Do',
                            style: TextStyle(
                              fontSize: 68,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                              letterSpacing: -1,
                              height: 0.6,
                            ),
                          ),

                          Text(
                            'Doppy',
                            style: TextStyle(
                              fontSize: 68,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '딱 너희만 봐, 도피',
                            style: TextStyle(
                              fontSize: 20,
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 하단 버튼 영역
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    children: [
                      // 로그인 폼 (조건부 표시)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (
                          Widget child,
                          Animation<double> animation,
                        ) {
                          // child가 ValueKey를 가진 경우 (로그인 폼이 나타나는 경우)
                          if (child.key == const ValueKey('loginForm')) {
                            return SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.3),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                ),
                              ),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            );
                          } else {
                            // child가 SizedBox.shrink인 경우 (로그인 폼이 사라지는 경우)
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          }
                        },
                        child:
                            _showLoginForm
                                ? GestureDetector(
                                  key: const ValueKey('loginForm'),
                                  onTap: () {
                                    // 로그인 폼 클릭 시에는 아무것도 하지 않음 (이벤트 전파 차단)
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(0),

                                    child: Form(
                                      key: _formKey,
                                      child: Column(
                                        children: [
                                          // 아이디 입력
                                          TextFormField(
                                            controller: _idController,
                                            focusNode: _idFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted:
                                                (_) => FocusScope.of(
                                                  context,
                                                ).requestFocus(_pwFocus),
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'User ID',
                                              hintStyle: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.6,
                                                ),
                                              ),
                                              filled: true,
                                              fillColor:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.surfaceVariant,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderSide: BorderSide.none,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide.none,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: BorderSide.none,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            validator: (v) {
                                              if (v == null ||
                                                  v.trim().isEmpty) {
                                                return '아이디를 입력하세요.';
                                              }
                                              return null;
                                            },
                                          ),

                                          const SizedBox(height: 8),

                                          // 비밀번호 입력
                                          TextFormField(
                                            controller: _pwController,
                                            focusNode: _pwFocus,
                                            textInputAction:
                                                TextInputAction.done,
                                            onFieldSubmitted: (_) => _submit(),
                                            obscureText: _obscure,
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Password',
                                              hintStyle: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.6,
                                                ),
                                              ),
                                              filled: true,
                                              fillColor:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.surfaceVariant,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderSide: BorderSide.none,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide.none,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: BorderSide.none,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),

                                              suffixIcon: IconButton(
                                                onPressed:
                                                    () => setState(
                                                      () =>
                                                          _obscure = !_obscure,
                                                    ),
                                                icon: Icon(
                                                  _obscure
                                                      ? Icons.visibility_off
                                                      : Icons.visibility,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.6),
                                                ),
                                              ),
                                            ),
                                            validator: (v) {
                                              if (v == null || v.isEmpty) {
                                                return '비밀번호를 입력하세요.';
                                              }
                                              if (v.length < 6) {
                                                return '비밀번호는 6자 이상이어야 합니다.';
                                              }
                                              return null;
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                                : const SizedBox.shrink(),
                      ),

                      // 로그인 버튼 (로그인 폼이 보일 때만)
                      if (_showLoginForm) ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _canSubmit ? _submit : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              disabledBackgroundColor: Colors.white.withOpacity(
                                0.3,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child:
                                _isLoading
                                    ? const CircularProgressIndicator(
                                      color: Colors.black,
                                      strokeWidth: 2.0,
                                    )
                                    : Text(
                                      '로그인',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                          ),
                        ),
                      ],

                      // 로그인 버튼 (로그인 폼이 안 보일 때만)
                      if (!_showLoginForm) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _showLoginFormMethod,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              '로그인',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 회원가입 버튼 (로그인 폼이 안 보일 때만)
                      if (!_showLoginForm)
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => JoinScreen(),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.6),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              '회원가입',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
