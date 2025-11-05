import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/image/native_image_picker.dart';
import 'package:doppy/image/custom_image_editor_screen.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/editor/utils/video_upload_utils.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:video_player/video_player.dart';

void printLarge(String text, {int chunkSize = 800}) {
  final int len = text.length;
  for (int i = 0; i < len; i += chunkSize) {
    final int end = (i + chunkSize < len) ? i + chunkSize : len;
    debugPrint(text.substring(i, end));
  }
}

class PostExportScreen extends StatefulWidget {
  const PostExportScreen({super.key, required this.exported, this.sessionKey});
  final String exported;
  final String? sessionKey; // 블로그/드래프트별 네임스페이스 키

  @override
  State<PostExportScreen> createState() => _PostExportScreenState();
}

class _PostExportScreenState extends State<PostExportScreen>
    with SingleTickerProviderStateMixin {
  String get _nsKey => widget.sessionKey ?? 'default';

  // 3단계 진행 상태
  int _currentStep = 0;
  static const int _totalSteps = 3;

  // 더미 데이터
  String _exportedThumbnailImageUrl = '';
  String _title = '';
  String _excerpt = '';
  late final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  late final TextEditingController _excerptController = TextEditingController();
  final FocusNode _excerptFocusNode = FocusNode();

  Map<String, dynamic> _exportedBase = <String, dynamic>{};

  bool _editMode = false;

  // Step 2: 공개 범위 선택
  final Set<int> _selectedAudienceGroupIds = {};
  bool _audienceSelectAll = false;
  bool _audiencePrivateOnly = false;
  bool _audienceFriendsOnly = false;

  // Step 3: 카테고리 선택
  int? _selectedCategoryId = 0; // 기본값: 미지정 카테고리 (ID: 0)
  bool _isCreatingCategory = false;
  final TextEditingController _newCategoryController = TextEditingController();
  List<Map<String, dynamic>>? _cachedCategories; // 캐시된 카테고리 목록
  bool _isLoadingCategories = false; // 카테고리 로딩 상태
  bool _showCategoryLoading = false; // 1초 후에만 표시할 카테고리 로딩
  bool _showGroupLoading = false; // 1초 후에만 표시할 그룹 로딩
  bool _isGroupLoadingStarted = false; // 그룹 로딩 시작 여부

  bool _isUploading = false;
  bool _isUploadingThumb = false;
  String? _thumbnailImageId;
  bool _showLoadingOverlay = false; // 0.8초 후에만 표시할 로딩 오버레이
  File? _localThumbnailFile; // 업로드 중 로컬 파일 미리보기용
  File? _localVideoFile; // 영상 선택 시 원본 비디오 파일
  VideoPlayerController? _videoController; // 영상 재생 컨트롤러
  String? _cachedVideoUrl; // 캐시된 비디오 URL (서버 영상용)

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _introCurve = CurvedAnimation(
    parent: _intro,
    curve: Curves.elasticOut,
    reverseCurve: Curves.easeInCubic, // 닫힐 때는 부드럽게
  );

  @override
  void initState() {
    super.initState();
    print('[PostExport] ═══════════════════════════════════════');
    print('[PostExport] initState 호출됨 - sessionKey: $_nsKey');
    print('[PostExport] ═══════════════════════════════════════');
    _hydrateFromExported(jsonDecode(widget.exported));
    _intro.forward();
    _titleFocusNode.addListener(_onEditFocusChange);
    _excerptFocusNode.addListener(_onEditFocusChange);
  }

  @override
  void dispose() {
    try {
      _titleFocusNode.removeListener(_onEditFocusChange);
      _excerptFocusNode.removeListener(_onEditFocusChange);
      _titleController.dispose();
      _titleFocusNode.dispose();
      _excerptController.dispose();
      _excerptFocusNode.dispose();

      // 로컬 비디오 컨트롤러는 직접 dispose
      if (_localVideoFile != null && _videoController != null) {
        _videoController?.dispose();
      }

      // 캐시된 서버 비디오는 참조 해제
      if (_cachedVideoUrl != null) {
        VideoCacheService().releaseController(
          _cachedVideoUrl!,
          namespace: 'profile',
        );
      }
    } catch (e) {
      print('[PostExport] dispose 에러: $e');
    }
    super.dispose();
  }

  void _onEditFocusChange() {
    // Step 1에서만 편집 모드 활성화
    if (_currentStep != 0) return;

    final bool nowEditing =
        _titleFocusNode.hasFocus || _excerptFocusNode.hasFocus;
    if (_editMode != nowEditing) {
      setState(() => _editMode = nowEditing);
    }
  }

  void _hydrateFromExported(Map<String, dynamic> exported) {
    _exportedBase = exported;
    // 제목
    final String? exportedTitle = _readString(exported, keys: const ['title']);
    if (exportedTitle != null && exportedTitle.trim().isNotEmpty) {
      _title = exportedTitle.trim();
      _titleController.text = _title;
    }

    // 썸네일: persist된 값만 사용 (exported 값은 무시)
    final svc = NodeComponentService();
    final persistedUrl = svc.getTempThumbnailUrl(_nsKey) ?? '';
    final persistedId = svc.getTempThumbnailId(_nsKey);
    final persistedVideoPath = svc.getTempVideoFilePath(_nsKey);
    final persistedVideoThumbnailPath = svc.getTempVideoThumbnailPath(_nsKey);

    _exportedThumbnailImageUrl = persistedUrl;
    _thumbnailImageId = persistedId;

    // 영상 파일 복원 (있다면)
    if (persistedVideoPath != null && persistedVideoPath.isNotEmpty) {
      final videoFile = File(persistedVideoPath);
      if (videoFile.existsSync()) {
        _localVideoFile = videoFile;
        _videoController = VideoPlayerController.file(videoFile)
          ..initialize().then((_) {
            if (mounted) {
              _videoController?.play();
              _videoController?.setLooping(true);
              setState(() {});
            }
          });
        print('[PostExport] 영상 파일 복원: $persistedVideoPath');

        // 영상 로컬 썸네일도 복원
        if (persistedVideoThumbnailPath != null &&
            persistedVideoThumbnailPath.isNotEmpty) {
          final thumbnailFile = File(persistedVideoThumbnailPath);
          if (thumbnailFile.existsSync()) {
            _localThumbnailFile = thumbnailFile;
            print('[PostExport] 영상 썸네일 복원: $persistedVideoThumbnailPath');
          }
        }
      } else {
        print('[PostExport] 영상 파일이 존재하지 않음: $persistedVideoPath');
        svc.clearTempVideoFile(_nsKey);
      }
    }

    // 본문 전체 내용
    String collected = _collectText(exported);
    collected =
        collected
            .replaceAll(RegExp('\\s+'), ' ')
            .replaceAll('\u200B', '')
            .trim();
    // 제목이 포함되어 있으면 제목 부분 제거
    String preview = collected;
    if (_title.isNotEmpty && preview.startsWith(_title)) {
      preview = preview.substring(_title.length).trim();
    }
    if (preview.isEmpty) preview = _excerpt;
    _excerpt = preview;
    _excerptController.text = _excerpt;

    // 공개 범위 초기값 동기화: accessLevel/sharedGroupIds 반영
    try {
      final dynamic rawLevel = exported['accessLevel'];
      final String level = rawLevel?.toString().toUpperCase() ?? '';
      final List<dynamic> shared =
          (exported['sharedGroupIds'] is List)
              ? List<dynamic>.from(exported['sharedGroupIds'])
              : const [];

      // 우선 순위: PRIVATE > PUBLIC > FRIENDS > GROUPS(shared)
      bool selectAll = false;
      bool privateOnly = false;
      bool friendsOnly = false;
      final Set<int> groups = <int>{};
      for (final x in shared) {
        final id = (x is int) ? x : int.tryParse(x.toString());
        if (id != null) groups.add(id);
      }

      if (level == 'PRIVATE') {
        privateOnly = true;
      } else if (level == 'PUBLIC') {
        selectAll = true;
      } else if (level == 'FRIENDS') {
        friendsOnly = true;
      } else if (level == 'GROUPS') {
        // 그룹 공유: 기존 그룹 선택 반영
      }

      _audiencePrivateOnly = privateOnly;
      _audienceSelectAll = selectAll;
      _audienceFriendsOnly = friendsOnly;
      _selectedAudienceGroupIds
        ..clear()
        ..addAll(groups);
    } catch (_) {}
    setState(() {});
  }

  Future<void> _persistThumbnail() async {
    if (_exportedThumbnailImageUrl.isNotEmpty) {
      NodeComponentService().setTempThumbnail(
        _nsKey,
        url: _exportedThumbnailImageUrl,
        id: _thumbnailImageId,
      );
      print(
        '[PostExport] 썸네일 persist 완료: $_exportedThumbnailImageUrl (ID: $_thumbnailImageId, sessionKey: $_nsKey)',
      );
    } else {
      print('[PostExport] 썸네일 persist 실패: URL이 비어있음');
    }
  }

  String? _readString(Map<String, dynamic> map, {required List<String> keys}) {
    for (final k in keys) {
      final v = map[k];
      if (v is String) return v;
    }
    return null;
  }

  String _collectText(dynamic node) {
    final buffer = StringBuffer();
    void walk(dynamic n) {
      if (n is Map) {
        // 제목 노드는 건너뛰기
        if (n['isTitle'] == true) {
          return;
        }

        n.forEach((key, value) {
          final k = key.toString().toLowerCase();
          if (value is String) {
            if (k.contains('text') ||
                k.contains('content') ||
                k.contains('paragraph') ||
                k.contains('description') ||
                k.contains('body')) {
              buffer.write(' ');
              buffer.write(value);
            }
          } else {
            walk(value);
          }
        });
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return buffer.toString();
  }

  void _toggleEditMode() {
    setState(() => _editMode = !_editMode);
    if (_editMode) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  // 부드러운 애니메이션과 함께 닫기
  Future<void> _closeWithAnimation() async {
    // 닫힐 때는 빠르게 (250ms)
    _intro.duration = const Duration(milliseconds: 250);
    await _intro.reverse();
    // 다시 원래 duration으로 복원
    _intro.duration = const Duration(milliseconds: 800);

    if (!mounted) return;

    Navigator.of(context).pop({
      'thumbnailImageUrl': _exportedThumbnailImageUrl,
      'thumbnailImageId': _thumbnailImageId,
    });
  }

  // 등록 가능 여부 확인 (서버 API 스펙 준수)
  bool _canPublish() {
    // 1. 기본 상태 확인
    if (_isUploading || _isUploadingThumb) {
      return false;
    }

    // 2. 필수 필드 확인 (편집된 내용 기준)
    final editedTitle = _titleController.text.trim();
    final editedExcerpt = _excerptController.text.trim();

    if (editedTitle.isEmpty) {
      return false;
    }
    if (editedExcerpt.isEmpty) {
      return false;
    }
    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return false;
    }

    // 3. 그룹 공유시 그룹 선택 확인
    if (!_audienceSelectAll &&
        !_audiencePrivateOnly &&
        !_audienceFriendsOnly &&
        _selectedAudienceGroupIds.isEmpty) {
      return false;
    }

    // 4. 카테고리 선택 확인 (미지정 카테고리 ID: 0도 유효)
    // _selectedCategoryId는 기본값이 0이므로 항상 유효

    return true;
  }

  // 등록 불가능할 때 표시할 에러 메시지 (서버 API 스펙 준수)
  String _getPublishErrorMessage() {
    if (_isUploadingThumb) {
      return '이미지 업로드 중입니다.';
    }
    final editedTitle = _titleController.text.trim();
    final editedExcerpt = _excerptController.text.trim();

    if (editedTitle.isEmpty) {
      return '제목을 입력해주세요.';
    }
    if (editedExcerpt.isEmpty) {
      return '본문 내용을 입력해주세요.';
    }
    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return '썸네일 이미지를 먼저 선택하세요.';
    }
    if (!_audienceSelectAll &&
        !_audiencePrivateOnly &&
        !_audienceFriendsOnly &&
        _selectedAudienceGroupIds.isEmpty) {
      return '그룹 공유를 선택했을 경우 최소 1개 이상의 그룹을 선택해주세요.';
    }
    // 카테고리 선택은 기본값이 0(미지정)이므로 항상 유효
    return '등록할 수 없습니다.';
  }

  Future<void> _publish() async {
    try {
      // 최종 편집된 내용으로 검증
      final finalTitle = _titleController.text.trim();
      final finalExcerpt = _excerptController.text.trim();

      // 1. 제목 검증 (모든 공개 범위에서 필수)
      if (finalTitle.isEmpty) {
        ErrorHandler.showError(context, '제목을 입력해주세요.');
        return;
      }

      // 2. 컨텐츠 검증 (모든 공개 범위에서 필수)
      if (finalExcerpt.isEmpty) {
        ErrorHandler.showError(context, '본문 내용을 입력해주세요.');
        return;
      }

      // 3. 썸네일 검증 (모든 공개 범위에서 필수)
      if (_exportedThumbnailImageUrl.trim().isEmpty) {
        ErrorHandler.showError(context, '썸네일 이미지를 먼저 선택하세요.');
        return;
      }

      // 4. 그룹 공유시 그룹 선택 검증 (친구공유는 예외)
      if (!_audienceSelectAll &&
          !_audiencePrivateOnly &&
          !_audienceFriendsOnly &&
          _selectedAudienceGroupIds.isEmpty) {
        ErrorHandler.showError(context, '그룹 공유를 선택했을 경우 최소 1개 이상의 그룹을 선택해주세요.');
        return;
      }

      // 5. 카테고리 선택 검증 (기본값이 0이므로 항상 유효)
      // _selectedCategoryId는 기본값이 0(미지정)이므로 검증 불필요

      // 모든 검증 통과 후 업로드 시작
      setState(() {
        _isUploading = true;
        _showLoadingOverlay = false; // 초기에는 오버레이 숨김
      });

      // 0.8초 후에 로딩 오버레이 표시
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted && _isUploading) {
          setState(() {
            _showLoadingOverlay = true;
          });
        }
      });

      final Map<String, dynamic> payload = await _buildFinalJson();

      // 최종 검증된 데이터 로깅
      final String json = const JsonEncoder.withIndent('  ').convert(payload);
      debugPrint('===== FINAL POST JSON (API SPEC COMPLIANT) =====');
      debugPrint('제목: $finalTitle');
      debugPrint('컨텐츠: $finalExcerpt');
      debugPrint('썸네일: $_exportedThumbnailImageUrl');
      final scopeLabel =
          _audienceSelectAll
              ? 'PUBLIC'
              : (_audiencePrivateOnly
                  ? 'PRIVATE'
                  : (_audienceFriendsOnly ? 'FRIENDS' : 'GROUPS'));
      debugPrint('공개 범위: $scopeLabel');
      if (!_audienceSelectAll && !_audiencePrivateOnly) {
        debugPrint('선택된 그룹: $_selectedAudienceGroupIds');
      }
      debugPrint('카테고리 ID: $_selectedCategoryId');
      printLarge(json);

      if (!mounted) return;

      // BlogService를 통한 서버 업로드

      final blogService = BlogService();
      // 매핑 제거: 서버로 전달할 썸네일 ID는 업로더가 반환한 값만 사용 (없으면 null)
      final String? resolvedThumbId = _thumbnailImageId?.toString();
      final uploadResult = await blogService.uploadPost(
        postData: payload,
        thumbnailImageId: resolvedThumbId,
      );

      debugPrint('===== UPLOAD RESULT =====');
      debugPrint('Upload successful: ${uploadResult}');

      if (!mounted) return;

      // 스티커 캔버스 청소
      try {
        context.read<StickerService>().removeAll();
      } catch (_) {}

      // 이미지 매핑 정리 로직 제거됨

      // 로컬 썸네일 이미지 정리 (발행 완료 후)
      try {
        NodeComponentService().clearTempThumbnail(_nsKey);
        print('[PostExport] 로컬 썸네일 이미지 정리 완료');
      } catch (e) {
        print('[PostExport] 썸네일 정리 실패: $e');
      }

      try {
        final feedProvider = context.read<MyProfileFeedProvider>();
        feedProvider.refresh().catchError((e) {
          print('[PostExport] 백그라운드 재로드 실패: $e');
        });
        print('[PostExport] 백그라운드 재로드 시작');
      } catch (e) {
        print('[PostExport] 백그라운드 재로드 실패: $e');
      }

      Navigator.of(context).pop();

      // 업로드 성공 시 바로 글보기 화면으로 이동
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder:
              (_, __, ___) => PostReaderScreen(
                exported: uploadResult, // 서버 응답 데이터 직접 사용
                heroTag:
                    'uploaded-post-${DateTime.now().millisecondsSinceEpoch}',
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
            final scale = Tween<double>(
              begin: 0.98,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);

            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: slide,
                child: ScaleTransition(scale: scale, child: child),
              ),
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('Upload failed: $e');

      if (!mounted) return;

      // 에러 메시지 표시
      ErrorHandler.handleError(context, e, customMessage: '업로드 중 오류가 발생했어요');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _showLoadingOverlay = false; // 업로드 완료 시 오버레이 숨김
        });
      }
    }
  }

  Future<Map<String, dynamic>> _buildFinalJson() async {
    // 사용자가 최종 편집한 제목과 본문 사용
    final editedTitle = _titleController.text.trim();
    final editedExcerpt = _excerptController.text.trim();

    // 기존 exportedBase를 복사하고 편집된 내용으로 덮어쓰기
    final editedBase = Map<String, dynamic>.from(_exportedBase);

    // 제목과 본문을 편집된 내용으로 업데이트
    editedBase['title'] = editedTitle;
    editedBase['summary'] = editedExcerpt; // 사용자가 편집한 내용을 summary로 설정

    // 발행 직전 정리: 서버에 업로드되지 않은 로컬 이미지/영상 노드 제거
    try {
      bool _isHttpUrl(String u) =>
          u.startsWith('http://') || u.startsWith('https://');
      final dynamic contentDyn = editedBase['content'];
      if (contentDyn is Map) {
        final List<dynamic> nodes = List<dynamic>.from(
          contentDyn['nodes'] as List? ?? const [],
        );
        final List<dynamic> cleaned = [];
        for (final n in nodes) {
          if (n is! Map) continue;
          final String type = (n['type'] ?? '').toString();
          if (type == 'image') {
            final Map<String, dynamic>? data =
                (n['data'] as Map?)?.cast<String, dynamic>();
            final String url = (data?['url'] ?? n['url'] ?? '').toString();
            if (_isHttpUrl(url)) cleaned.add(n);
          } else if (type == 'imageRow') {
            final List<dynamic> urls = List<dynamic>.from(
              n['urls'] ?? const [],
            );
            final List<String> httpUrls =
                urls.map((e) => e.toString()).where(_isHttpUrl).toList();
            if (httpUrls.isNotEmpty) {
              n['urls'] = httpUrls;
              cleaned.add(n);
            }
          } else if (type == 'video' || type == 'clip') {
            final Map<String, dynamic>? data =
                (n['data'] as Map?)?.cast<String, dynamic>();
            final String url = (data?['url'] ?? n['url'] ?? '').toString();
            if (_isHttpUrl(url)) cleaned.add(n);
          } else {
            cleaned.add(n); // 그 외 노드는 그대로 유지
          }
        }
        editedBase['content'] = {...contentDyn, 'nodes': cleaned};
      }
    } catch (e) {
      debugPrint('[PostExport] 로컬 미디어 정리 중 오류: $e');
    }

    // 디버그 로깅: 실제 전달되는 값 확인
    debugPrint('===== [_buildFinalJson] 공개 범위 설정 =====');
    debugPrint('_audiencePrivateOnly: $_audiencePrivateOnly');
    debugPrint('_audienceSelectAll: $_audienceSelectAll');
    debugPrint('_selectedAudienceGroupIds: $_selectedAudienceGroupIds');

    return PostExporter.composeFinalPayload(
      thumbnailImageUrl: _exportedThumbnailImageUrl,
      base: editedBase,
      privateOnly: _audiencePrivateOnly,
      publicOnly: _audienceSelectAll,
      friendsOnly: _audienceFriendsOnly,
      selectedGroupIds: _selectedAudienceGroupIds.toList(),
      categoryId: _selectedCategoryId, // 카테고리 ID 전달
      createdAt: DateTime.now(),
    );
  }

  void _openGalleryPicker() async {
    // 이미지 또는 비디오 선택 옵션 제공
    String? mode;
    final mediaType = await showModalBottomSheet<String>(
      backgroundColor: Colors.transparent,
      context: context,
      builder:
          (context) => ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                height: 180,
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      onTap: () async {
                        mode = 'image';
                        return Navigator.of(context).pop(mode);
                      },
                      title: const Text('이미지 선택'),
                    ),
                    ListTile(
                      onTap: () async {
                        mode = 'video';
                        return Navigator.of(context).pop(mode);
                      },
                      title: const Text('short clip 선택'),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    if (mediaType == null || !mounted) return;

    if (mediaType == 'image') {
      await _pickAndUploadImage();
    } else if (mediaType == 'video') {
      await _pickAndExtractVideoThumbnail();
    }
  }

  /// 이미지 선택 및 업로드
  Future<void> _pickAndUploadImage() async {
    final picker = NativeImagePicker();
    final file = await picker.pickSingleImage();

    if (file != null) {
      if (!mounted) return;

      // 즉시 로컬 파일 미리보기 표시 (영상 제거)
      setState(() {
        _localThumbnailFile = file;
        _isUploadingThumb = true;
        // 영상 파일 정리
        _videoController?.dispose();
        _videoController = null;
        _localVideoFile = null;
      });

      // 영상 파일 persist 정리
      final svc = NodeComponentService();
      svc.clearTempVideoFile(_nsKey);

      try {
        final upload = context.read<UploadService>();
        final tasks = await upload.uploadFilesViaServerBatches([
          file,
        ], kind: UploadKind.editorImage);
        if (tasks.isNotEmpty) {
          final t = tasks.first;
          final hasUrl = (t.url ?? '').isNotEmpty;
          final hasServerImageId = (t.imageId ?? '').toString().isNotEmpty;
          if (t.state == UploadState.success && hasUrl && hasServerImageId) {
            // 서버 URL로 교체
            _exportedThumbnailImageUrl = t.url!;
            _thumbnailImageId = t.imageId;
            await _persistThumbnail();

            if (mounted) {
              setState(() {
                _localThumbnailFile = null; // 로컬 파일 제거
              });
            }
          } else {
            if (mounted) {
              ErrorHandler.showError(context, '썸네일 업로드에 실패했어요. 다시 시도해주세요.');
              setState(() {
                _localThumbnailFile = null;
              });
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.handleError(context, e, customMessage: '업로드 오류');
          setState(() {
            _localThumbnailFile = null;
          });
        }
      } finally {
        if (mounted) setState(() => _isUploadingThumb = false);
      }
    }
  }

  /// 비디오 선택 및 업로드 (썸네일로 사용)
  Future<void> _pickAndExtractVideoThumbnail() async {
    final picker = NativeImagePicker();
    final videoFile = await picker.pickSingleVideo();

    if (videoFile == null || !mounted) return;

    // 클라이언트 측 파일 검증 (확장자 + 크기)
    final validationError = await VideoUploadUtils.validateFile(
      context,
      videoFile.path,
    );
    if (validationError != null) return;

    setState(() => _isUploadingThumb = true);

    try {
      // 원본 비디오에서 썸네일 생성 (업로드 중 플레이스홀더로 사용)
      final thumbnail = await VideoUploadUtils.generateThumbnail(
        videoFile.path,
      );
      if (thumbnail == null) {
        throw Exception('썸네일 생성 실패');
      }

      // 비디오 플레이어 초기화 (즉시 재생 - 원본)
      _videoController?.dispose();
      _videoController = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {
          if (mounted) {
            _videoController?.play();
            _videoController?.setLooping(true);
            setState(() {});
          }
        });

      // 즉시 영상 파일 저장 + 로컬 썸네일 표시 (플레이어용 + persist)
      if (mounted) {
        setState(() {
          _localVideoFile = videoFile;
          _localThumbnailFile = thumbnail; // 업로드 중 플레이스홀더로 썸네일 사용
        });
        // 영상 파일 경로 + 로컬 썸네일 경로 persist
        final svc = NodeComponentService();
        svc.setTempVideoFile(_nsKey, videoFile.path);
        svc.setTempVideoThumbnail(_nsKey, thumbnail.path);
        print('[PostExport] 영상 파일 persist: ${videoFile.path}');
        print('[PostExport] 영상 썸네일 persist: ${thumbnail.path}');
      }

      // MOV/M4V를 MP4로 변환 (원본 화질 유지)
      final mp4File = await VideoUploadUtils.compressVideo(videoFile.path);
      if (mp4File == null) {
        if (mounted) {
          await DialogUtils.showInfoDialog(
            context,
            title: '업로드 불가',
            message: '파일이 너무 큽니다.',
          );
          _videoController?.dispose();
          _videoController = null;
          setState(() {
            _localVideoFile = null;
            _localThumbnailFile = null;
            _isUploadingThumb = false;
          });
        }
        return;
      }

      // 압축된 MP4 파일을 서버에 업로드
      final upload = context.read<UploadService>();
      final task = upload.enqueueFile(mp4File, kind: UploadKind.video);

      // 리스너로 상태 변화 감지
      bool handled = false;
      void listener() async {
        if (handled) return;

        if (task.state == UploadState.success) {
          handled = true;
          final videoUrl = task.url;
          final videoId = task.imageId;

          if (videoUrl == null || videoUrl.isEmpty) {
            if (mounted) {
              ErrorHandler.showError(context, '영상 URL을 받지 못했습니다');
              _videoController?.dispose();
              _videoController = null;
              setState(() {
                _localVideoFile = null;
                _isUploadingThumb = false;
              });
            }
            return;
          }

          // 영상 URL을 썸네일로 저장
          _exportedThumbnailImageUrl = videoUrl;
          _thumbnailImageId = videoId;
          _persistThumbnail();

          if (mounted) {
            setState(() {
              // 로컬 썸네일은 유지 (영상의 배경으로 계속 표시)
              _isUploadingThumb = false;
            });
          }
        } else if (task.state == UploadState.failed) {
          handled = true;
          if (mounted) {
            await VideoUploadUtils.showUploadFailedDialog(context, task.error);
            _videoController?.dispose();
            _videoController = null;
            setState(() {
              _localVideoFile = null;
              _localThumbnailFile = null;
              _isUploadingThumb = false;
            });
          }
        } else if (task.state == UploadState.cancelled) {
          handled = true;
          if (mounted) {
            await VideoUploadUtils.showUploadCancelledDialog(context);
            _videoController?.dispose();
            _videoController = null;
            setState(() {
              _localVideoFile = null;
              _localThumbnailFile = null;
              _isUploadingThumb = false;
            });
          }
        }
      }

      task.addListener(listener);

      // 안전 타임아웃 (2분)
      Future.delayed(const Duration(minutes: 2), () async {
        if (!handled && mounted) {
          task.removeListener(listener);
          await VideoUploadUtils.showUploadTimeoutDialog(context);
          _videoController?.dispose();
          _videoController = null;
          setState(() {
            _localVideoFile = null;
            _localThumbnailFile = null;
            _isUploadingThumb = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        await VideoUploadUtils.showGeneralErrorDialog(context);
        _videoController?.dispose();
        _videoController = null;
        setState(() {
          _localVideoFile = null;
          _localThumbnailFile = null;
          _isUploadingThumb = false;
        });
      }
    }
  }

  /// 썸네일 편집 (커스텀 이미지 에디터 사용)
  Future<void> _editThumbnail() async {
    if (_exportedThumbnailImageUrl.isEmpty) {
      ErrorHandler.showInfo(context, '먼저 썸네일을 선택해주세요');
      return;
    }

    try {
      FocusScope.of(context).unfocus();

      // 현재 썸네일 이미지를 네트워크에서 로드
      final response = await http.get(Uri.parse(_exportedThumbnailImageUrl));
      if (response.statusCode != 200) {
        if (mounted) {
          ErrorHandler.showError(context, '이미지를 불러올 수 없습니다');
        }
        return;
      }

      final imageBytes = response.bodyBytes;

      // 커스텀 이미지 에디터 열기
      final editedBytes = await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (context) => CustomImageEditorScreen(imageBytes: imageBytes),
          fullscreenDialog: true,
        ),
      );

      if (editedBytes == null || !mounted) return;

      // 편집된 이미지를 서버에 업로드
      setState(() => _isUploadingThumb = true);

      final upload = context.read<UploadService>();
      final tempFile = File(
        '${Directory.systemTemp.path}/edited_thumbnail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(editedBytes);

      final tasks = await upload.uploadFilesViaServerBatches([
        tempFile,
      ], kind: UploadKind.editorImage);

      // 임시 파일 삭제
      try {
        await tempFile.delete();
      } catch (_) {}

      if (tasks.isEmpty || tasks.first.state != UploadState.success) {
        if (mounted) {
          ErrorHandler.showError(context, '썸네일 업로드에 실패했습니다');
        }
        return;
      }

      final newUrl = tasks.first.url;
      final newId = tasks.first.imageId;

      if (newUrl == null || newUrl.isEmpty) {
        if (mounted) {
          ErrorHandler.showError(context, '업로드 URL을 받지 못했습니다');
        }
        return;
      }

      // 새 썸네일 정보 저장
      _exportedThumbnailImageUrl = newUrl;
      _thumbnailImageId = newId;
      await _persistThumbnail();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: '편집 중 오류가 발생했습니다');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingThumb = false);
      }
    }
  }

  Widget _buildDynamicBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          // 썸네일 이미지 또는 단색 배경
          Positioned.fill(
            child:
                // 우선순위: 로컬 썸네일 > 서버 URL > 기본 배경
                _localThumbnailFile != null
                    ? Image.file(_localThumbnailFile!, fit: BoxFit.cover)
                    : _exportedThumbnailImageUrl.isNotEmpty
                    ? Image.network(
                      _exportedThumbnailImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) =>
                              Container(color: AppColors.darkSurface),
                    )
                    : Container(color: AppColors.darkSurface),
          ),
          // 블러 오버레이 (썸네일이 있을 때만)
          if (_localThumbnailFile != null ||
              _exportedThumbnailImageUrl.isNotEmpty)
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const ui.Color.fromARGB(
                          235,
                          45,
                          45,
                          45,
                        ).withOpacity(0.7),
                        const ui.Color.fromARGB(
                          235,
                          45,
                          45,
                          45,
                        ).withOpacity(0.7),
                        const ui.Color.fromARGB(
                          235,
                          45,
                          45,
                          45,
                        ).withOpacity(0.7),
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _nextStep() {
    // 썸네일 업로드 중이면 진행 불가
    if (_isUploadingThumb) {
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      FocusScope.of(context).unfocus();
      setState(() {
        _currentStep++;
        _editMode = false;
      });

      // Step 3 진입 시 카테고리 로드
      if (_currentStep == 1 && _cachedCategories == null) {
        _loadCategoriesOnce();
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      FocusScope.of(context).unfocus();
      setState(() {
        _currentStep--;
        _editMode = false;
      });
    }
  }

  bool _canProceedToNextStep() {
    switch (_currentStep) {
      case 0: // Step 1: 썸네일 & 글 편집
        final editedTitle = _titleController.text.trim();
        final editedExcerpt = _excerptController.text.trim();
        return _exportedThumbnailImageUrl.isNotEmpty &&
            editedTitle.isNotEmpty &&
            editedExcerpt.isNotEmpty;
      case 1: // Step 2: 공개 범위
        // 전체공개, 나만보기, 전체 친구 또는 그룹 중 하나는 선택되어야 함
        return _audienceSelectAll ||
            _audiencePrivateOnly ||
            _audienceFriendsOnly ||
            _selectedAudienceGroupIds.isNotEmpty;
      case 2: // Step 3: 카테고리
        return true; // 항상 진행 가능
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardRadius = 12.0; // PostCard와 동일한 라운드

    return WillPopScope(
      onWillPop: () async {
        // 업로드 중에는 뒤로 가기 방지
        if (_isUploading) {
          return false;
        }

        if (_currentStep > 0) {
          _previousStep();
          return false;
        }

        // Step 0에서 뒤로가기 시 부드러운 애니메이션과 함께 닫기
        await _closeWithAnimation();
        return false; // WillPopScope가 직접 처리하지 않도록 false 반환
      },
      child: FadeTransition(
        opacity: _intro,
        child: Stack(
          children: [
            _buildDynamicBackground(),
            Scaffold(
              backgroundColor: Colors.transparent,
              extendBodyBehindAppBar: true,
              appBar: _editMode ? _buildFocusAppBar() : _buildNormalAppBar(),
              body: SafeArea(
                child: IndexedStack(
                  index: _currentStep,
                  children: [
                    _buildStep1ThumbnailAndEdit(cardRadius),
                    _buildStep2AudienceSelection(),
                    _buildStep3CategorySelection(),
                  ],
                ),
              ),
            ),
            // 업로드 중 전체 화면 오버레이 (0.8초 후에만 표시)
            AnimatedOpacity(
              opacity: _showLoadingOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                color:
                    _showLoadingOverlay
                        ? Colors.black.withOpacity(0.8)
                        : Colors.transparent,
                child:
                    _showLoadingOverlay
                        ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 부드러운 로딩 인디케이터
                              TweenAnimationBuilder<double>(
                                duration: const Duration(milliseconds: 800),
                                tween: Tween(begin: 0.0, end: 1.0),
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: 0.8 + (0.2 * value),
                                    child: Opacity(
                                      opacity: value,
                                      child: Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.2,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const CircularProgressIndicator(
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                              strokeWidth: 3,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              '업로드 중...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '잠시만 기다려주세요',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.7,
                                                ),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 포커스 상태의 간단한 앱바 (완료 버튼만)
  PreferredSizeWidget _buildFocusAppBar() {
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
              setState(() {
                _editMode = false;
              });
              FocusScope.of(context).unfocus();
            },
            child: Text(
              context.tr('modify_complete'),
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 일반 상태의 앱바 (진행바와 다음/업로드 버튼)
  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      toolbarHeight: 50,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 80, // 이전 버튼이 잘리지 않도록 너비 확장
      leading: GestureDetector(
        onTap: () async {
          if (_currentStep > 0) {
            _previousStep();
          } else {
            // Step 0에서 뒤로가기 시 부드러운 애니메이션
            await _closeWithAnimation();
          }
        },
        child: Padding(
          padding: const EdgeInsets.only(left: 20, top: 16),
          child: Text(
            context.tr('previous'),
            style: TextStyle(
              color: AppColors.darkTextPrimary.withOpacity(0.9),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),

      actions: [
        if (_currentStep < _totalSteps - 1)
          TextButton(
            onPressed: _canProceedToNextStep() ? _nextStep : null,
            child: Text(
              context.tr('next'),
              style: TextStyle(
                color:
                    _canProceedToNextStep()
                        ? AppColors.darkTextPrimary.withOpacity(1)
                        : AppColors.darkTextPrimary.withOpacity(0.3),
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: TextButton(
              onPressed:
                  _isUploading
                      ? null
                      : () async {
                        final bool canPublish = _canPublish();
                        if (canPublish) {
                          await _publish();
                        } else {
                          String msg = _getPublishErrorMessage();
                          ErrorHandler.showError(context, msg);
                        }
                      },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child:
                    _isUploading
                        ? Container(
                          key: const ValueKey('loading'),
                          width: 20,
                          height: 20,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : Text(
                          context.tr('publish'),
                          key: const ValueKey('text'),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
              ),
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.onSurface.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.darkTextPrimary,
            ),
          ),
        ),
      ),
    );
  }

  // Step 1: 썸네일 & 글 편집
  Widget _buildStep1ThumbnailAndEdit(double cardRadius) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          // PostList와 동일한 카드 디자인
          // 키보드 열리거나 그룹 바텀시트가 열리면 썸네일 카드 임시 숨김 → 오버플로우 방지
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 100),
            crossFadeState:
                (MediaQuery.of(context).viewInsets.bottom > 0)
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            firstChild: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 4 / 5, // PostList와 동일한 4:5 비율
                      child: GestureDetector(
                        onTap: _openGalleryPicker,
                        onLongPress: _toggleEditMode,
                        child: AnimatedBuilder(
                          animation: _introCurve,
                          builder: (context, _) {
                            final double scale =
                                0.85 +
                                0.15 * _introCurve.value; // PostList와 동일한 스케일
                            final double translateY =
                                (1 - _introCurve.value) * 10;
                            return Transform.translate(
                              offset: Offset(0, translateY),
                              child: Transform.scale(
                                scale: scale,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      cardRadius + 2,
                                    ),
                                    border: Border.all(
                                      color: AppColors.darkTextPrimary
                                          .withOpacity(0.1),
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      cardRadius,
                                    ),
                                    child: Stack(
                                      children: [
                                        // 배경 이미지 또는 비디오 (로컬 미리보기 또는 서버 URL)
                                        Positioned.fill(
                                          child:
                                              _localVideoFile != null &&
                                                      _videoController != null
                                                  ? Stack(
                                                    children: [
                                                      // 배경: 로컬 썸네일 (비디오 초기화 전/중에도 항상 표시)
                                                      if (_localThumbnailFile !=
                                                          null)
                                                        Positioned.fill(
                                                          child: Image.file(
                                                            _localThumbnailFile!,
                                                            fit: BoxFit.cover,
                                                          ),
                                                        ),
                                                      // 전경: 비디오 플레이어 (초기화되면 썸네일 위에 재생)
                                                      if (_videoController!
                                                          .value
                                                          .isInitialized)
                                                        Positioned.fill(
                                                          child: FittedBox(
                                                            fit: BoxFit.cover,
                                                            child: SizedBox(
                                                              width:
                                                                  _videoController!
                                                                      .value
                                                                      .size
                                                                      .width,
                                                              height:
                                                                  _videoController!
                                                                      .value
                                                                      .size
                                                                      .height,
                                                              child: VideoPlayer(
                                                                _videoController!,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  )
                                                  : _localThumbnailFile != null
                                                  ? Image.file(
                                                    _localThumbnailFile!,
                                                    fit: BoxFit.cover,
                                                  )
                                                  : (_exportedThumbnailImageUrl
                                                          .isEmpty
                                                      ? const _EmptyImagePlaceholder()
                                                      : Image.network(
                                                        _exportedThumbnailImageUrl,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (c, e, s) =>
                                                                const _EmptyImagePlaceholder(),
                                                      )),
                                        ),

                                        // 업로드 중 로딩 오버레이
                                        if (_isUploadingThumb)
                                          Positioned.fill(
                                            child: Container(
                                              color: Colors.black.withOpacity(
                                                0.3,
                                              ),
                                              child: const Center(
                                                child: CircularProgressIndicator(
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.white),
                                                  strokeWidth: 3,
                                                ),
                                              ),
                                            ),
                                          ),

                                        // 음소거 버튼 (영상일 때만 표시)
                                        if (_localVideoFile != null &&
                                            _videoController != null &&
                                            _videoController!
                                                .value
                                                .isInitialized)
                                          Positioned(
                                            right: 12,
                                            bottom: 12,
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  if (_videoController!
                                                          .value
                                                          .volume >
                                                      0) {
                                                    _videoController!.setVolume(
                                                      0,
                                                    );
                                                  } else {
                                                    _videoController!.setVolume(
                                                      1,
                                                    );
                                                  }
                                                });
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withOpacity(0.5),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  _videoController!
                                                              .value
                                                              .volume >
                                                          0
                                                      ? Icons.volume_up_rounded
                                                      : Icons
                                                          .volume_off_rounded,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ),

                                        // 편집하기 버튼 (이미지일 때만 표시)
                                        if (_localVideoFile == null)
                                          Positioned(
                                            left: 6,
                                            bottom: 6,
                                            child: GestureDetector(
                                              onTap: _editThumbnail,
                                              child: _buildEditButton(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                /*
                        if (_exportedThumbnailImageUrl.isEmpty)
                          Positioned(
                            right: 40,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: AppColors.darkSurface,
                              ),
                            ),
                          ),*/
              ],
            ),
            secondChild: const SizedBox(height: 8),
          ),

          // 하단 텍스트 영역 (PostList의 StickyAuthor와 동일)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              // 바텀시트가 열려있으면 텍스트 영역을 약간 위로 올려 겹침 최소화
              vertical: 30,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // 제목 (탭 시 인라인 편집) - 바텀시트 중 편집 차단
                GestureDetector(
                  onTap: () {
                    setState(() => _editMode = true);
                    FocusScope.of(context).requestFocus(_titleFocusNode);
                  },
                  child: AbsorbPointer(
                    absorbing: false,
                    child: TextField(
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.darkTextPrimary.withOpacity(0.9),
                        fontSize: 35,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 내용 (탭 시 인라인 편집 가능) - 바텀시트 중 편집 차단
                GestureDetector(
                  onTap: () {
                    setState(() => _editMode = true);
                    FocusScope.of(context).requestFocus(_excerptFocusNode);
                  },
                  child: AbsorbPointer(
                    absorbing: false,
                    child: TextField(
                      controller: _excerptController,
                      focusNode: _excerptFocusNode,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.darkTextPrimary.withOpacity(0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                        height: 1.8,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 5,
                      minLines: 5,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      scrollPhysics: NeverScrollableScrollPhysics(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Step 2: 공개 범위 선택
  Widget _buildStep2AudienceSelection() {
    return Consumer<GroupProvider>(
      builder: (context, groupProvider, child) {
        // 그룹 목록 로드
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (groupProvider.myGroups.isEmpty &&
              !groupProvider.isLoading &&
              !_isGroupLoadingStarted) {
            _isGroupLoadingStarted = true;
            _showGroupLoading = false;

            // 1초 후에 로딩 표시
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted && groupProvider.isLoading) {
                setState(() {
                  _showGroupLoading = true;
                });
              }
            });

            groupProvider.fetchMyGroups();
          }
        });

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),
              Text(
                '누구에게 공개할까요?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: AppColors.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 20),

              // 전체공개/나만보기 선택 영역
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    // 전체공개
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color:
                            _audienceSelectAll
                                ? Colors.white.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _audienceSelectAll = true;
                              _audiencePrivateOnly = false;
                              _selectedAudienceGroupIds.clear();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '전체 공개',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (_audienceSelectAll)
                                      Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 나만보기
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            _audiencePrivateOnly
                                ? Colors.white.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _audiencePrivateOnly = true;
                              _audienceSelectAll = false;
                              _audienceFriendsOnly = false;
                              _selectedAudienceGroupIds.clear();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '나만 보기',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (_audiencePrivateOnly)
                                      Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 친구공유
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            _audienceFriendsOnly
                                ? Colors.white.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _audienceFriendsOnly = true;
                              _audiencePrivateOnly = false;
                              _audienceSelectAll = false;
                              _selectedAudienceGroupIds.clear();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '친구공유',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (_audienceFriendsOnly)
                                      const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 그룹 공유 헤더
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  '그룹',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),

              // 그룹 리스트 (항상 표시)
              Expanded(
                child:
                    groupProvider.isLoading
                        ? (_showGroupLoading
                            ? Center(
                              child: CircularProgressIndicator(
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : const SizedBox.shrink()) // 로딩이 1초 미만이면 아무것도 표시하지 않음
                        : ListView.builder(
                          itemCount: groupProvider.myGroups.length,
                          itemBuilder: (context, index) {
                            final group = groupProvider.myGroups[index];
                            final isSelected = _selectedAudienceGroupIds
                                .contains(group.id);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? Colors.white.withOpacity(0.4)
                                        : Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedAudienceGroupIds.remove(
                                          group.id,
                                        );
                                      } else {
                                        // 그룹 선택 시 전체공개/나만보기 먼저 해제
                                        _audienceSelectAll = false;
                                        _audiencePrivateOnly = false;
                                        _audienceFriendsOnly = false;
                                        _selectedAudienceGroupIds.add(group.id);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            group.name,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Step 3: 카테고리 선택
  Widget _buildStep3CategorySelection() {
    final isDarkMode = true; // 항상 다크모드 UI 사용
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 36),
          Text(
            '어느 카테고리에 저장할까요?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 20),
          Expanded(
            child:
                _cachedCategories == null
                    ? (_showCategoryLoading
                        ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : const SizedBox.shrink()) // 로딩이 1초 미만이면 아무것도 표시하지 않음
                    : ListView(
                      children: [
                        // 새 카테고리 만들기 버튼
                        _buildCreateCategoryButton(isDarkMode: isDarkMode),
                        const SizedBox(height: 12),
                        // 실제 카테고리 목록
                        ..._cachedCategories!.map((category) {
                          final id = category['id'] as int?;
                          var name = category['name'] as String? ?? '이름 없음';

                          if (name == 'system_doppy_uncategorized') {
                            name = '지정 안 함';
                          }

                          return _buildCategoryOption(
                            title: name,
                            isSelected: _selectedCategoryId == id,
                            isDarkMode: isDarkMode,
                            onTap: () {
                              setState(() {
                                _selectedCategoryId = id;
                              });
                            },
                          );
                        }).toList(),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCategoriesOnce() async {
    if (_cachedCategories != null || _isLoadingCategories)
      return; // 이미 로드 중이거나 완료됨

    setState(() {
      _isLoadingCategories = true;
      _showCategoryLoading = false; // 초기에는 로딩 숨김
    });

    // 1초 후에 로딩 표시
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted && _isLoadingCategories) {
        setState(() {
          _showCategoryLoading = true;
        });
      }
    });

    try {
      final currentUser =
          Provider.of<UserProvider>(context, listen: false).currentUser;
      final username = currentUser?.username ?? '';

      if (username.isEmpty) {
        throw Exception('사용자 정보를 찾을 수 없습니다.');
      }

      final categories = await BlogService().getUserCategories(username);
      if (mounted) {
        setState(() {
          _cachedCategories = categories;
          _isLoadingCategories = false;
          _showCategoryLoading = false;
        });
      }
    } catch (e) {
      print('[PostExportScreen] 카테고리 로드 실패: $e');
      if (mounted) {
        // 에러 발생 시 빈 리스트로 설정하여 재시도 방지
        setState(() {
          _cachedCategories = [];
          _isLoadingCategories = false;
          _showCategoryLoading = false;
        });
      }
    }
  }

  Widget _buildCreateCategoryButton({required bool isDarkMode}) {
    if (_isCreatingCategory) {
      // 인라인 텍스트 필드 표시
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isDarkMode
                  ? Colors.grey.withOpacity(0.15)
                  : Colors.grey.shade200.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            TextField(
              cursorColor:
                  isDarkMode ? Colors.white : AppColors.darkTextPrimary,
              controller: _newCategoryController,
              autofocus: true,
              style: TextStyle(
                color: isDarkMode ? Colors.white : AppColors.darkTextPrimary,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: '카테고리 이름 입력',
                hintStyle: TextStyle(
                  color:
                      isDarkMode
                          ? Colors.white.withOpacity(0.5)
                          : Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                  fontSize: 16,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isCreatingCategory = false;
                      _newCategoryController.clear();
                    });
                  },
                  child: Text(
                    '취소',
                    style: TextStyle(
                      color:
                          isDarkMode
                              ? Colors.white.withOpacity(0.7)
                              : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _createNewCategory,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDarkMode
                            ? Colors.white.withOpacity(0.9)
                            : AppColors.darkTextPrimary,
                    foregroundColor:
                        isDarkMode ? Colors.black : AppColors.darkBackground,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('추가', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 새 카테고리 만들기 버튼
    return GestureDetector(
      onTap: () {
        setState(() {
          _isCreatingCategory = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '새 카테고리 만들기',
                style: TextStyle(
                  color:
                      isDarkMode
                          ? Colors.white
                          : Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createNewCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) {
      ErrorHandler.showError(context, '카테고리 이름을 입력하세요.');
      return;
    }

    try {
      await BlogService().createCategory(
        name: name,
        isPrivate: false,
        description: '',
      );

      if (mounted) {
        // 캐시 무효화하여 다음 로드 시 새로고침
        _cachedCategories = null;

        setState(() {
          _isCreatingCategory = false;
          _newCategoryController.clear();
        });

        // 카테고리 목록 즉시 새로고침
        await _loadCategoriesOnce();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: '카테고리 생성 실패');
      }
    }
  }

  Widget _buildCategoryOption({
    required String title,
    required bool isSelected,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Colors.white.withOpacity(0.4)
                  : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: isDarkMode ? Colors.white : AppColors.darkTextPrimary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  // PostCard와 동일한 좌하단 작성자 정보
  Widget _buildEditButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.darkTextPrimary.withOpacity(0.2),
            borderRadius: BorderRadius.circular(35),
          ),
          child: Row(
            children: [
              Text(
                context.tr('edit_thumbnail'),
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudiencePicker extends StatefulWidget {
  final String title;
  final String excerpt;
  final String thumbnailImageUrl;
  final Function(
    bool selectAll,
    bool privateOnly,
    Set<int> selectedGroupIds,
    List<String> selectedNames,
  )
  onSelectionChanged;

  const _AudiencePicker({
    required this.title,
    required this.excerpt,
    required this.thumbnailImageUrl,
    required this.onSelectionChanged,
  });

  @override
  State<_AudiencePicker> createState() => _AudiencePickerState();
}

class _AudiencePickerState extends State<_AudiencePicker> {
  final Set<int> _selectedGroupIds = {};
  bool _selectAll = true; // 전체공개 토글
  bool _privateOnly = false; // 나만보기

  @override
  void initState() {
    super.initState();

    // 바텀시트 진입 시 실제 그룹 목록 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (context.read<GroupProvider>().myGroups.isEmpty) {
          context.read<GroupProvider>().fetchMyGroups();
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupProv = context.watch<GroupProvider>();
    final List<Group> groups = groupProv.myGroups;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.24),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: Row(
                children: [
                  Text(
                    '공개 범위 선택',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Icon(
                      Icons.close_outlined,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Builder(
                builder: (context) {
                  final list = _displayGroups(groups, groupProv.isLoading);

                  return ListView.builder(
                    itemCount:
                        list.length + 1, // +1 for the audience options row
                    itemBuilder: (context, i) {
                      // 첫 번째 아이템: 전체공개-나만보기 로우
                      if (i == 0) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8, top: 8),
                          child: Column(
                            children: [
                              // 전체공개
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        _selectAll
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.onSurface
                                            : Theme.of(context)
                                                .colorScheme
                                                .surface
                                                .withOpacity(1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        setState(() {
                                          _selectAll = true;
                                          _privateOnly = false;
                                          _selectedGroupIds.clear();
                                        });
                                        _notifySelectionChanged();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '전체 공개',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          _selectAll
                                                              ? Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .surface
                                                              : Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .onSurface,
                                                    ),
                                                  ),
                                                ),
                                                if (_selectAll)
                                                  Icon(
                                                    Icons.check,
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.surface,
                                                    size: 20,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '모든 사용자에게 공개',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color:
                                                    _selectAll
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .surface
                                                            .withOpacity(0.8)
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.7),
                                                height: 1.2,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // 나만보기
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(left: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        _privateOnly
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.onSurface
                                            : Theme.of(context)
                                                .colorScheme
                                                .surface
                                                .withOpacity(1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        setState(() {
                                          _privateOnly = true;
                                          _selectAll = false;
                                          _selectedGroupIds.clear();
                                        });
                                        _notifySelectionChanged();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '나만 보기',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          _privateOnly
                                                              ? Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .surface
                                                              : Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .onSurface,
                                                    ),
                                                  ),
                                                ),
                                                if (_privateOnly)
                                                  Icon(
                                                    Icons.check,
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.surface,
                                                    size: 20,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '본인만 볼 수 있음',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color:
                                                    _privateOnly
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .surface
                                                            .withOpacity(0.8)
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.7),
                                                height: 1.2,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // 그룹 아이템들 (i-1로 인덱스 조정)
                      final g = list[i - 1];
                      final checked = _selectedGroupIds.contains(g.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),

                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() {
                                if (checked) {
                                  _selectedGroupIds.remove(g.id);
                                } else {
                                  // 그룹 선택 시 다른 옵션들 취소
                                  _selectAll = false;
                                  _privateOnly = false;
                                  _selectedGroupIds.add(g.id);
                                }
                              });
                              _notifySelectionChanged();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // 그룹 정보
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          g.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                checked
                                                    ? Theme.of(
                                                      context,
                                                    ).colorScheme.surface
                                                    : Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          g.description,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color:
                                                checked
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .surface
                                                        .withOpacity(0.8)
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.7),
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 선택 아이콘
                                  checked
                                      ? Icon(
                                        Icons.check,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                        size: 20,
                                      )
                                      : Icon(
                                        Icons.circle_outlined,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.4),
                                        size: 20,
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
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

  List<Group> _displayGroups(List<Group> original, bool isLoading) {
    return List<Group>.from(original);
  }

  void _notifySelectionChanged() {
    final current = _displayGroups(
      context.read<GroupProvider>().myGroups,
      false,
    );
    final selectedNames =
        current
            .where((g) => _selectedGroupIds.contains(g.id))
            .map((g) => g.name)
            .toList();

    widget.onSelectionChanged(
      _selectAll,
      _privateOnly,
      _selectedGroupIds,
      selectedNames,
    );
  }
}

enum _StickerType { text, emoji, image }

class _Sticker {
  final _StickerType type;
  final String text;
  final Uint8List? bytes;
  Offset offset;

  _Sticker({
    required this.type,
    required this.text,
    required this.bytes,
    required this.offset,
  });
}

class _DraggableSticker extends StatefulWidget {
  final _Sticker sticker;
  final bool enabled;

  const _DraggableSticker({required this.sticker, required this.enabled});

  @override
  State<_DraggableSticker> createState() => _DraggableStickerState();
}

class _DraggableStickerState extends State<_DraggableSticker> {
  @override
  Widget build(BuildContext context) {
    final Widget child;
    switch (widget.sticker.type) {
      case _StickerType.text:
        child = _buildTextChip(widget.sticker.text);
        break;
      case _StickerType.emoji:
        child = _buildEmoji(widget.sticker.text);
        break;
      case _StickerType.image:
        child = _buildImageSticker(widget.sticker.bytes);
        break;
    }

    return Positioned(
      left: widget.sticker.offset.dx,
      top: widget.sticker.offset.dy,
      child:
          widget.enabled
              ? GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    widget.sticker.offset += d.delta;
                  });
                },
                child: child,
              )
              : child,
    );
  }

  Widget _buildTextChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmoji(String emoji) {
    return Text(emoji, style: const TextStyle(fontSize: 28));
  }

  Widget _buildImageSticker(Uint8List? bytes) {
    if (bytes == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(bytes, width: 96, height: 96, fit: BoxFit.cover),
    );
  }
}

/// 빈 이미지 자리표시자 (업로드 전/오류 시 사용)
class _EmptyImagePlaceholder extends StatelessWidget {
  const _EmptyImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkSurface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('tap_to_select_thumbnail'),
              style: TextStyle(color: AppColors.darkTextPrimary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// 간단한 쉬머 플레이스홀더 (썸네일 업로드 중 표시)
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final gradient = LinearGradient(
          begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
          end: Alignment(1.0 + 2.0 * _ctrl.value, 0),
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade700,
            Colors.grey.shade800,
          ],
          stops: const [0.25, 0.5, 0.75],
        );
        return Container(decoration: BoxDecoration(gradient: gradient));
      },
    );
  }
}
