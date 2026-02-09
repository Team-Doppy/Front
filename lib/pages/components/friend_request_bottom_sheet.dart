import 'dart:math' as math;
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friend_provider.dart';

/// 하트 파티클 데이터 클래스
class _HeartParticle {
  final String id;
  final Offset startPosition;
  final double startSize;
  final double rotation;
  final double horizontalOffset;
  final AnimationController controller;

  _HeartParticle({
    required this.id,
    required this.startPosition,
    required this.startSize,
    required this.rotation,
    required this.horizontalOffset,
    required this.controller,
  });
}

// 친구 요청 수락/거절 바텀시트
class FriendRequestBottomSheet extends StatefulWidget {
  final String username;
  final String? profileImageUrl;
  final bool isCoupleRequest; // ✅ 곰신 요청 여부

  const FriendRequestBottomSheet({
    Key? key,
    required this.username,
    this.profileImageUrl,
    this.isCoupleRequest = false, // 기본값 false
  }) : super(key: key);

  @override
  State<FriendRequestBottomSheet> createState() =>
      _FriendRequestBottomSheetState();
}

class _FriendRequestBottomSheetState extends State<FriendRequestBottomSheet>
    with TickerProviderStateMixin {
  bool _isAccepting = false; // 🎯 수락 버튼 독립 로딩 상태
  bool _isRejecting = false; // 🎯 거절 버튼 독립 로딩 상태

  // ✅ 하트 파티클 관리
  final List<_HeartParticle> _heartParticles = [];
  late AnimationController _heartSpawnController;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    // 🎯 타이밍 기반 캐시 사용: 10초 이내 조회했으면 캐시 사용, 아니면 서버에서 조회
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<FriendProvider>().fetchAllFriendData(forceRefresh: false);
      }
    });

    // ✅ 곰신 요청일 때만 하트 파티클 생성 타이머 시작
    if (widget.isCoupleRequest) {
      _heartSpawnController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500), // 500ms마다 새 하트 생성
      )..repeat();

      _heartSpawnController.addListener(_spawnHeart);
    }
  }

  /// 새로운 하트 파티클 생성
  void _spawnHeart() {
    if (!mounted || !widget.isCoupleRequest) return;

    // 최대 파티클 개수 제한 (너무 많이 생성되지 않도록)
    if (_heartParticles.length >= 15) return;

    // 프로필 이미지 위치 기준으로 생성 (중앙 프로필 이미지 주변)
    final screenSize = MediaQuery.of(context).size;
    final profileCenterX = screenSize.width - 130 / 2 - 24; // 프로필 이미지 중앙 X
    final profileCenterY =
        screenSize.height * 0.4 / 2 + 30; // 프로필 이미지 중앙 Y (대략)

    // 랜덤 시작 위치 (프로필 이미지 주변) - 가로 범위 확대
    final startX =
        profileCenterX +
        (_random.nextDouble() - 0.5) * 200; // -100 ~ +100 범위 (더 넓게)
    final startY = profileCenterY + 40 + _random.nextDouble() * 30;

    // 랜덤 속성
    final size = 16.0 + _random.nextDouble() * 12.0; // 16~28px
    final rotation = _random.nextDouble() * 2 * math.pi;
    final horizontalOffset = (_random.nextDouble() - 0.5) * 120; // 좌우 흔들림 범위 확대

    final controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: 2000 + _random.nextInt(1000), // 2~3초
      ),
    );

    final particle = _HeartParticle(
      id:
          DateTime.now().millisecondsSinceEpoch.toString() +
          _random.nextInt(1000).toString(),
      startPosition: Offset(startX, startY),
      startSize: size,
      rotation: rotation,
      horizontalOffset: horizontalOffset,
      controller: controller,
    );

    setState(() {
      _heartParticles.add(particle);
    });

    // 애니메이션 완료 시 파티클 제거
    controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _heartParticles.remove(particle);
        });
        controller.dispose();
      }
    });
  }

  @override
  void dispose() {
    if (widget.isCoupleRequest) {
      _heartSpawnController.dispose();
      // 모든 하트 파티클 컨트롤러 정리
      for (final particle in _heartParticles) {
        particle.controller.dispose();
      }
      _heartParticles.clear();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: MediaQuery.of(context).size.height * 0.4, // 화면 높이의 40%
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.background,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 드래그 핸들
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 15),

                // 프로필 정보
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => UserProfileScreen(
                              otherUser: User(username: widget.username),
                            ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 30),
                            Text(
                              widget.username,
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color:
                                    Theme.of(context).colorScheme.onBackground,
                              ),
                            ),

                            const SizedBox(height: 4),
                            Text(
                              // ✅ 곰신 요청일 때 텍스트 변경
                              widget.isCoupleRequest
                                  ? '곰신 요청을 수락할까요?'
                                  : context.tr('accept_friend_request'),
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onBackground.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 4,
                          ),
                        ),
                        child: CommonProfileAvatar(
                          imageUrl: widget.profileImageUrl ?? '',
                          username: widget.username,
                          size: 130,
                          borderWidth: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: SizedBox()),

                // 액션 버튼들
                Row(
                  children: [
                    // 거절 버튼
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            (_isAccepting || _isRejecting)
                                ? null
                                : () => _handleFriendRequest(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.1),
                          foregroundColor:
                              Theme.of(context).colorScheme.onBackground,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            _isRejecting
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : Text(
                                  context.tr('reject'),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // 수락 버튼
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            (_isAccepting || _isRejecting)
                                ? null
                                : () => _handleFriendRequest(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            _isAccepting
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : Text(
                                  context.tr('accept'),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        // ✅ 하트 파티클 오버레이 (곰신 요청일 때만)
        if (widget.isCoupleRequest)
          ..._heartParticles.map((particle) {
            return AnimatedBuilder(
              animation: particle.controller,
              builder: (context, child) {
                final progress = particle.controller.value;
                final curve = Curves.easeOut.transform(progress);

                // 위로 이동 (페이드아웃)
                final offsetY = -curve * 250; // 최대 250px 위로
                final offsetX =
                    math.sin(progress * math.pi * 2) *
                    particle.horizontalOffset *
                    curve; // 좌우 흔들림

                // 페이드아웃
                final opacity = (1.0 - progress).clamp(0.0, 1.0);

                // 스케일 (작아지면서 사라짐)
                final scale = 1.0 - progress * 0.3;

                // 회전
                final rotation = particle.rotation + progress * math.pi;

                return Positioned(
                  left: particle.startPosition.dx + offsetX,
                  top: particle.startPosition.dy + offsetY,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Transform.rotate(
                        angle: rotation,
                        child: Icon(
                          Icons.favorite,
                          color: const Color.fromARGB(255, 255, 103, 92),
                          size: particle.startSize,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }).toList(),
      ],
    );
  }

  Future<void> _handleFriendRequest(bool accept) async {
    if (!mounted) return;

    // 🎯 각 버튼의 독립적인 로딩 상태 설정
    setState(() {
      if (accept) {
        _isAccepting = true;
      } else {
        _isRejecting = true;
      }
    });

    try {
      if (!mounted) return;
      final friendProvider = context.read<FriendProvider>();
      bool? result;

      if (accept) {
        // 그룹 기능 제거로 인해 groupProvider 파라미터 제거
        result = await friendProvider.acceptFriendRequest(widget.username);
      } else {
        // 🎯 거절 기능 구현
        result = await friendProvider.rejectFriendRequest(widget.username);
      }

      if (mounted) {
        Navigator.pop(context); // 바텀시트 닫기
        if (result == false && mounted) {
          // 🎯 수락/거절에 따라 다른 실패 메시지 표시
          ErrorHandler.showError(
            context,
            accept
                ? context.tr('friend_request_accept_failed')
                : context.tr('friend_request_reject_failed'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        // 🎯 수락/거절에 따라 다른 실패 메시지 표시
        ErrorHandler.showError(
          context,
          accept
              ? context.tr('friend_request_accept_failed')
              : context.tr('friend_request_reject_failed'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          // 🎯 각 버튼의 독립적인 로딩 상태 해제
          if (accept) {
            _isAccepting = false;
          } else {
            _isRejecting = false;
          }
        });
      }
    }
  }
}
