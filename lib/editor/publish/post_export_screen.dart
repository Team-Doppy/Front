import 'dart:convert';
import 'dart:math' as math;
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/content_change_detector.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/publish/service/post_publish_service.dart'
    show PostContentUtils, PostExporter;
import 'package:doppy/providers/publish_provider.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/access_level_parser.dart';
import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/editor/publish/component/step1_thumbnail_edit.dart';
import 'package:doppy/pages/components/access_level_sheet.dart'
    show AccessLevelSheet, AccessLevelSelectMode;
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show cleanupAllVideoPlayers;
import 'package:doppy/pages/components/retry_cancel_bottom_sheet.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/utils/mentioned_usernames_extractor.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/main.dart' show navigatorKey;
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/overlay/letter_recipient_selection_overlay.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';

void printLarge(String text, {int chunkSize = 800}) {
  final int len = text.length;
  for (int i = 0; i < len; i += chunkSize) {
    final int end = (i + chunkSize < len) ? i + chunkSize : len;
    debugPrint(text.substring(i, end));
  }
}

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

class PostExportScreen extends StatefulWidget {
  const PostExportScreen({
    super.key,
    required this.exported,
    this.sessionKey,
    this.isEditMode = false,
    this.postId,
    this.initialAccessLevel,
    this.initialExportedForComparison,
    this.initialYear,
    this.initialYearOfWeek,
    this.isOnboardingMode = false, // 🎯 온보딩 모드 여부
    this.writeMode, // ✅ 글쓰기 모드
  });
  final String exported;
  final String? sessionKey; // 블로그/드래프트별 네임스페이스 키
  final bool isEditMode; // 🎯 수정 모드 여부
  final String? postId; // 🎯 수정 모드일 때 포스트 ID
  final String? initialAccessLevel; // 🎯 수정 모드일 때 초기 공개범위
  final String? initialExportedForComparison; // 🎯 수정 진입 시 원본 exported(JSON)
  final int? initialYear; // 초기 연도
  final int? initialYearOfWeek; // 초기 주차 (1-53)
  final bool isOnboardingMode; // 🎯 온보딩 모드 여부
  final PostWriteMode? writeMode; // ✅ 글쓰기 모드

  @override
  State<PostExportScreen> createState() => _PostExportScreenState();
}

class _PostExportScreenState extends State<PostExportScreen>
    with TickerProviderStateMixin {
  String get _nsKey => widget.sessionKey ?? 'default';

  // 🎯 Step 2, 3 제거됨 - 이제 bottomNavigationBar에서 직접 선택

  // 더미 데이터
  String _exportedThumbnailImageUrl = '';
  // ✅ 썸네일(특히 영상)을 선택/변경했는데, URL 비교 타이밍 때문에 "변경사항 없음"으로 떨어지는 케이스 방지용
  bool _thumbnailTouchedInSession = false;
  String _firstBodyImageUrl = '';
  String _title = '';
  late final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();

  Map<String, dynamic> _exportedBase = <String, dynamic>{};

  bool _editMode = false;

  // 공개 범위 선택 (기본값: 글 타입에 따라 결정)
  late String _currentAccessLevel;

  // ✅ letter 모드: 선택한 친구 목록 (exported에서 추출)
  List<String> _letterRecipients = [];

  // ✅ 친구공개(친구지정): 선택한 친구 목록
  List<Map<String, dynamic>> _selectedFriends =
      []; // {username, alias, imageUrl}

  // ✅ 수정 모드: 원본 exported(변경 감지용)
  Map<String, dynamic>? _initialExportedForComparisonMap;

  bool _isUploading = false;
  bool _isUploadingThumb = false;
  bool _showInitialThumbnailShimmer = true; // ✅ 첫 진입: placeholder 대신 쉬머 먼저
  File? _localThumbnailFile; // 업로드 중 로컬 파일 미리보기용
  File? _localVideoFile; // 영상 선택 시 원본 비디오 파일
  VideoPlayerController? _videoController; // 영상 재생 컨트롤러
  String? _cachedVideoUrl; // 캐시된 비디오 URL (서버 영상용)

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  // 🎯 dispose()에서 안전하게 사용하기 위해 UploadService 참조 저장
  UploadService? _uploadService;

  // ✅ 하트 파티클 관리 (letter 모드에서 여친만 선택되었을 때)
  final List<_HeartParticle> _heartParticles = [];
  late AnimationController _heartSpawnController;
  final math.Random _random = math.Random();
  bool _shouldShowHearts = false;

  @override
  void initState() {
    super.initState();
    // ✅ 수정 모드일 때는 initialAccessLevel 우선 사용, 없으면 글 타입에 따른 기본값
    _currentAccessLevel =
        widget.initialAccessLevel ??
        _getDefaultAccessLevelForWriteMode(widget.writeMode);

    // 🎯 수정 진입 시 원본 payload 파싱 (있으면)
    if (widget.initialExportedForComparison != null &&
        widget.initialExportedForComparison!.trim().isNotEmpty) {
      try {
        final decoded =
            jsonDecode(widget.initialExportedForComparison!)
                as Map<String, dynamic>;
        _initialExportedForComparisonMap = decoded;
      } catch (e) {
        debugPrint('[PostExportScreen] initialExportedForComparison 파싱 실패: $e');
        _initialExportedForComparisonMap = null;
      }
    }
    _hydrateFromExported(jsonDecode(widget.exported));
    cleanupAllVideoPlayers();
    _intro.forward();

    // ✅ 첫 프레임에서는 "눌러서 썸네일 선택" 문구가 튀지 않도록 쉬머를 잠깐 보여준다.
    // 이후에는 Step1ThumbnailEdit의 frameBuilder(이미지) / controller 초기화(비디오) 쉬머가 이어받는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        setState(() {
          _showInitialThumbnailShimmer = false;
        });
      });
    });

    // ✅ 하트 파티클 생성 타이머 (약하게: 800ms마다)
    _heartSpawnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // ✅ 약하게: 800ms마다
    );

    // 카테고리는 Step3 컴포넌트에서 로드함
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _uploadService = context.read<UploadService>();

    // ✅ letter 모드: String 형태의 letterRecipients를 Map 형태로 변환
    if (widget.writeMode == PostWriteMode.letter &&
        _letterRecipients.isNotEmpty &&
        (_exportedBase['letterRecipients'] as List?)?.isNotEmpty == true &&
        (_exportedBase['letterRecipients'] as List).first is! Map) {
      try {
        final friendProvider = context.read<FriendProvider>();
        final friends = friendProvider.acceptedFriends;
        final userProvider = context.read<UserProvider>();
        final currentUser = userProvider.currentUser;

        // 연결된 짝궁도 확인
        User? partner;
        if (currentUser != null) {
          final userType = currentUser.militaryInfo?.userType;
          if (userType == UserType.girlfriend) {
            partner = currentUser.connectedMilitaryUser;
          } else if (userType == UserType.military ||
              userType == UserType.plannedEnlistment) {
            partner = currentUser.connectedToMeByUser;
          }
        }

        final letterRecipientsAsMaps = <Map<String, dynamic>>[];
        for (final username in _letterRecipients) {
          if (username == 'all_friends') continue;

          // 연결된 짝궁인지 확인
          if (partner != null && partner.username == username) {
            letterRecipientsAsMaps.add({
              'username': partner.username,
              'alias': partner.alias ?? partner.username,
              'imageUrl': partner.profileImageUrl,
            });
          } else {
            // 친구 목록에서 찾기
            try {
              final friend = friends.firstWhere((f) => f.username == username);
              letterRecipientsAsMaps.add({
                'username': friend.username,
                'alias': friend.alias,
                'imageUrl': friend.profileImageUrl,
              });
            } catch (_) {
              // 친구를 찾을 수 없으면 username만으로 추가
              letterRecipientsAsMaps.add({
                'username': username,
                'alias': username,
                'imageUrl': null,
              });
            }
          }
        }
        _exportedBase['letterRecipients'] = letterRecipientsAsMaps;
      } catch (_) {
        // 변환 실패 시 그대로 유지
      }
    }

    // ✅ letter 모드에서 여친만 선택되었는지 확인하고 하트 파티클 시작/중지
    _updateHeartParticles();
  }

  @override
  void dispose() {
    try {
      _titleController.dispose();
      _titleFocusNode.dispose();

      // ✅ 하트 파티클 정리
      _heartSpawnController.removeListener(_spawnHeart);
      _heartSpawnController.stop();
      _heartSpawnController.dispose();
      for (final particle in _heartParticles) {
        particle.controller.dispose();
      }
      _heartParticles.clear();

      // 🎯 비디오 컨트롤러 정리 (로컬/서버 구분하여 처리)
      // _disposeVideoController 내부에서 _cachedVideoUrl 여부에 따라 처리
      _disposeVideoController(context: 'dispose');

      // 🎯 업로드 태스크 취소 (비동기로 처리하여 위젯 트리 잠금 방지)
      // dispose() 중에는 notifyListeners()가 호출되면 위젯 트리가 잠겨있어 에러 발생
      // 다음 프레임에서 처리하도록 비동기로 실행
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _cancelUploadTasks();
        } catch (e) {
          debugPrint('[PostExport] dispose 후 업로드 태스크 취소 오류: $e');
        }
      });
    } catch (e) {
      debugPrint('[PostExport] dispose 에러: $e');
    }
    super.dispose();
  }

  void _hydrateFromExported(Map<String, dynamic> exported) {
    _exportedBase = exported;
    // 제목
    final String? exportedTitle = PostContentUtils.readString(
      exported,
      keys: const ['title'],
    );
    if (exportedTitle != null && exportedTitle.trim().isNotEmpty) {
      _title = exportedTitle.trim();
      _titleController.text = _title;
    }

    // ✅ letter 모드: 선택한 친구 목록 추출
    if (widget.writeMode == PostWriteMode.letter) {
      try {
        final recipients = exported['letterRecipients'] as List?;
        if (recipients != null) {
          // Map 형태인 경우 (전체 정보) - 수정 모드에서 전체 정보 유지
          if (recipients.isNotEmpty && recipients.first is Map) {
            // ✅ exportedBase에 Map 형태로 유지 (수정 모드에서 전체 정보 필요)
            _exportedBase['letterRecipients'] = recipients;
            _letterRecipients =
                recipients
                    .map(
                      (r) =>
                          (r as Map<String, dynamic>)['username']?.toString() ??
                          '',
                    )
                    .where((r) => r.isNotEmpty)
                    .toList();
          } else {
            // String 형태인 경우 (하위 호환성)
            _letterRecipients =
                recipients
                    .map((r) => r.toString())
                    .where((r) => r.isNotEmpty)
                    .toList();
            // ✅ String 형태를 Map 형태로 변환하는 것은 didChangeDependencies에서 처리
            // (initState에서는 context.read 사용 불가)
          }
        }
      } catch (_) {
        _letterRecipients = [];
      }
    }

    // ✅ letter 모드: 하트 파티클 업데이트 (초기 로드 후)
    if (widget.writeMode == PostWriteMode.letter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateHeartParticles();
        }
      });
    }

    // ✅ 친구공개(친구지정): 선택한 친구 목록 추출
    try {
      final selectedFriends = exported['selectedFriends'] as List?;
      if (selectedFriends != null) {
        _selectedFriends =
            selectedFriends
                .map((f) => f is Map<String, dynamic> ? f : <String, dynamic>{})
                .where((f) => f['username'] != null)
                .toList();
      }
    } catch (_) {
      _selectedFriends = [];
    }

    // ✅ 수정 모드: exported에서 accessLevel 추출 (실제 보낸 타겟 정보 반영)
    if (widget.isEditMode) {
      try {
        final exportedAccessLevel = exported['accessLevel']?.toString();
        if (exportedAccessLevel != null && exportedAccessLevel.isNotEmpty) {
          _currentAccessLevel = exportedAccessLevel.toUpperCase();
          debugPrint(
            '[PostExportScreen] 수정 모드: accessLevel=$_currentAccessLevel 로드',
          );
        }
      } catch (e) {
        debugPrint('[PostExportScreen] accessLevel 추출 실패: $e');
      }
    }

    // 🎯 썸네일: exported에서 가져오기 (임시저장 사용 안 함)
    final exportedThumbnailUrl = exported['thumbnailImageUrl'] as String? ?? '';

    // ✅ 본문 첫 미디어 URL (이미지 우선, 없으면 영상) - Step1 카드/배경 기본값
    _firstBodyImageUrl = PostContentUtils.findFirstBodyImageUrl(exported);

    assert(() {
      final nodes =
          (exported['content'] is Map)
              ? List<dynamic>.from(
                ((exported['content'] as Map)['nodes'] as List?) ?? const [],
              )
              : const [];
      debugPrint(
        '[ThumbAuto][PostExportScreen] exportedThumbnailUrl="$exportedThumbnailUrl", firstBody="$_firstBodyImageUrl", nodes=${nodes.length}',
      );
      if (nodes.isNotEmpty) {
        for (int i = 0; i < nodes.length && i < 6; i++) {
          final n = nodes[i];
          if (n is! Map) continue;
          debugPrint('[ThumbAuto][PostExportScreen] node[$i] = ${n['type']}');
        }
      }
      debugPrint(
        '[ThumbAuto][PostExportScreen] usedImageUrls=${(exported['usedImageUrls'] as List?)?.length ?? 0}',
      );
      return true;
    }());

    // ✅ 썸네일이 비어있으면 "본문 첫 미디어(이미지 우선, 없으면 영상)"를 기본값으로 사용한다.
    // - 카드 + 배경 이미지/영상이 즉시 보여야 함
    // - http(s)만 채택
    _exportedThumbnailImageUrl =
        exportedThumbnailUrl.trim().isNotEmpty
            ? exportedThumbnailUrl.trim()
            : _firstBodyImageUrl.trim();

    debugPrint(
      '[PostExport] 썸네일 초기화: $_exportedThumbnailImageUrl (firstBody=$_firstBodyImageUrl)',
    );

    // ✅ 같은 캐시 매니저(EditImageCacheManager)로 precache해서 "즉시 표시" 확률을 높인다.
    // 🎯 비디오 URL인 경우: precache 스킵 (이미지로 로드할 수 없음)
    final thumb = _exportedThumbnailImageUrl.trim();
    if (thumb.isNotEmpty &&
        (thumb.startsWith('http://') || thumb.startsWith('https://'))) {
      // 🎯 비디오 URL인지 확인
      final lowerUrl = thumb.toLowerCase();
      final isVideo =
          lowerUrl.endsWith('.mp4') ||
          lowerUrl.endsWith('.mov') ||
          lowerUrl.endsWith('.m4v') ||
          lowerUrl.contains('/videos/') ||
          lowerUrl.contains('video');

      // 🎯 비디오 URL인 경우: 표준 방식으로 처리
      if (isVideo) {
        _cachedVideoUrl = thumb;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            // 🎯 표준 방식: 직접 컨트롤러 생성
            _videoController = VideoPlayerController.networkUrl(
              Uri.parse(thumb),
              httpHeaders: const {
                'Accept': 'video/*',
                'Connection': 'keep-alive',
              },
              videoPlayerOptions: VideoPlayerOptions(
                mixWithOthers: false,
                allowBackgroundPlayback: false,
              ),
            );

            // 리스너 추가
            _videoController!.addListener(_onVideoControllerInitialized);

            // 초기화 시작
            _videoController!
                .initialize()
                .then((_) {
                  if (!mounted || _videoController == null) return;
                  try {
                    _videoController!.play();
                    _videoController!.setLooping(true);
                    if (mounted) setState(() {});
                  } catch (e) {
                    debugPrint('[PostExport] 초기화 후 설정 오류: $e');
                  }
                })
                .catchError((e) {
                  debugPrint('[PostExport] 초기화 실패: $e');
                });
          } catch (e) {
            debugPrint('[PostExport] 서버 비디오 컨트롤러 생성 오류: $e');
            _videoController = null;
            _cachedVideoUrl = null;
          }
        });
      } else {
        // 🎯 이미지 URL인 경우: EditorImageProvider를 사용하여 step1_thumbnail_edit과 동일한 캐시 키 사용
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            final screenWidth = MediaQuery.sizeOf(context).width;
            final decodeWidth = EditorImageProvider.editingDecodeWidth(
              context,
              screenWidth,
            );
            final built = EditorImageProvider.build(
              url: thumb,
              isEditing: true,
              decodeWidth: decodeWidth,
            );
            precacheImage(built.effectiveProvider, context).catchError((_) {});
          } catch (_) {}
        });
      }
    }

    // ✅ 수정 모드에서는 영상 파일/썸네일 복원을 하지 않음 (서버 원본 사용)
    if (widget.isEditMode) {
      // 수정 모드: 로컬 임시 파일 복원 스킵
      debugPrint('[PostExport] 수정 모드: 영상 파일/썸네일 복원 스킵');
    } else {
      // 영상 파일만 복원 (persist 사용)
      final svc = NodeComponentService();
      final persistedVideoPath = svc.getTempVideoFilePath(_nsKey);
      final persistedVideoThumbnailPath = svc.getTempVideoThumbnailPath(_nsKey);

      // 영상 파일 복원 (있다면)
      if (persistedVideoPath != null && persistedVideoPath.isNotEmpty) {
        final videoFile = File(persistedVideoPath);
        if (videoFile.existsSync()) {
          _localVideoFile = videoFile;

          // 🎯 기존 컨트롤러 안전하게 dispose
          _disposeVideoController(context: '_hydrateFromExported');

          // 🎯 로컬 비디오는 직접 관리 (VideoCacheService 불필요)
          try {
            final controller = VideoPlayerController.file(videoFile);

            // 🎯 컨트롤러 참조 저장 (비동기 콜백에서 dispose 체크용)
            final controllerRef = controller;

            _videoController = controller;

            // 🎯 dispose 체크: 리스너 추가 전 컨트롤러 유효성 확인
            try {
              controller.addListener(_onVideoControllerInitialized);
            } catch (e) {
              debugPrint('[PostExport] 리스너 추가 오류 (dispose됨): $e');
              _videoController = null;
              return;
            }

            controller
                .initialize()
                .then((_) {
                  // 🎯 dispose 체크 강화: mounted, controller 유효성, 참조 일치 확인
                  if (!mounted || _videoController != controllerRef) {
                    try {
                      controllerRef.dispose();
                    } catch (_) {}
                    return;
                  }

                  try {
                    // 🎯 dispose 체크: 컨트롤러 유효성 확인
                    if (controllerRef.value.isInitialized) {
                      controllerRef.play();
                      controllerRef.setLooping(true);
                      if (mounted) {
                        setState(() {});
                      }
                    }
                  } catch (e) {
                    debugPrint('[PostExport] 비디오 재생 오류 (dispose됨): $e');
                  }
                })
                .catchError((error) {
                  debugPrint('[PostExport] 비디오 컨트롤러 초기화 실패: $error');
                  if (!mounted) return;

                  // 🎯 컨트롤러가 여전히 유효한지 확인
                  if (_videoController == controllerRef) {
                    _disposeVideoController(
                      context: '_hydrateFromExported.catchError',
                    );
                    setState(() {});
                  }
                });
          } catch (e) {
            debugPrint('[PostExport] 비디오 컨트롤러 생성 오류: $e');
            _videoController = null;
          }
          debugPrint('[PostExport] 영상 파일 복원: $persistedVideoPath');

          // 영상 로컬 썸네일도 복원
          if (persistedVideoThumbnailPath != null &&
              persistedVideoThumbnailPath.isNotEmpty) {
            final thumbnailFile = File(persistedVideoThumbnailPath);
            if (thumbnailFile.existsSync()) {
              _localThumbnailFile = thumbnailFile;
              debugPrint(
                '[PostExport] 영상 썸네일 복원: $persistedVideoThumbnailPath',
              );
            }
          }
        } else {
          debugPrint('[PostExport] 영상 파일이 존재하지 않음: $persistedVideoPath');
          svc.clearTempVideoFile(_nsKey);
        }
      }
    }

    // 🎯 summary/excerpt 필드 제거됨 - 이제 node를 직접 검사

    // 🎯 수정 모드일 때 초기값 설정, 아니면 exported에서 파싱
    if (widget.isEditMode) {
      // 수정 모드: 전달받은 초기값 사용
      if (widget.initialAccessLevel != null &&
          widget.initialAccessLevel!.isNotEmpty) {
        _currentAccessLevel = widget.initialAccessLevel!;
      }
    } else {
      // 발행 모드: exported에서 파싱
      try {
        // 🎯 공통 파싱 유틸리티 사용
        final level =
            AccessLevelParser.parseAccessLevelString(exported['accessLevel']) ??
            '';

        // 공개범위 초기화 (exported에 값이 있으면 우선 사용)
        if (level == SystemCategoryKeys.private) {
          _currentAccessLevel = SystemCategoryKeys.private;
        } else if (level == SystemCategoryKeys.public) {
          _currentAccessLevel = SystemCategoryKeys.public;
        } else if (level == SystemCategoryKeys.friends) {
          _currentAccessLevel = SystemCategoryKeys.friends;
        } else {
          // exported에 값이 없으면 글 타입에 따른 기본값 사용
          _currentAccessLevel = _getDefaultAccessLevelForWriteMode(
            widget.writeMode,
          );
        }
      } catch (_) {}
    }
    setState(() {});
  }

  /// ✅ 글 타입에 따른 기본 공개범위 반환
  String _getDefaultAccessLevelForWriteMode(PostWriteMode? writeMode) {
    switch (writeMode) {
      case PostWriteMode.militaryLife:
        // 부대 기록: 개인적인 내용이므로 비공개
        return SystemCategoryKeys.private;
      case PostWriteMode.leaveOrPreEnlistment:
        // 휴가 모드: 기본값 전체공개
        return SystemCategoryKeys.public;
      case PostWriteMode.public:
        // 공개 글: 전체공개
        return SystemCategoryKeys.public;
      case PostWriteMode.letter:
        // 편지: 특정 수신인에게 보내는 것이므로 비공개
        return SystemCategoryKeys.private;
      case PostWriteMode.promise:
        // 약속: 친구들과 공유하는 것이 적절
        return SystemCategoryKeys.friends;
      case null:
        // 글 타입이 없으면 기본값 전체공개
        return SystemCategoryKeys.public;
    }
  }

  // 🎯 비디오 컨트롤러 안전하게 dispose하는 헬퍼 메서드
  void _disposeVideoController({String? context}) {
    if (_videoController == null) return;

    // 🎯 표준 방식: 모든 컨트롤러 dispose
    try {
      _videoController!.removeListener(_onVideoControllerInitialized);
      if (_videoController!.value.isInitialized) {
        _videoController!.pause();
      }
      _videoController!.dispose();
      debugPrint('[PostExport] ${context ?? "dispose"}: 컨트롤러 dispose 완료');
    } catch (e) {
      debugPrint('[PostExport] ${context ?? "dispose"}: 컨트롤러 dispose 오류: $e');
    }

    _videoController = null;
    _cachedVideoUrl = null;
  }

  // 🎯 비디오 컨트롤러 초기화 완료 리스너
  void _onVideoControllerInitialized() {
    // 🎯 dispose 체크: mounted 및 컨트롤러 유효성 확인
    if (!mounted || _videoController == null) {
      // dispose된 경우 리스너 제거 시도
      try {
        _videoController?.removeListener(_onVideoControllerInitialized);
      } catch (_) {}
      return;
    }

    // 🎯 컨트롤러 참조 저장 (리스너 제거 전에)
    final controller = _videoController!;

    try {
      // 🎯 dispose 체크: 컨트롤러 유효성 확인
      if (controller.value.isInitialized) {
        // 🎯 리스너 제거 (먼저 제거하여 재진입 방지)
        try {
          controller.removeListener(_onVideoControllerInitialized);
        } catch (e) {
          debugPrint('[PostExport] 리스너 제거 오류 (dispose됨): $e');
          return;
        }

        if (mounted) {
          try {
            controller.play();
            controller.setLooping(true);
            setState(() {});
          } catch (e) {
            debugPrint('[PostExport] 비디오 재생 오류 (dispose됨): $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[PostExport] 비디오 컨트롤러 초기화 리스너 오류 (dispose됨): $e');
      // dispose된 경우 리스너 제거 시도
      try {
        controller.removeListener(_onVideoControllerInitialized);
      } catch (_) {}
    }
  }

  // 부드러운 애니메이션과 함께 닫기
  Future<void> _closeWithAnimation() async {
    _cancelUploadTasks();

    // 🎯 로컬 비디오 컨트롤러 직접 dispose
    _disposeVideoController(context: '_closeWithAnimation');

    // 닫힐 때는 빠르게 (250ms)
    _intro.duration = const Duration(milliseconds: 250);
    await _intro.reverse();
    // 다시 원래 duration으로 복원
    _intro.duration = const Duration(milliseconds: 800);

    if (!mounted || !context.mounted) return;

    Navigator.of(context).pop({
      'thumbnailImageUrl': _exportedThumbnailImageUrl,
      'title': _titleController.text.trim(),
      // 🎯 summary 필드 제거됨
    });
  }

  // 🎯 본문(content)이 있는지 확인하는 헬퍼 함수
  bool _hasContent() {
    try {
      final dynamic content = _exportedBase['content'];
      if (content is Map) {
        final List<dynamic> nodes = List<dynamic>.from(
          content['nodes'] as List? ?? const [],
        );
        // 노드가 하나라도 있으면 본문이 있는 것으로 간주
        return nodes.isNotEmpty;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // 등록 가능 여부 확인 (서버 API 스펙 준수)
  bool _canPublish() {
    // 1. 기본 상태 확인
    if (_isUploading || _isUploadingThumb) {
      return false;
    }

    // 2. 필수 필드 확인 (편집된 내용 기준)
    final editedTitle = _titleController.text.trim();

    if (editedTitle.isEmpty) {
      return false;
    }

    // 🎯 본문(content)이 있는지 확인
    if (!_hasContent()) {
      return false;
    }

    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return false;
    }

    // 3. 공개범위 확인 (항상 선택되어 있음)

    return true;
  }

  // 등록 불가능할 때 표시할 에러 메시지 (서버 API 스펙 준수)
  String _getPublishErrorMessage() {
    if (_isUploadingThumb) {
      return context.tr('image_uploading');
    }
    final editedTitle = _titleController.text.trim();

    if (editedTitle.isEmpty) {
      return context.tr('title_required');
    }

    // 🎯 본문(content)이 있는지 확인
    if (!_hasContent()) {
      return context.tr('content_required');
    }

    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return context.tr('thumbnail_required');
    }
    // 공개범위는 항상 선택되어 있음
    return context.tr('cannot_publish');
  }

  /// 🎯 공통 검증 로직
  String? _validateInputs() {
    final finalTitle = _titleController.text.trim();

    if (finalTitle.isEmpty) {
      return context.tr('title_required');
    }

    if (!_hasContent()) {
      return context.tr('content_required');
    }

    final trimmedThumbnailUrl = _exportedThumbnailImageUrl.trim();
    if (trimmedThumbnailUrl.isEmpty) {
      return context.tr('thumbnail_required');
    }

    final isHttpUrl =
        trimmedThumbnailUrl.startsWith('http://') ||
        trimmedThumbnailUrl.startsWith('https://');
    if (!isHttpUrl) {
      return context.tr('thumbnail_upload_required');
    }

    return null; // 검증 통과
  }

  /// 🎯 수정 모드: 포스트 업데이트
  Future<void> _updatePost() async {
    try {
      // 검증
      final validationError = _validateInputs();
      if (validationError != null) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('error'),
          message: validationError,
        );
        return;
      }

      if (widget.postId == null) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('error'),
          message: context.tr('invalid_post_id'),
        );
        return;
      }

      cleanupAllVideoPlayers();

      final finalTitle = _titleController.text.trim();
      final content = _exportedBase['content'] as Map<String, dynamic>?;
      if (content == null) {
        throw Exception('본문 데이터를 추출할 수 없습니다.');
      }

      // ✅ 변경 감지 (본문/스티커 + 메타데이터)
      final initialMap = _initialExportedForComparisonMap;
      final initialTitle = (initialMap?['title'] ?? '').toString().trim();
      final initialThumbnail =
          (initialMap?['thumbnailImageUrl'] ?? '').toString().trim();
      final initialAccessLevel =
          AccessLevelParser.parseAccessLevelString(
            initialMap?['accessLevel'],
          ) ??
          (widget.initialAccessLevel?.trim().isNotEmpty ?? false
              ? widget.initialAccessLevel!.trim()
              : SystemCategoryKeys.public);

      final currentThumbnail = _exportedThumbnailImageUrl.trim();
      final currentAccessLevel = _currentAccessLevel.trim();

      final titleChanged = finalTitle != initialTitle;
      final thumbnailChanged = currentThumbnail != initialThumbnail;
      final accessLevelChanged = currentAccessLevel != initialAccessLevel;

      // 본문 변경은 exported(Map) 비교로 판단 (노드 id 등은 ContentChangeDetector에서 무시)
      final contentChanged =
          (initialMap != null)
              ? ContentChangeDetector.hasExportedContentChanged(
                originalExported: initialMap,
                currentExported: _exportedBase,
              )
              : true; // 원본이 없으면 안전하게 변경된 것으로 간주

      final hasAnyChange =
          contentChanged ||
          titleChanged ||
          thumbnailChanged ||
          accessLevelChanged;

      debugPrint(
        '[PostExportScreen] 변경 감지: content=$contentChanged, title=$titleChanged, thumbnail=$thumbnailChanged, accessLevel=$accessLevelChanged',
      );

      // ✅ 썸네일을 "선택/변경"했는데도 URL 비교상 동일해서 '변경사항 없음'으로 떨어지는 케이스 방지
      // - 특히 영상 썸네일은 로컬 상태(영상/포스터) 변화가 먼저 일어나고, URL 반영은 약간 늦을 수 있음
      final hasLocalThumbState =
          _localVideoFile != null || _localThumbnailFile != null;
      if (!hasAnyChange &&
          _thumbnailTouchedInSession &&
          hasLocalThumbState &&
          !thumbnailChanged) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ErrorHandler.showInfo(
            ctx,
            '썸네일 업로드/반영이 아직 완료되지 않았어요.\n잠시 후 다시 시도해 주세요.',
            duration: const Duration(seconds: 2),
          );
        }
        return;
      }

      if (!hasAnyChange) {
        if (!mounted) return;
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ErrorHandler.showInfo(
            ctx,
            '변경사항이 없습니다.',
            duration: const Duration(seconds: 2),
          );
        }
        return;
      }

      setState(() {
        _isUploading = true;
      });

      // 사용된 미디어 URL 수집
      final usedImageUrls = PostExporter.collectUsedMediaUrls(_exportedBase);
      final mentionedUsernames = MentionedUsernamesExtractor.extractFromContent(
        content,
      );

      // 🎯 연도와 주차 결정
      int? year;
      int? nthWeek;
      if (widget.initialYear != null && widget.initialYearOfWeek != null) {
        year = widget.initialYear;
        nthWeek = widget.initialYearOfWeek;
      }

      final postIdInt = int.parse(widget.postId!);

      // ✅ 1) 본문이 바뀐 경우만 content 엔드포인트 호출 (필요 시 title도 함께)
      if (contentChanged) {
        await BlogService().updatePostContent(
          postId: postIdInt,
          content: content,
          title: titleChanged ? finalTitle : null,
          usedImageUrls: usedImageUrls,
          mentionedUsernames: mentionedUsernames,
          year: year,
          nthWeek: nthWeek,
        );
      }

      // ✅ 2) 썸네일/제목만 바뀐 경우엔 thumbnail 엔드포인트로 (content는 안 보냄)
      // - contentChanged가 false인데 titleChanged/thumbnailChanged 중 하나라도 true면 여기서 처리
      // - contentChanged가 true일 때는 "썸네일"만 별도로 처리 (제목은 updatePostContent로 처리 가능)
      if (thumbnailChanged || (!contentChanged && titleChanged)) {
        await BlogService().updatePostThumbnail(
          postId: postIdInt,
          thumbnailImageUrl: thumbnailChanged ? currentThumbnail : null,
          title: (!contentChanged && titleChanged) ? finalTitle : null,
        );
      }

      // ✅ 3) 공개범위 변경은 전용 엔드포인트로
      if (accessLevelChanged) {
        await BlogService().updatePostAccessLevel(
          postId: postIdInt,
          accessLevel: currentAccessLevel,
        );
      }

      if (!mounted) return;

      // 🎯 publish처럼 바로 화면 닫기 (PostExportScreen + PostWriteScreen)
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);

      // 🎯 스낵바 표시
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ErrorHandler.showInfo(
          ctx,
          '포스트가 수정되었습니다.',
          duration: const Duration(seconds: 2),
        );
      }

      // 🎯 피드 업데이트 (백그라운드)
      try {
        final feed = MyProfileFeedProvider();
        final exportedForUpdate = Map<String, dynamic>.from(_exportedBase);
        exportedForUpdate['title'] = finalTitle;
        exportedForUpdate['thumbnailImageUrl'] = _exportedThumbnailImageUrl;
        exportedForUpdate['accessLevel'] = _currentAccessLevel;
        exportedForUpdate['id'] = int.parse(widget.postId!);
        feed.updatePostInCache(exportedForUpdate);
        debugPrint('[PostExportScreen] ✅ 피드 업데이트 완료');
      } catch (e) {
        debugPrint('[PostExportScreen] ⚠️ 피드 업데이트 실패: $e');
      }
    } catch (e) {
      debugPrint('Update failed: $e');

      if (!mounted) return;

      final action = await RetryCancelBottomSheet.show(
        context,
        title: context.tr('edit_failed_title'),
        error: e,
      );
      if (!mounted) return;
      if (action == RetryCancelAction.retry) {
        await _updatePost();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// ✅ militaryInfo 기반으로 현재 phase 계산
  String? _calculatePhaseFromMilitaryInfo() {
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    if (currentUser == null) return null;

    // ✅ 곰신의 경우 연결된 남친의 militaryInfo 사용
    final militaryInfo =
        currentUser.connectedMilitaryUser?.militaryInfo ??
        currentUser.militaryInfo;
    if (militaryInfo == null) return null;

    final userStatus = militaryInfo.status;
    final currentRank = militaryInfo.currentRank;

    if (userStatus == MilitaryStatus.beforeEnlistment) {
      return 'preEnlistment';
    } else if (userStatus == MilitaryStatus.afterEnlistment &&
        currentRank != null) {
      switch (currentRank) {
        case MilitaryRank.trainee:
          return 'training';
        case MilitaryRank.private:
          return 'private';
        case MilitaryRank.privateFirstClass:
          return 'privateFirstClass';
        case MilitaryRank.corporal:
          return 'corporal';
        case MilitaryRank.sergeant:
          return 'sergeant';
      }
    }

    return null;
  }

  /// 🎯 발행 모드: 새 포스트 발행
  Future<void> _publish() async {
    try {
      String? recipientUsername;
      String? writingType;
      String? phase;

      // ✅ letter 모드일 때 발송 대상 선택
      if (widget.writeMode == PostWriteMode.letter) {
        final recipient = await _showLetterRecipientSelection();
        if (recipient == null) {
          // 사용자가 취소한 경우
          return;
        }
        // ✅ username을 직접 사용 (서버에서 username으로 조회)
        recipientUsername = recipient.username;

        // ✅ 편지 모드: writingType은 서버가 자동으로 LETTER로 설정하지만, 명시적으로도 설정 가능
        writingType = 'LETTER';
      } else if (widget.writeMode == PostWriteMode.promise) {
        // ✅ API 명세: Promise 모드 - writingType=PROMISE, accessLevel=PRIVATE
        writingType = 'PROMISE';
        // Promise는 반드시 PRIVATE이어야 함
        if (_currentAccessLevel.toUpperCase() !=
            SystemCategoryKeys.private.toUpperCase()) {
          await DialogUtils.showInfoDialog(
            context,
            title: context.tr('error'),
            message: '목표(Promise) 글은 공개범위가 나만보기(PRIVATE)이어야 합니다.',
          );
          return;
        }
        debugPrint('[PostExportScreen] Promise 모드: writingType=PROMISE');
      } else if (widget.writeMode == PostWriteMode.militaryLife) {
        // ✅ MILITARY_LIFE 모드: writingType 설정
        writingType = 'MILITARY_LIFE';
      }

      // ✅ 여친이 쓴 글이 아닐 때 항상 phase 보내기
      final userProvider = context.read<UserProvider>();
      final currentUser = userProvider.currentUser;
      final isGirlfriend =
          currentUser?.militaryInfo?.userType == UserType.girlfriend;
      final requiresPhase = !isGirlfriend; // ✅ 여친이 아닐 때 항상 phase 필요

      if (requiresPhase) {
        // ✅ militaryInfo 기반으로 현재 phase 계산
        phase = _calculatePhaseFromMilitaryInfo();
        if (phase == null) {
          await DialogUtils.showInfoDialog(
            context,
            title: context.tr('error'),
            message: '군 정보를 확인할 수 없어 글을 발행할 수 없습니다.',
          );
          return;
        }
        debugPrint(
          '[PostExportScreen] phase 계산 완료: $phase (writingType=$writingType, isGirlfriend=$isGirlfriend)',
        );
      } else {
        debugPrint(
          '[PostExportScreen] phase 생략 (여친이 쓴 글: isGirlfriend=$isGirlfriend)',
        );
      }

      // 검증
      final validationError = _validateInputs();
      if (validationError != null) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('error'),
          message: validationError,
        );
        return;
      }

      final finalTitle = _titleController.text.trim();

      int? year;
      int? nthWeek;
      if (widget.initialYear != null && widget.initialYearOfWeek != null) {
        year = widget.initialYear;
        nthWeek = widget.initialYearOfWeek;
        debugPrint(
          '[PostExportScreen] 지정된 연도/주차 사용: year=$year, nthWeek=$nthWeek',
        );
      } else {
        debugPrint(
          '[PostExportScreen] 현재 주차 기준 사용 (initialYear/initialYearOfWeek 없음)',
        );
      }

      // ✅ 친구공개(친구지정)일 때 선택한 친구 목록을 exportedBase에 포함
      if (_currentAccessLevel.toUpperCase() ==
          SystemCategoryKeys.friends.toUpperCase()) {
        _exportedBase['selectedFriends'] = _selectedFriends;
      }

      // 🎯 아래 모든 로직은 Provider(백그라운드)의 몫
      // - payload 생성/업로드/피드갱신/실패 다이얼로그/완료 ShareOverlay 표시
      context.read<PublishProvider>().startPublish(
        PublishRequest(
          exportedBase: _exportedBase,
          title: finalTitle,
          thumbnailImageUrl: _exportedThumbnailImageUrl,
          accessLevel: _currentAccessLevel,
          year: year,
          nthWeek: nthWeek,
          sessionKey: widget.sessionKey,
          isOnboardingMode: widget.isOnboardingMode, // 🎯 온보딩 모드 전달
          lifePhase: widget.writeMode?.toLifePhase(), // 🎯 작성 모드 전달
          recipientUsername: recipientUsername, // ✅ 편지 모드: 수신인 username (필수)
          writingType: writingType, // ✅ 글 타입 (LETTER, PROMISE 등)
          phase: phase, // ✅ 복무 단계 코드 (MILITARY_LIFE일 때 필수)
        ),
      );

      // 🎯 일반 모드: 요청 던지고 즉시 화면 닫기 (PostExportScreen + PostWriteScreen)
      // ✅ 온보딩 모드: PublishProvider가 즉시 Splash로 네비게이션하므로 여기서 popUntil 하면 레이스가 날 수 있다.
      if (!mounted) return;
      if (!widget.isOnboardingMode) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      debugPrint('Upload failed: $e');

      if (!mounted) return;

      // 🎯 실패 UX: 스낵바 대신 재시도/취소 바텀시트 (등록/발행)
      final action = await RetryCancelBottomSheet.show(
        context,
        title: context.tr('publish_failed_title'),
        error: e,
      );
      if (!mounted) return;
      if (action == RetryCancelAction.retry) {
        await _publish();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Widget _buildDynamicBackground() {
    return Positioned.fill(
      child: Container(color: Theme.of(context).colorScheme.surface),
    );
  }

  /// 업로드 태스크 취소 헬퍼
  void _cancelUploadTasks() {
    try {
      // 🎯 dispose()에서도 안전하게 사용하기 위해 저장된 참조 사용
      final upload = _uploadService;
      if (upload != null) {
        upload.cancelByRef('thumb_$_nsKey');
        upload.cancelEditorCompressions('publish_$_nsKey');
      } else if (mounted) {
        // 🎯 mounted 상태이고 참조가 없으면 context에서 가져오기 (일반적인 경우)
        try {
          final uploadFromContext = context.read<UploadService>();
          uploadFromContext.cancelByRef('thumb_$_nsKey');
          uploadFromContext.cancelEditorCompressions('publish_$_nsKey');
        } catch (e) {
          debugPrint('[PostExport] 업로드 태스크 취소 오류 (context): $e');
        }
      }
    } catch (e) {
      debugPrint('[PostExport] 업로드 태스크 취소 오류: $e');
    }
  }

  // 🎯 Step 2, 3 제거됨 - 더 이상 step 이동 없음

  @override
  Widget build(BuildContext context) {
    final cardRadius = 12.0; // PostCard와 동일한 라운드

    return WillPopScope(
      onWillPop: () async {
        // 🎯 업로드 중에는 다이얼로그 표시 후 뒤로 가기 차단
        if (_isUploading || _isUploadingThumb) {
          await DialogUtils.showInfoDialog(
            context,
            title: context.tr('uploading'),
            message:
                _isUploadingThumb
                    ? context.tr('image_uploading')
                    : context.tr('uploading'),
          );
          return false;
        }

        // 뒤로가기 시 부드러운 애니메이션과 함께 닫기
        await _closeWithAnimation();
        return false; // WillPopScope가 직접 처리하지 않도록 false 반환
      },
      child: FadeTransition(
        opacity: _intro,
        child: Stack(
          children: [
            _buildDynamicBackground(),
            // ✅ 하트 파티클 오버레이 (letter 모드에서 여친만 선택되었을 때)
            ..._heartParticles.map((particle) {
              return AnimatedBuilder(
                animation: particle.controller,
                builder: (context, child) {
                  final progress = particle.controller.value;
                  final curve = Curves.easeOut.transform(progress);

                  // 위로 이동 (페이드아웃) - 약하게
                  final offsetY = -curve * 180; // 최대 180px 위로 (약하게)
                  final offsetX =
                      math.sin(progress * math.pi * 2) *
                      particle.horizontalOffset *
                      curve; // 좌우 흔들림

                  // 페이드아웃
                  final opacity =
                      (1.0 - progress).clamp(0.0, 1.0) * 0.6; // ✅ 약하게: 최대 0.6

                  // 스케일 (작아지면서 사라짐)
                  final scale = 1.0 - progress * 0.3;

                  // 회전
                  final rotation =
                      particle.rotation +
                      progress * math.pi * 0.5; // ✅ 약하게: 회전 속도 감소

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
            Scaffold(
              backgroundColor: Colors.transparent,
              extendBodyBehindAppBar: true,
              appBar: _editMode ? _buildFocusAppBar() : _buildNormalAppBar(),
              body: SafeArea(
                child: GestureDetector(
                  onTap: () {
                    // 🎯 편집 모드가 활성화되어 있을 때 여백을 탭하면 편집 모드 닫기
                    if (_editMode) {
                      _titleFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _editMode = false;
                      });
                      _controller.reverse();
                      // 추가로 포커스가 완전히 해제될 때까지 약간 대기
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (mounted) {
                          _titleFocusNode.unfocus();
                          FocusScope.of(context).unfocus();
                        }
                      });
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Step1ThumbnailEdit(
                    sessionKey: _nsKey,
                    cardRadius: cardRadius,
                    titleController: _titleController,
                    titleFocusNode: _titleFocusNode,
                    exportedThumbnailImageUrl: _exportedThumbnailImageUrl,
                    editMode: _editMode,
                    isUploadingThumb: _isUploadingThumb,
                    isLoading:
                        _showInitialThumbnailShimmer &&
                        _exportedThumbnailImageUrl.trim().isEmpty &&
                        _localThumbnailFile == null &&
                        _localVideoFile == null,
                    localThumbnailFile: _localThumbnailFile,
                    localVideoFile: _localVideoFile,
                    videoController: _videoController,
                    controller: _controller,
                    onThumbnailUrlChanged: (url) {
                      setState(() {
                        _exportedThumbnailImageUrl = url;
                        _thumbnailTouchedInSession = true;
                      });
                    },
                    onLocalThumbnailChanged: (file) {
                      setState(() {
                        _localThumbnailFile = file;
                        if (file != null) _thumbnailTouchedInSession = true;
                      });
                    },
                    onLocalVideoChanged: (file) {
                      setState(() {
                        _localVideoFile = file;
                        if (file != null) _thumbnailTouchedInSession = true;
                      });
                    },
                    onVideoControllerChanged: (controller) {
                      // 🎯 기존 컨트롤러 안전하게 정리
                      if (_videoController != null &&
                          _videoController != controller) {
                        // 🎯 서버 비디오 컨트롤러인 경우 _cachedVideoUrl 초기화
                        if (_cachedVideoUrl != null) {
                          _cachedVideoUrl = null;
                        }
                        _disposeVideoController(
                          context: 'onVideoControllerChanged',
                        );
                      }

                      // 🎯 새 컨트롤러 설정 및 리스너 추가
                      _videoController = controller;
                      if (controller != null) {
                        _localVideoFile = null; // Step1에서 새로 생성한 컨트롤러
                        _cachedVideoUrl = null; // 로컬 비디오이므로 서버 비디오 URL 초기화
                        try {
                          // 🎯 dispose 체크: 컨트롤러 유효성 확인
                          if (!controller.value.isInitialized) {
                            // 🎯 리스너 추가 전 dispose 체크
                            try {
                              controller.addListener(
                                _onVideoControllerInitialized,
                              );
                            } catch (e) {
                              debugPrint(
                                '[PostExport] 리스너 추가 오류 (dispose됨): $e',
                              );
                              _videoController = null;
                              return;
                            }
                          } else {
                            // 이미 초기화된 경우 즉시 재생
                            if (mounted) {
                              try {
                                // 🎯 dispose 체크: 컨트롤러 유효성 재확인
                                if (controller.value.isInitialized) {
                                  controller.play();
                                  controller.setLooping(true);
                                }
                              } catch (e) {
                                debugPrint(
                                  '[PostExport] 새 컨트롤러 재생 오류 (dispose됨): $e',
                                );
                              }
                            }
                          }
                        } catch (e) {
                          debugPrint(
                            '[PostExport] 새 컨트롤러 설정 오류 (dispose됨): $e',
                          );
                        }
                      }

                      if (mounted) {
                        setState(() {});
                      }
                    },
                    onIsUploadingThumbChanged: (value) {
                      setState(() {
                        _isUploadingThumb = value;
                      });
                    },
                    onEditModeChanged: (value) {
                      setState(() {
                        _editMode = value;
                      });
                    },
                    // ✅ Step1 내부에서 포커스/애니메이션을 관리한다.
                    // (중복 리스너로 인한 불필요한 setState 루프 방지)
                    onEditFocusChange: () {},
                  ),
                ),
              ),

              bottomNavigationBar: _buildBottomNavigationBar(),
            ),
          ],
        ),
      ),
    );
  }

  // 포커스 상태의 간단한 앱바 (완료 버튼만)
  PreferredSizeWidget _buildFocusAppBar() {
    final textColor = Theme.of(context).colorScheme.onSurface;

    return AppBar(
      toolbarHeight: 53,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: true,

      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: TextButton(
            onPressed: () {
              // 🎯 수정완료 시 명시적으로 포커스 노드 모두 해제
              _titleFocusNode.unfocus();
              FocusScope.of(context).unfocus();

              setState(() {
                _editMode = false;
              });
              _controller.reverse();

              // 추가로 포커스가 완전히 해제될 때까지 약간 대기
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  _titleFocusNode.unfocus();
                  FocusScope.of(context).unfocus();
                }
              });
            },
            child: Text(
              context.tr('modify_complete'),
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 일반 상태의 앱바 (진행바와 다음/업로드 버튼)
  PreferredSizeWidget _buildNormalAppBar() {
    final textColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.75);

    return AppBar(
      toolbarHeight: 56,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,

      // 이전 버튼이 잘리지 않도록 너비 확장
      leading: GestureDetector(
        onTap: () async {
          // 뒤로가기 시 부드러운 애니메이션
          await _closeWithAnimation();
        },
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 24,
          color: textColor,
        ),
      ),

      // 중앙에 year, yearOfWeek 표시 (있는 경우만)
      title:
          widget.initialYear != null && widget.initialYearOfWeek != null
              ? Text(
                '${widget.initialYear}년 ${widget.initialYearOfWeek}주차',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor.withOpacity(0.8),
                ),
              )
              : null,
      centerTitle: true,

      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: TextButton(
            onPressed:
                _isUploading
                    ? null
                    : () async {
                      final bool canPublish = _canPublish();
                      if (canPublish) {
                        // 🎯 수정 모드면 업데이트, 발행 모드면 발행
                        if (widget.isEditMode) {
                          await _updatePost();
                        } else {
                          await _publish();
                        }
                      } else {
                        String msg = _getPublishErrorMessage();
                        await DialogUtils.showInfoDialog(
                          context,
                          title: context.tr('error'),
                          message: msg,
                        );
                      }
                    },
            child:
                _isUploading
                    ? Container(
                      key: const ValueKey('loading'),
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    )
                    : Text(
                      widget.isEditMode
                          ? context.tr('modify_complete')
                          : context.tr('publish'),
                      key: ValueKey(widget.isEditMode ? 'edit' : 'publish'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  // 🎯 공개범위 이름 가져오기
  String _getAccessLevelName(String accessLevel) {
    if (accessLevel == SystemCategoryKeys.private) {
      return context.tr('private');
    } else if (accessLevel == SystemCategoryKeys.friends) {
      return context.tr('friends');
    } else {
      return context.tr('public');
    }
  }

  // 🎯 하단 네비게이션 바 (공개범위 선택 또는 letter 모드 친구 목록)
  Widget _buildBottomNavigationBar() {
    // ✅ letter 모드일 때는 선택한 친구 목록 표시
    if (widget.writeMode == PostWriteMode.letter) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 12,
          ), // ✅ horizontal 패딩 제거
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: _buildLetterRecipientsDisplay(),
        ),
      );
    }

    // ✅ 친구공개(친구지정)일 때는 친구 선택 UI 표시
    final isFriendsAccess =
        _currentAccessLevel.toUpperCase() ==
        SystemCategoryKeys.friends.toUpperCase();

    debugPrint(
      '[PostExportScreen] _buildBottomNavigationBar: _currentAccessLevel=$_currentAccessLevel, isFriendsAccess=$isFriendsAccess, _selectedFriends.length=${_selectedFriends.length}',
    );

    if (isFriendsAccess) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 12,
          ), // ✅ horizontal 패딩 제거
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: _buildFriendsSelectionDisplay(),
        ),
      );
    }

    // 일반 모드: 공개범위 선택 버튼
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
        child: Row(
          children: [
            // 공개범위 선택 버튼
            Expanded(
              child: _buildSelectionButton(
                icon: Icons.lock_outline,
                label: _getAccessLevelName(_currentAccessLevel),
                onTap: () async {
                  // 공개범위 선택 시트 표시 (지정 모드로 호출)
                  AccessLevelSheet.show(
                    context,
                    postId: 'new', // 새 포스트이므로 임시 ID
                    currentAccessLevel: _currentAccessLevel,
                    mode: AccessLevelSelectMode.selectionOnly, // 🎯 지정 모드
                    onChanged: (accessLevel) {
                      setState(() {
                        _currentAccessLevel = accessLevel;
                        // 친구공개가 아닌 경우 선택한 친구 목록 초기화
                        if (accessLevel.toUpperCase() !=
                            SystemCategoryKeys.friends.toUpperCase()) {
                          _selectedFriends = [];
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ 여친만 선택되었는지 확인 (친구공개 모드용)
  bool _isOnlyPartnerSelectedForFriends(List<Map<String, dynamic>> friends) {
    if (friends.length != 1) return false;

    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    User? partner;
    if (currentUser != null) {
      final userType = currentUser.militaryInfo?.userType;
      if (userType == UserType.girlfriend) {
        partner = currentUser.connectedMilitaryUser;
      } else if (userType == UserType.military ||
          userType == UserType.plannedEnlistment) {
        partner = currentUser.connectedToMeByUser;
      }
    }

    if (partner == null) return false;

    final selectedFriend = friends.first;
    return selectedFriend['username'] == partner.username;
  }

  // ✅ 친구공개(친구지정): 선택한 친구 목록 표시
  Widget _buildFriendsSelectionDisplay() {
    debugPrint(
      '[PostExportScreen] _buildFriendsSelectionDisplay: _selectedFriends.length=${_selectedFriends.length}',
    );

    if (_selectedFriends.isEmpty) {
      return GestureDetector(
        onTap: () => _openFriendSelection(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.person_add_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 12),
              Text(
                '친구 선택',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ 여친만 선택되었는지 확인
    final isOnlyPartner = _isOnlyPartnerSelectedForFriends(_selectedFriends);
    final showAddButton = !isOnlyPartner; // ✅ 여친만 있으면 + 버튼 숨김

    // ✅ 여친(짝궁) 1명만 선택된 경우: 리스트 UI는 숨기고 높이만 유지
    // - UX: 하트 파티클(다른 오버레이)만으로 충분
    if (isOnlyPartner) {
      return const SizedBox(width: double.infinity, height: 100);
    }

    // ✅ 1명일 때도 리스트 UI로 통일 (가운데 정렬)
    return SizedBox(
      width: double.infinity, // ✅ 화면 전체 너비
      height: 100, // 프로필 + 이름을 위한 높이
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(), // ✅ alwaysScroll 적용
        itemCount:
            _selectedFriends.length +
            (showAddButton ? 1 : 0) +
            2, // ✅ + 버튼 조건부 포함 + 양쪽 SizedBox
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          // ✅ 맨 왼쪽에 SizedBox 추가 (첫 번째 아이템)
          if (index == 0) {
            return const SizedBox(width: 24); // ✅ 왼쪽 여백
          }

          // ✅ 맨 오른쪽에 SizedBox 추가 (마지막 아이템)
          final totalItems = _selectedFriends.length + (showAddButton ? 1 : 0);
          if (index == totalItems + 1) {
            return const SizedBox(width: 24); // ✅ 오른쪽 여백
          }

          // ✅ 인덱스 조정 (왼쪽 SizedBox 제외)
          final adjustedIndex = index - 1;

          // ✅ 마지막 item은 + 버튼 (showAddButton이 true일 때만)
          if (showAddButton && adjustedIndex == _selectedFriends.length) {
            return GestureDetector(
              onTap: () => _openFriendSelection(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64, // ✅ 프로필 크기에 맞춰 조정
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.add,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      size: 28, // ✅ 약간 크게: 24 -> 28
                    ),
                  ),
                  const SizedBox(height: 6),
                  // + 버튼 아래 공간 (이름이 없어도 레이아웃 맞추기)
                  const SizedBox(height: 20),
                ],
              ),
            );
          }

          // ✅ 일반 친구 프로필
          final friend = _selectedFriends[adjustedIndex];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CommonProfileAvatar(
                imageUrl:
                    (friend['profileImageUrl'] ?? friend['imageUrl'])
                        as String?,
                username: friend['username'] as String? ?? '',
                size: 64.0, // ✅ 더 크게: 48 -> 64
                borderColor: Colors.transparent,
                borderWidth: 0,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 64, // ✅ 프로필 크기에 맞춰 너비 조정
                child: Text(
                  friend['alias'] as String? ??
                      friend['username'] as String? ??
                      '',
                  style: TextStyle(
                    fontSize: 13, // ✅ 약간 크게: 12 -> 13
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ✅ letter 모드: 수신인 선택 화면 열기
  Future<void> _openLetterRecipientSelection() async {
    // 기존 선택한 수신인들의 정보
    final letterRecipientsAsFriends = <Map<String, dynamic>>[];

    try {
      final recipients = _exportedBase['letterRecipients'] as List?;
      if (recipients != null && recipients.isNotEmpty) {
        if (recipients.first is Map) {
          letterRecipientsAsFriends.addAll(
            recipients
                .map((r) => r as Map<String, dynamic>)
                .where(
                  (r) =>
                      r['username'] != null && r['username'] != 'all_friends',
                )
                .toList(),
          );
        }
      }
    } catch (_) {
      // 에러 발생 시 빈 리스트
    }

    final initialUsernames =
        letterRecipientsAsFriends
            .map((f) => f['username'] as String?)
            .where((u) => u != null && u.isNotEmpty)
            .toList()
            .cast<String>();

    // LetterRecipientSelectionScreen 재활용 (returnResult: true로 결과 반환)
    final selectedRecipients = await Navigator.of(
      context,
    ).push<List<Map<String, dynamic>>>(
      MaterialPageRoute(
        builder:
            (_) => LetterRecipientSelectionScreen(
              initialRecipientUsernames:
                  initialUsernames.isNotEmpty ? initialUsernames : null,
              returnResult: true, // ✅ 결과 반환 모드
            ),
      ),
    );

    if (selectedRecipients != null && selectedRecipients.isNotEmpty) {
      // ✅ exportedBase에 업데이트
      setState(() {
        _exportedBase['letterRecipients'] = selectedRecipients;
        // _letterRecipients도 업데이트
        _letterRecipients =
            selectedRecipients
                .map((r) => r['username']?.toString() ?? '')
                .where((r) => r.isNotEmpty)
                .toList();
      });
    }
  }

  // ✅ 친구 선택 화면 열기
  Future<void> _openFriendSelection() async {
    // 기존 선택한 친구들의 username 리스트
    final initialUsernames =
        _selectedFriends
            .map((f) => f['username'] as String?)
            .where((u) => u != null && u.isNotEmpty)
            .toList()
            .cast<String>();

    // LetterRecipientSelectionScreen 재활용 (returnResult: true로 결과 반환)
    final selectedRecipients = await Navigator.of(
      context,
    ).push<List<Map<String, dynamic>>>(
      MaterialPageRoute(
        builder:
            (_) => LetterRecipientSelectionScreen(
              initialRecipientUsernames:
                  initialUsernames.isNotEmpty ? initialUsernames : null,
              returnResult: true, // ✅ 결과 반환 모드
            ),
      ),
    );

    if (selectedRecipients != null && selectedRecipients.isNotEmpty) {
      // ✅ 이미 전체 정보가 포함되어 있으므로 그대로 사용
      final selectedFriendsList = <Map<String, dynamic>>[];
      for (final recipient in selectedRecipients) {
        if (recipient['username'] == 'all_friends') continue; // "모든 친구" 제외

        selectedFriendsList.add({
          'username': recipient['username'] as String? ?? '',
          'alias':
              recipient['alias'] as String? ??
              recipient['username'] as String? ??
              '',
          'imageUrl': recipient['imageUrl'] as String?,
        });
      }

      setState(() {
        _selectedFriends = selectedFriendsList;
      });
      // ✅ 하트 파티클 업데이트
      _updateHeartParticles();
    }
  }

  /// ✅ letter 모드에서 여친만 선택되었는지 확인하고 하트 파티클 관리
  void _updateHeartParticles() {
    if (widget.writeMode != PostWriteMode.letter) {
      // letter 모드가 아니면 하트 파티클 중지
      if (_shouldShowHearts) {
        _shouldShowHearts = false;
        _heartSpawnController.removeListener(_spawnHeart);
        _heartSpawnController.stop();
        for (final particle in _heartParticles) {
          particle.controller.dispose();
        }
        _heartParticles.clear();
        if (mounted) setState(() {});
      }
      return;
    }

    // letter 모드일 때: 여친만 선택되었는지 확인
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    User? partner;
    if (currentUser != null) {
      final userType = currentUser.militaryInfo?.userType;
      if (userType == UserType.girlfriend) {
        partner = currentUser.connectedMilitaryUser;
      } else if (userType == UserType.military ||
          userType == UserType.plannedEnlistment) {
        partner = currentUser.connectedToMeByUser;
      }
    }

    // letterRecipients가 1명이고, 그게 연결된 짝궁(여친)인지 확인
    final isOnlyPartnerSelected =
        partner != null &&
        _letterRecipients.length == 1 &&
        _letterRecipients.first == partner.username &&
        !_letterRecipients.contains('all_friends');

    if (isOnlyPartnerSelected && !_shouldShowHearts) {
      // 하트 파티클 시작
      _shouldShowHearts = true;
      _heartSpawnController.repeat();
      _heartSpawnController.addListener(_spawnHeart);
      if (mounted) setState(() {});
    } else if (!isOnlyPartnerSelected && _shouldShowHearts) {
      // 하트 파티클 중지
      _shouldShowHearts = false;
      _heartSpawnController.removeListener(_spawnHeart);
      _heartSpawnController.stop();
      for (final particle in _heartParticles) {
        particle.controller.dispose();
      }
      _heartParticles.clear();
      if (mounted) setState(() {});
    }
  }

  /// ✅ 새로운 하트 파티클 생성 (약하게)
  void _spawnHeart() {
    if (!mounted || !_shouldShowHearts) return;

    // 최대 파티클 개수 제한 (약하게: 8개)
    if (_heartParticles.length >= 8) return;

    // 선택된 친구 목록 영역 중앙 기준
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 하단 네비게이션 바 영역 중앙 기준
    final centerX = screenWidth / 2;
    final centerY = screenHeight * 0.9; // 하단 90% 지점

    // 랜덤 시작 위치 (약하게: 범위 축소)
    final startX = centerX + (_random.nextDouble() - 0.5) * 120; // -60 ~ +60 범위
    final startY = centerY - 20 - _random.nextDouble() * 20;

    // 랜덤 속성 (약하게: 크기와 범위 축소)
    final size = 12.0 + _random.nextDouble() * 8.0; // 12~20px (약하게)
    final rotation = _random.nextDouble() * 2 * math.pi;
    final horizontalOffset = (_random.nextDouble() - 0.5) * 80; // 좌우 흔들림 범위 축소

    final controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: 2500 + _random.nextInt(1000), // 2.5~3.5초 (약하게)
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

  // ✅ letter 모드: 선택한 친구 목록 표시 (친구공개와 동일한 형식)
  Widget _buildLetterRecipientsDisplay() {
    // ✅ 여친(짝궁) 1명만 선택된 경우: 리스트 UI 제거 + 높이 유지
    // - 하트 파티클은 이미 화면 오버레이로 표시됨
    if (_shouldShowHearts) {
      return const SizedBox(width: double.infinity, height: 100);
    }

    // ✅ letterRecipients를 selectedFriends 형식으로 변환
    final letterRecipientsAsFriends = <Map<String, dynamic>>[];

    // exported에서 letterRecipients 전체 정보 가져오기
    try {
      final recipients = _exportedBase['letterRecipients'] as List?;
      if (recipients != null && recipients.isNotEmpty) {
        if (recipients.first is Map) {
          // Map 형태인 경우 (전체 정보)
          letterRecipientsAsFriends.addAll(
            recipients
                .map((r) => r as Map<String, dynamic>)
                .where(
                  (r) =>
                      r['username'] != null && r['username'] != 'all_friends',
                )
                .toList(),
          );
        } else {
          // String 형태인 경우 (하위 호환성) - FriendProvider에서 조회 필요
          final friendProvider = context.read<FriendProvider>();
          final friends = friendProvider.acceptedFriends;
          final userProvider = context.read<UserProvider>();
          final currentUser = userProvider.currentUser;

          // 연결된 짝궁도 확인
          User? partner;
          if (currentUser != null) {
            final userType = currentUser.militaryInfo?.userType;
            if (userType == UserType.girlfriend) {
              partner = currentUser.connectedMilitaryUser;
            } else if (userType == UserType.military ||
                userType == UserType.plannedEnlistment) {
              partner = currentUser.connectedToMeByUser;
            }
          }

          for (final username in _letterRecipients) {
            if (username == 'all_friends') continue;

            // 연결된 짝궁인지 확인
            if (partner != null && partner.username == username) {
              letterRecipientsAsFriends.add({
                'username': partner.username,
                'alias': partner.alias ?? partner.username,
                'imageUrl': partner.profileImageUrl,
              });
            } else {
              // 친구 목록에서 찾기
              try {
                final friend = friends.firstWhere(
                  (f) => f.username == username,
                );
                letterRecipientsAsFriends.add({
                  'username': friend.username,
                  'alias': friend.alias,
                  'imageUrl': friend.profileImageUrl,
                });
              } catch (_) {
                // 친구를 찾을 수 없으면 username만으로 추가
                letterRecipientsAsFriends.add({
                  'username': username,
                  'alias': username,
                  'imageUrl': null,
                });
              }
            }
          }
        }
      }
    } catch (_) {
      // 에러 발생 시 빈 리스트
    }

    // ✅ 친구공개와 동일한 형식으로 표시
    if (letterRecipientsAsFriends.isEmpty) {
      return GestureDetector(
        onTap: () {
          // letter 모드에서는 수신인 재선택 불가 (에디터로 돌아가야 함)
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 12),
              Text(
                '수신인 선택',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ 여친만 선택되었는지 확인
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    User? partner;
    if (currentUser != null) {
      final userType = currentUser.militaryInfo?.userType;
      if (userType == UserType.girlfriend) {
        partner = currentUser.connectedMilitaryUser;
      } else if (userType == UserType.military ||
          userType == UserType.plannedEnlistment) {
        partner = currentUser.connectedToMeByUser;
      }
    }

    final isOnlyPartner =
        partner != null &&
        letterRecipientsAsFriends.length == 1 &&
        letterRecipientsAsFriends.first['username'] == partner.username;
    final showAddButton = !isOnlyPartner; // ✅ 여친만 있으면 + 버튼 숨김

    // ✅ 1명일 때도 리스트 UI로 통일 (가운데 정렬)
    return SizedBox(
      width: double.infinity, // ✅ 화면 전체 너비
      height: 100, // 프로필 + 이름을 위한 높이
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(), // ✅ alwaysScroll 적용
        itemCount:
            letterRecipientsAsFriends.length +
            (showAddButton ? 1 : 0) +
            2, // ✅ + 버튼 조건부 포함 + 양쪽 SizedBox
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          // ✅ 맨 왼쪽에 SizedBox 추가 (첫 번째 아이템)
          if (index == 0) {
            return const SizedBox(width: 24); // ✅ 왼쪽 여백
          }

          // ✅ 맨 오른쪽에 SizedBox 추가 (마지막 아이템)
          final totalItems =
              letterRecipientsAsFriends.length + (showAddButton ? 1 : 0);
          if (index == totalItems + 1) {
            return const SizedBox(width: 24); // ✅ 오른쪽 여백
          }

          // ✅ 인덱스 조정 (왼쪽 SizedBox 제외)
          final adjustedIndex = index - 1;

          // ✅ 마지막 item은 + 버튼 (showAddButton이 true일 때만)
          if (showAddButton &&
              adjustedIndex == letterRecipientsAsFriends.length) {
            return GestureDetector(
              onTap: () => _openLetterRecipientSelection(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64, // ✅ 프로필 크기에 맞춰 조정
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.add,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      size: 28, // ✅ 약간 크게: 24 -> 28
                    ),
                  ),
                  const SizedBox(height: 6),
                  // + 버튼 아래 공간 (이름이 없어도 레이아웃 맞추기)
                  const SizedBox(height: 20),
                ],
              ),
            );
          }

          // ✅ 일반 친구 프로필
          final friend = letterRecipientsAsFriends[adjustedIndex];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CommonProfileAvatar(
                imageUrl: friend['imageUrl'] as String?,
                username: friend['username'] as String? ?? '',
                size: 64.0, // ✅ 더 크게: 48 -> 64
                borderColor: Colors.transparent,
                borderWidth: 0,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 64, // ✅ 프로필 크기에 맞춰 너비 조정
                child: Text(
                  friend['alias'] as String? ??
                      friend['username'] as String? ??
                      '',
                  style: TextStyle(
                    fontSize: 13, // ✅ 약간 크게: 12 -> 13
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 🎯 선택 버튼 위젯
  Widget _buildSelectionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_drop_up,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ letter 모드: 발송 대상 선택 화면 표시
  Future<User?> _showLetterRecipientSelection() async {
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;

    // 발송 대상 후보 목록
    User? recipient;

    if (currentUser?.militaryInfo?.userType == UserType.girlfriend) {
      // 곰신: connectedMilitaryUser (남친)
      recipient = currentUser?.connectedMilitaryUser;
    } else {
      // 군인/입대 예정자: connectedToMeByUser (곰신)
      recipient = currentUser?.connectedToMeByUser;
    }

    // 발송 대상이 없으면 에러 표시
    if (recipient == null) {
      await DialogUtils.showInfoDialog(
        context,
        title: '대상이 없어요',
        message: '연결된 짝궁이 없습니다.',
      );
      return null;
    }

    // ✅ DialogUtils를 사용한 발송 대상 확인 다이얼로그
    final recipientName = recipient.alias ?? recipient.username;
    final confirmed = await DialogUtils.showConfirmDialog(
      context,
      title: '포스트 보내기',
      message: '$recipientName에게 보내시겠습니까?',
      confirmText: '확인',
      cancelText: '취소',
      isDestructive: false,
    );

    return confirmed == true ? recipient : null;
  }
}
