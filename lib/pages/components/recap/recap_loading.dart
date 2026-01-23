import 'dart:async';
// import 'dart:convert'; // ✅ 캐시 기능 주석처리로 인해 사용 안 함
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/recap_service.dart';
import 'package:doppy/pages/components/recap/recap_content_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class RecapLoadingScreen extends StatefulWidget {
  const RecapLoadingScreen({
    super.key,
    required this.thumbnailUrls,
    this.forceRefresh = false, // ✅ true면 캐시 무시하고 서버에서 강제로 받기
  });

  final List<String> thumbnailUrls; // 0..n (최대 3개를 권장)
  final bool forceRefresh; // ✅ 서버에서 강제로 받기 플래그

  @override
  State<RecapLoadingScreen> createState() => _RecapLoadingScreenState();
}

class _RecapLoadingScreenState extends State<RecapLoadingScreen>
    with SingleTickerProviderStateMixin {
  static const Color _darkSurface = AppColors.darkSurface;
  // static const String _cacheKeyPrefix = 'insight_content_preview_'; // ✅ 캐시 기능 주석처리로 인해 사용 안 함
  static const String _audioPath =
      'audio/copy_E40AB8B9-EA58-449C-8E26-B2560003CA3C.mp3';

  late final AnimationController _spinController;
  // ignore: unused_field
  bool _isLoading = true; // ✅ 상태 관리용 (향후 UI 개선 시 사용 가능)
  String? _error;
  bool _isContentNotReadyError =
      false; // ✅ "InsightContent 준비가 되지 않았습니다" 에러인지 여부
  AudioPlayer? _audioPlayer;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<void>? _playerCompleteSubscription;
  double _audioVolume = 0.0; // 페이드인/아웃용 볼륨
  int _currentTextIndex = 0; // ✅ 현재 표시할 텍스트 인덱스 (0 또는 1)
  Timer? _textSwitchTimer; // ✅ 텍스트 전환 타이머

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAudio();
      _startTextSwitching(); // ✅ 텍스트 전환 시작
      // ✅ 백그라운드에서 실행 (화면을 닫아도 완료되면 캐시에 저장)
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _spinController.dispose();
    _textSwitchTimer?.cancel(); // ✅ 타이머 정리
    _playerStateSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    _fadeOutAndDisposeAudio();
    super.dispose();
  }

  /// ✅ 텍스트 전환 시작 (3초 주기, 전환 시 약간의 딜레이 추가)
  void _startTextSwitching() {
    _textSwitchTimer?.cancel();
    _textSwitchTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // ✅ 텍스트 전환 전 약간의 딜레이 (200ms) - 자연스러운 전환을 위해
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        setState(() {
          _currentTextIndex = (_currentTextIndex + 1) % 2; // 0 ↔ 1 번갈아가며
        });
      });
    });
  }

  Future<void> _initializeAudio() async {
    try {
      _audioPlayer = AudioPlayer();

      // ✅ 안드로이드에서 명시적으로 PlayerMode 설정
      if (!kIsWeb && Platform.isAndroid) {
        await _audioPlayer!.setPlayerMode(PlayerMode.mediaPlayer);
        debugPrint('[RecapLoadingScreen] 안드로이드 PlayerMode 설정 완료');
      }

      _audioPlayer!.setReleaseMode(ReleaseMode.stop);

      // ✅ 오디오 완료 리스너
      _playerCompleteSubscription = _audioPlayer!.onPlayerComplete.listen((_) {
        if (mounted) {
          _fadeOutAndDisposeAudio();
        }
      });

      // ✅ 오디오 소스 설정
      debugPrint('[RecapLoadingScreen] 오디오 소스 설정 시작: $_audioPath');
      try {
        await _audioPlayer!.setSource(AssetSource(_audioPath));
      } catch (sourceError) {
        // ✅ iOS에서 asset 로드 실패 시에도 계속 진행 (오디오 없이 작동)
        debugPrint('[RecapLoadingScreen] 오디오 소스 설정 실패 (무시하고 계속): $sourceError');
        await _audioPlayer?.dispose();
        _audioPlayer = null;
        _playerCompleteSubscription?.cancel();
        _playerCompleteSubscription = null;
        return;
      }

      // ✅ 안드로이드에서 준비 완료 대기 (상태 확인)
      if (!kIsWeb && Platform.isAndroid) {
        // 상태가 playing 또는 completed가 될 때까지 대기 (최대 2초)
        int retryCount = 0;
        while (retryCount < 20) {
          final state = _audioPlayer?.state;
          if (state == null) break;
          debugPrint(
            '[RecapLoadingScreen] 오디오 상태 확인: $state (시도 ${retryCount + 1}/20)',
          );
          if (state == PlayerState.playing || state == PlayerState.completed) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
          retryCount++;
        }
      }

      if (_audioPlayer == null) return;

      await _audioPlayer!.setVolume(0.0); // 초기 볼륨 0
      debugPrint('[RecapLoadingScreen] 오디오 재생 시작');
      await _audioPlayer!.resume();

      // ✅ 재생 상태 확인
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final finalState = _audioPlayer?.state;
      debugPrint('[RecapLoadingScreen] 오디오 최종 상태: $finalState');

      // ✅ 페이드인 애니메이션 (1초 동안 0.0 -> 1.0)
      if (_audioPlayer != null) {
        _fadeInAudio();
      }
    } catch (e, stackTrace) {
      debugPrint('[RecapLoadingScreen] 오디오 초기화 실패: $e');
      debugPrint('[RecapLoadingScreen] 스택 트레이스: $stackTrace');
      // ✅ 오디오 실패 시에도 앱은 계속 작동
      if (_audioPlayer != null) {
        await _audioPlayer?.dispose();
        _audioPlayer = null;
      }
      _playerCompleteSubscription?.cancel();
      _playerCompleteSubscription = null;
    }
  }

  Future<void> _fadeInAudio() async {
    const duration = Duration(milliseconds: 1000);
    const steps = 20;
    final stepDuration = duration ~/ steps;
    const volumeStep = 1.0 / steps;

    for (int i = 0; i <= steps; i++) {
      if (!mounted || _audioPlayer == null) return;
      _audioVolume = (i * volumeStep).clamp(0.0, 1.0);
      await _audioPlayer!.setVolume(_audioVolume);
      await Future<void>.delayed(stepDuration);
    }
  }

  Future<void> _fadeOutAndDisposeAudio() async {
    if (_audioPlayer == null) return;

    try {
      // ✅ 페이드아웃 애니메이션 (0.5초 동안 1.0 -> 0.0)
      const duration = Duration(milliseconds: 500);
      const steps = 10;
      final stepDuration = duration ~/ steps;
      final volumeStep = _audioVolume / steps;

      for (int i = steps; i >= 0; i--) {
        if (_audioPlayer == null) return;
        _audioVolume = (i * volumeStep).clamp(0.0, 1.0);
        await _audioPlayer!.setVolume(_audioVolume);
        await Future<void>.delayed(stepDuration);
      }

      await _audioPlayer!.stop();
    } catch (e) {
      debugPrint('[RecapLoadingScreen] 오디오 페이드아웃 실패: $e');
    } finally {
      _playerStateSubscription?.cancel();
      _playerCompleteSubscription?.cancel();
      await _audioPlayer?.dispose();
      _audioPlayer = null;
    }
  }

  Future<void> _bootstrap() async {
    // ✅ 캐시 기능 주석처리: 매번 서버에서 불러오도록
    // // ✅ forceRefresh가 true면 캐시 무시하고 바로 서버 호출
    // if (widget.forceRefresh) {
    //   // ✅ 백그라운드에서 실행 (화면을 닫아도 완료되면 캐시에 저장)
    //   _requestAndNavigate();
    //   return;
    // }

    // // ✅ 안전장치: 혹시 여기까지 왔는데 캐시가 이미 있으면 서버 호출 없이 바로 전환
    // // 단, 최소 2초는 로딩 화면을 보여주기 위해 대기
    // try {
    //   final cached = await _readCachedDocJson();
    //   if (!mounted) return;
    //   if (cached != null) {
    //     // ✅ 최소 2초 대기 (로딩 화면을 충분히 보여주기 위해)
    //     await Future<void>.delayed(const Duration(seconds: 2));
    //     if (!mounted) return;
    //     await _goToRenderer(cached);
    //     return;
    //   }
    // } catch (_) {
    //   // 캐시 파싱 실패면 그냥 생성 시도
    // }

    // ✅ 매번 서버에서 불러오기
    _requestAndNavigate();
  }

  // ✅ 리캡 캐시 기능 주석처리 (나중을 위해)
  // Future<Map<String, dynamic>?> _readCachedDocJson() async {
  //   final accountKey = await AuthService().getAccountKeyFromToken();
  //   if (accountKey == null || accountKey.isEmpty) return null;
  //
  //   final prefs = await SharedPreferences.getInstance();
  //   final raw = prefs.getString('$_cacheKeyPrefix$accountKey');
  //   if (raw == null || raw.isEmpty) return null;
  //
  //   final decoded = jsonDecode(raw);
  //   if (decoded is Map<String, dynamic>) return decoded;
  //   return null;
  // }
  //
  // Future<void> _writeCachedDocJson(Map<String, dynamic> docJson) async {
  //   final accountKey = await AuthService().getAccountKeyFromToken();
  //   if (accountKey == null || accountKey.isEmpty) return;
  //
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.setString('$_cacheKeyPrefix$accountKey', jsonEncode(docJson));
  // }

  Future<void> _requestAndNavigate() async {
    // ✅ mounted 체크: 화면이 이미 닫혔으면 UI 업데이트 스킵
    if (!mounted) return;

    _spinController.repeat(); // ✅ 애니메이션 재시작
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      "당신은 여러 개의 포스트, postAnalysis 데이터, 이미지들을 종합해 하나의 ‘리캡형 콘텐츠’를 편집하는 콘텐츠 에디터다.\n\n이 결과물은 분석 리포트처럼 정확해야 하지만, 읽히는 방식은 명확히 ‘콘텐츠’여야 한다. 정리된 글이면서도 흥미가 있어야 하고, 사용자가 스크롤을 멈추지 않게 해야 한다.\n\n문체는 반드시 해요체를 사용한다. 가르치거나 평가하지 않고, 기록을 정리해주듯 차분하게 서술한다.\n\n이 콘텐츠는 최소 40개 이상의 블록으로 구성한다 블록은 텍스트 블록과 이미지 블록을 모두 포함하며, 이미지 사용은 선택이 아니라 필수다.\n\n---\n\n### 전체 구조 (기승전결 고정)\n\n이 콘텐츠는 반드시 다음 4단계를 순서대로 따른다.\n\n1) 기 – 도입(6-10블록)\n- 이 시기의 기록을 처음 훑어본 느낌으로 시작한다.\n- 특정 사건을 바로 나열하지 말고, 말투·리듬·공기부터 잡는다.\n- 이 구간에는 이미지 블록을 최소 1개 이상 포함한다.\n\n2) 승 – 전개(10-20블록)\n- 있었던 일들을 시간순이 아닌 ‘맥락 묶음’으로 정리한다.\n- 비슷한 상황, 반복되는 행동, 자주 등장하는 사람이나 장소를 중심으로 서술한다.\n- 이 구간에는 이미지 블록을 최소 3개 이상 포함한다.\n- 이미지는 설명 대상이 아니라, 서술을 뒷받침하는 장면 증거로 사용한다.\n\n3) 전 – 전환 (12-20블록)\n- postAnalysis 데이터를 활용해 흐름이 살짝 달라지는 지점을 짚는다.\n- dominantEmotion, intensityScore, lifeDomain, narrativeRole 등을 근거로 한다.\n- 분석은 짧고 조심스럽게 한다. 단정하거나 해석하지 말고 ‘이렇게도 읽힌다’ 수준으로만 쓴다.\n- 이 구간에는 이미지 블록을 최소 2개 이상 포함한다.\n\n4) 결 – 여운(10-20블록)\n- 정리나 결론을 내리지 않는다.\n- 기록이 아직 이어지고 있다는 느낌으로 마무리한다.\n- 마지막에는 이 흐름에 다음 기록이 자연스럽게 이어질 것 같은 여지를 남긴다.\n\n---\n\n### 이미지 사용 규칙 (중요)\n\n- 이미지는 반드시 콘텐츠 흐름 중간중간에 배치한다.적극적으로 이미지를 이용해라.\n- 이미지 캡션은 사건 설명이 아니라 분위기 보조용으로 쓴다.\n- 이미지 하나당 1문장 캡션만 허용한다.\n\n---\n\n### 금지 사항\n\n- 포스트를 하나씩 요약하는 구조\n- 첫인상, 캐릭터 설정, 교훈 도출\n- 감정 점수 나열식 설명\n- 사용자를 평가하거나 방향을 제시하는 문장\n- 여행기, 후기, 일기처럼 보이는 나열\n\n---\n\n이 콘텐츠를 다 읽고 나면, 사용자는 ‘이 시기의 기록을 잘 편집해 다시 본 느낌’을 받아야 한다. 동시에, 다음 기록이 이 흐름에 어떤 장면을 더할지 자연스럽게 궁금해져야 한다.";
      const postSelection = <String, dynamic>{
        'type': 'firstNByCreatedAtAsc',
        'n': 3,
      };

      final result = await RecapService().generate(
        postSelection: postSelection,
        forceRegenerate: widget.forceRefresh, // ✅ 플래그에 따라 강제 재생성
      );

      // ✅ success: false인 경우 에러 처리
      if (result['success'] == false) {
        final errorMsg = result['error']?.toString() ?? '';
        // ✅ 정확히 "InsightContent 준비가 되지 않았습니다. 잠시 후 다시 시도해 주세요." 에러만 특별 처리
        if (errorMsg.contains('준비')) {
          if (!mounted) return;
          _spinController.stop(); // ✅ 애니메이션 정지
          setState(() {
            _error = '처리중 문제가 있었어요\n잠시 후에 다시 시도해보세요';
            _isContentNotReadyError = true;
            _isLoading = false;
          });
          return;
        }
        // ✅ 나머지 에러는 네트워크 에러로 처리
        if (!mounted) return;
        _spinController.stop(); // ✅ 애니메이션 정지
        setState(() {
          _error = '네트워크 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.';
          _isContentNotReadyError = false;
          _isLoading = false;
        });
        return;
      }

      // ✅ 캐시 저장 기능 주석처리 (나중을 위해)
      // // ✅ 캐시 저장 (원본 그대로 저장: {success,data:{...}} 또는 {hero,blocks} 모두 지원)
      // // ✅ 화면이 닫혀도 캐시는 저장 (백그라운드 작업)
      // await _writeCachedDocJson(result);

      // ✅ 서버에서 성공적으로 로드했을 때만 리캡을 봤다는 플래그 설정
      await _markInsightContentAsViewed();

      // ✅ 화면이 닫혔으면 렌더러로 이동하지 않음
      if (!mounted) return;

      await _goToRenderer(result);
    } catch (e) {
      if (!mounted) return;
      _spinController.stop(); // ✅ 애니메이션 정지
      setState(() {
        _error = '네트워크 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.';
        _isContentNotReadyError = false;
        _isLoading = false;
      });
    }
  }

  /// ✅ 리캡을 봤다는 타임스탬프를 SharedPreferences에 저장
  /// 서버에서 성공적으로 로드했을 때만 호출
  Future<void> _markInsightContentAsViewed() async {
    try {
      final accountKey = await AuthService().getAccountKeyFromToken();
      if (accountKey == null || accountKey.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final key = 'insight_content_viewed_$accountKey';
      // ✅ 현재 시간을 ISO 8601 형식으로 저장
      final timestamp = DateTime.now().toIso8601String();
      await prefs.setString(key, timestamp);
      debugPrint('[RecapLoadingScreen] 리캡을 봤다는 타임스탬프 저장 완료: $key = $timestamp');
    } catch (e) {
      debugPrint('[RecapLoadingScreen] 타임스탬프 저장 실패: $e');
    }
  }

  Future<void> _goToRenderer(Map<String, dynamic> docJson) async {
    if (!mounted) return;

    // 로딩 상태를 잠깐 유지해 페이드가 자연스럽게 보이도록
    setState(() {
      _isLoading = false;
      _error = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    // ✅ 오디오 플레이어를 RecapContentScreen으로 전달
    final audioPlayerToPass = _audioPlayer;
    _audioPlayer = null; // 이 화면에서는 더 이상 관리하지 않음
    _playerStateSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    _playerStateSubscription = null;
    _playerCompleteSubscription = null;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (_, __, ___) => RecapContentScreen(
              docJson: docJson,
              audioPlayer: audioPlayerToPass,
              initialVolume: _audioVolume,
            ),
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  List<String> get _threeThumbnails {
    final urls =
        widget.thumbnailUrls.where((e) => e.trim().isNotEmpty).toList();
    if (urls.isEmpty) return const [];
    if (urls.length >= 3) return urls.take(3).toList();
    // 부족하면 마지막 썸네일 반복
    while (urls.length < 3) {
      urls.add(urls.last);
    }
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final thumbs = _threeThumbnails;

    return Scaffold(
      backgroundColor: _darkSurface,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null) ...[
                      // ✅ 에러 UI: 아이콘 + 메시지
                      Icon(
                        _isContentNotReadyError
                            ? Icons.sentiment_dissatisfied_outlined
                            : Icons.wifi_off_rounded,
                        size: 64,
                        color: AppColors.darkTextPrimary.withOpacity(0.3),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: LocaleTypography.style(
                          context: context,
                          color: AppColors.darkTextPrimary.withOpacity(0.6),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      // ✅ 로딩 UI: 회전 애니메이션 + 텍스트
                      SizedBox(
                        height: 180,
                        width: 180,
                        child: AnimatedBuilder(
                          animation: _spinController,
                          builder: (context, _) {
                            final t = _spinController.value * 2 * math.pi;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                for (int i = 0; i < 3; i++)
                                  _OrbitThumb(
                                    index: i,
                                    angle: t + i * (2 * math.pi / 3),
                                    url: i < thumbs.length ? thumbs[i] : null,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                      // ✅ 텍스트 번갈아가며 부드럽게 전환 (페이드아웃 → 빈 공간 → 페이드인)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 1200),
                        switchInCurve: const Interval(
                          0.5,
                          1.0,
                          curve: Curves.easeIn,
                        ),
                        switchOutCurve: const Interval(
                          0.0,
                          0.4,
                          curve: Curves.easeOut,
                        ),
                        transitionBuilder: (
                          Widget child,
                          Animation<double> animation,
                        ) {
                          // 🎯 나가는 애니메이션 (reverse): 0.0 ~ 0.4에서 페이드아웃
                          // 🎯 빈 공간: 0.4 ~ 0.5
                          // 🎯 들어오는 애니메이션 (forward): 0.5 ~ 1.0에서 페이드인
                          if (animation.status == AnimationStatus.reverse) {
                            // 나가는 애니메이션: 0.0 ~ 0.4 구간에서만 페이드아웃
                            final fadeOutProgress = (animation.value / 0.4)
                                .clamp(0.0, 1.0);
                            return Opacity(
                              opacity: 1.0 - fadeOutProgress,
                              child: child,
                            );
                          } else {
                            // 들어오는 애니메이션: 0.5 ~ 1.0 구간에서만 페이드인
                            if (animation.value < 0.5) {
                              // 빈 공간 구간 (0.0 ~ 0.5)
                              return Opacity(opacity: 0.0, child: child);
                            } else {
                              // 페이드인 구간 (0.5 ~ 1.0)
                              final fadeInProgress = ((animation.value - 0.5) /
                                      0.5)
                                  .clamp(0.0, 1.0);
                              return Opacity(
                                opacity: fadeInProgress,
                                child: child,
                              );
                            }
                          }
                        },
                        child:
                            _currentTextIndex == 0
                                ? Text(
                                  '이야기를 살펴보고 있어요',
                                  key: const ValueKey<String>('text1'),
                                  textAlign: TextAlign.center,
                                  style: LocaleTypography.style(
                                    context: context,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.darkTextPrimary
                                        .withOpacity(0.9),
                                    height: 1.25,
                                  ),
                                )
                                : Text(
                                  '조금 시간이 걸려요!',
                                  key: const ValueKey<String>('text2'),
                                  textAlign: TextAlign.center,
                                  style: LocaleTypography.style(
                                    context: context,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.darkTextPrimary
                                        .withOpacity(0.9),
                                    height: 1.25,
                                  ),
                                ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 닫기
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () async {
                  // ✅ 닫을 때 오디오 페이드아웃
                  await _fadeOutAndDisposeAudio();
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: AppColors.darkTextPrimary.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitThumb extends StatelessWidget {
  const _OrbitThumb({
    required this.index,
    required this.angle,
    required this.url,
  });

  final int index;
  final double angle;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final radius = 54.0;
    final dx = math.cos(angle) * radius;
    final dy = math.sin(angle) * radius;

    // depth 효과: 위쪽일수록(dy가 작을수록) 살짝 크게, 아래로 갈수록 작게
    final depth = ((-dy + radius) / (2 * radius)).clamp(0.0, 1.0);
    final size = lerpDouble(42, 54, depth)!;
    final opacity = lerpDouble(0.55, 1.0, depth)!;

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        opacity: opacity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
                width: 1,
              ),
            ),
            child:
                (url == null || url!.isEmpty)
                    ? const SizedBox.shrink()
                    : CachedNetworkImage(
                      imageUrl: url!,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget:
                          (_, __, ___) => Container(color: Colors.white12),
                      placeholder: (_, __) => Container(color: Colors.white12),
                    ),
          ),
        ),
      ),
    );
  }
}
