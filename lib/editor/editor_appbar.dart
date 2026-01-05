import 'dart:ui';
import 'dart:async';

import 'package:doppy/editor/publish/post_export_screen.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/component/clip_component.dart' show muteAllVideos;
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:convert';
import 'package:doppy/data/services/blog_service.dart';
import 'package:super_editor/super_editor.dart';

class EditModeAppBar extends StatefulWidget {
  final EditorService editorService;
  final VoidCallback? onSave;
  final String currentVisibility; // 'public', 'private', 'partial'
  final List<int> currentGroupIds;
  final Function(String visibility, List<int> groupIds)? onVisibilityChanged;
  final Function(String title, String summary)?
  onTitleSummaryChanged; // 제목/요약 변경 콜백
  final VoidCallback? onCategoryChanged; // 카테고리 변경 콜백
  final Function(String url, String? id)?
  onThumbnailChanged; // 썸네일 변경 콜백 (URL과 ID 전달)
  final String? postId; // 서버에서 데이터 가져오기용
  final bool isSaving; // 저장 중 상태
  final bool isAutoSaving; // 자동 저장 중 상태
  final ValueNotifier<bool>? videoUploadIndicatorNotifier; // 영상 업로드 인디케이터 상태
  final VoidCallback? onEditThumbnail; // 썸네일 편집 화면 열기 콜백
  final String? initialTitle; // 썸네일 편집 화면 초기 제목
  final String? initialSummary; // 썸네일 편집 화면 초기 요약
  final String? initialThumbnailUrl; // 썸네일 편집 화면 초기 썸네일 URL
  final String? sessionKey; // 썸네일 편집 화면용 sessionKey
  final String? currentTitle; // 현재 제목 (변경 감지용)
  final String? currentSummary; // 현재 요약 (변경 감지용)
  final String? currentThumbnailUrl; // 현재 썸네일 URL (변경 감지용)
  final Map<String, dynamic>?
  originalExportedData; // 원본 exported 데이터 (문서 변경 감지용)
  final StickerService? stickerService; // 스티커 서비스 (문서 변경 감지용)

  const EditModeAppBar({
    super.key,
    required this.editorService,
    this.onSave,
    required this.currentVisibility,
    required this.currentGroupIds,
    this.onVisibilityChanged,
    this.onTitleSummaryChanged,
    this.postId,
    this.isSaving = false,
    this.isAutoSaving = false,
    this.onCategoryChanged,
    this.onThumbnailChanged,
    this.videoUploadIndicatorNotifier,
    this.onEditThumbnail,
    this.initialTitle,
    this.initialSummary,
    this.initialThumbnailUrl,
    this.sessionKey,
    this.currentTitle,
    this.currentSummary,
    this.currentThumbnailUrl,
    this.originalExportedData,
    this.stickerService,
  });

  @override
  State<EditModeAppBar> createState() => _EditModeAppBarState();
}

class _EditModeAppBarState extends State<EditModeAppBar> {
  String? _thumbnailUrl;
  bool _isLoading = false;

  String? _originalTitle; // 원본 제목 (서버에서 처음 로드한 값)
  String? _originalSummary; // 원본 요약 (서버에서 처음 로드한 값)
  String? _originalThumbnailUrl; // 원본 썸네일 URL (서버에서 처음 로드한 값)
  String? _originalVisibility; // 원본 공개범위 (서버에서 처음 로드한 값)
  List<int>? _originalGroupIds; // 원본 그룹 ID 리스트 (서버에서 처음 로드한 값)
  // 🎯 카테고리는 로컬 기반이므로 editor_appbar에서는 관리하지 않음

  @override
  void initState() {
    super.initState();
    debugPrint('[EditModeAppBar] 썸네일 초기화: $_thumbnailUrl');

    // 수정 모드 진입 시 썸네일만 로드
    if (widget.postId != null) {
      _loadThumbnail();
    } else {
      // postId가 없으면 initial 값들을 원본으로 사용
      _originalTitle = widget.initialTitle;
      _originalSummary = widget.initialSummary;
      _originalThumbnailUrl = widget.initialThumbnailUrl;
    }
  }

  /// 수정 모드 진입 시 썸네일, 제목, 요약 로드
  Future<void> _loadThumbnail() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final metadata = await BlogService().getPostMetadata(widget.postId!);

      if (!mounted) return;

      setState(() {
        _thumbnailUrl = metadata['thumbnailImageUrl'] as String?;
        _isLoading = false;
      });

      // 🎯 제목과 요약도 함께 로드하여 초기화 (수정 완료 버튼 검증용)
      final title = metadata['title'] as String? ?? '';
      final summary = metadata['summary'] as String? ?? '';

      // 원본 값 저장 (서버에서 처음 로드한 값)
      if (mounted) {
        setState(() {
          // 원본 값이 아직 설정되지 않았을 때만 저장 (최초 1회만)
          _originalTitle ??= title;
          _originalSummary ??= summary;
          _originalThumbnailUrl ??= _thumbnailUrl;

          // 🎯 공개범위 원본 값 저장 (카테고리는 로컬 기반이므로 서버에서 가져오지 않음)
          final accessLevel = metadata['accessLevel'] as String?;
          final sharedGroupIds = metadata['sharedGroupIds'] as List<int>?;
          _originalVisibility ??= accessLevel;
          _originalGroupIds ??=
              sharedGroupIds != null ? List<int>.from(sharedGroupIds) : null;
        });
      }

      widget.onTitleSummaryChanged?.call(title, summary);

      debugPrint('[EditModeAppBar] 썸네일 로드 완료: $_thumbnailUrl');
      debugPrint('[EditModeAppBar] 제목 로드 완료: $title');
      debugPrint('[EditModeAppBar] 요약 로드 완료: $summary');
    } catch (e) {
      debugPrint('[EditModeAppBar] 썸네일 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 표준 앱바 높이: Flutter 기본 toolbar 높이(kToolbarHeight=56)를 사용한다.
    // ✅ 상태바 배경도 앱바 자체에서 칠한다(외부 TopPadding 의존 제거).
    final bgColor = Theme.of(context).colorScheme.background.withOpacity(1);
    return Container(
      color: bgColor,
      child: SafeArea(
        bottom: false,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(color: bgColor),
              height: kToolbarHeight,
              width: MediaQuery.of(context).size.width,
              child: Row(
                children: [
                  // 뒤로가기 버튼
                  IconButton(
                    onPressed: () async {
                      Navigator.of(context).maybePop();
                    },
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 24,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),

                  // 언두 버튼
                  AnimatedBuilder(
                    animation: widget.editorService,
                    builder:
                        (context, _) => Material(
                          color: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: InkWell(
                              onTap:
                                  widget.editorService.canUndo
                                      ? () {
                                        widget.editorService.undo();
                                      }
                                      : null,
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                padding: const EdgeInsets.all(1),
                                child: SvgPicture.asset(
                                  'assets/icons/editor_undo.svg',
                                  width: 30,
                                  height: 30,
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(
                                      widget.editorService.canUndo ? 0.6 : 0.15,
                                    ),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(width: 8),

                  // 리두 버튼
                  AnimatedBuilder(
                    animation: widget.editorService,
                    builder:
                        (context, _) => Material(
                          color: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: InkWell(
                              onTap:
                                  widget.editorService.canRedo
                                      ? () {
                                        widget.editorService.redo();
                                      }
                                      : null,
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                padding: const EdgeInsets.all(1),
                                child: SvgPicture.asset(
                                  'assets/icons/editor_redo.svg',
                                  width: 30,
                                  height: 30,
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(
                                      widget.editorService.canRedo ? 0.6 : 0.15,
                                    ),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                  Spacer(),

                  // 기존 버튼들
                  AnimatedBuilder(
                    animation: widget.editorService,
                    builder: (context, _) {
                      // 수정 완료 버튼 색상 (항상 활성화)
                      final saveButtonColor =
                          Theme.of(context).colorScheme.primary;

                      return Row(
                        children: [
                          // 썸네일 수정 버튼
                          if (widget.onEditThumbnail != null)
                            GestureDetector(
                              onTap: widget.onEditThumbnail,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(),
                                child: Icon(
                                  Icons.more_horiz_rounded,
                                  size: 20,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ),
                          // 수정 완료 버튼 / 로딩 표시
                          GestureDetector(
                            onTap: widget.isSaving ? null : widget.onSave,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child:
                                    widget.isSaving
                                        ? Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 2,
                                          ),
                                          child: SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                  ),
                                            ),
                                          ),
                                        )
                                        : Row(
                                          children: [
                                            const SizedBox(width: 4),
                                            Text(
                                              context.tr('modify_complete'),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: saveButtonColor,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                        ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EditorAppBar extends StatelessWidget {
  final EditorService editorService;
  final StickerService stickerService;
  final Future<bool> Function()? onSaveDraft;
  final VoidCallback? onLoadDraft;
  final String? currentDraftId; // 현재 임시저장 ID
  final ValueNotifier<bool>? videoUploadIndicatorNotifier; // 영상 업로드 인디케이터 상태
  final void Function(String title, String summary, String thumbnailUrl)?
  onExportMetadataChanged; // ✅ 다음(썸네일 편집)에서 편집한 메타데이터 전달
  final String? initialTitleForExport; // ✅ 다음(썸네일 편집) 프리필용
  final String? initialSummaryForExport; // ✅ 다음(썸네일 편집) 프리필용
  final String? initialThumbnailUrlForExport; // ✅ 다음(썸네일 편집) 프리필용

  const EditorAppBar({
    super.key,
    required this.editorService,
    required this.stickerService,
    this.onSaveDraft,
    this.onLoadDraft,
    this.currentDraftId,
    this.videoUploadIndicatorNotifier,
    this.onExportMetadataChanged,
    this.initialTitleForExport,
    this.initialSummaryForExport,
    this.initialThumbnailUrlForExport,
  });

  Future<void> _onNextButtonTapped(BuildContext context) async {
    // 업로드 가드: 업로드 중인 미디어가 있으면 진행 차단 (압축 중인 비디오도 포함)
    if (editorService.hasUnuploadedMedia()) {
      // 🎯 상세한 디버그 정보 출력 (kDebugMode에서만 실행)
      if (kDebugMode) {
        try {
          final activeTasks = editorService
              .debugDumpBusyMediaForCurrentDocument(
                kinds: {
                  UploadKind.editorImage,
                  UploadKind.video,
                  UploadKind.drawing,
                },
              );
          debugPrint('[EditorAppBar] ⚠️ 업로드/압축 진행 중 - 발행 차단\n$activeTasks');
        } catch (e) {
          debugPrint('[EditorAppBar] 업로드 상태 확인 실패: $e');
        }
      }

      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('wait_for_media_upload'),
        message: context.tr('media_still_uploading'),
      );
      return;
    }

    // 본문(또는 스티커) 검증 (제목은 썸네일 편집 화면에서 입력)
    final hasBody = editorService.hasNonEmptyBody(context: context);

    if (!hasBody) {
      // 본문이 비어있으면 다이얼로그 표시
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('enter_content_first'),
        message: context.tr('body_required'),
      );
      return;
    }

    // 🎯 sessionKey 계산 (UUID 기반)
    // currentDraftId가 있으면 사용, 없으면 안전장치로 생성 (일반적으로는 이미 생성되어 있음)
    final sessionKey = currentDraftId ?? 'draft_temp';

    // 검증 통과 시 다음 화면으로 이동
    // ✅ Step1으로 이동할 때 모든 비디오를 mute (dispose는 하지 않음)
    // 뮤트 전 상태를 저장하여 돌아올 때 복원
    final muteService = VideoMuteService();
    final wasMutedBeforeStep1 = muteService.isReaderMuted;
    muteAllVideos();
    NodeComponentService().selectNode(null);

    // 🚀 exportToJsonString 호출 시 예외 처리
    String json;
    try {
      json = exportToJsonString(context);
    } catch (e) {
      // 발행 시 업로드되지 않은 미디어가 있는 경우
      if (e is StateError && e.message.contains('발행 불가')) {
        await DialogUtils.showInfoDialog(
          context,
          title: '등록 실패',
          message: e.message.replaceAll('발행 불가: ', '').split(' (').first,
        );
      } else {
        // 기타 에러
        ErrorHandler.handleError(
          context,
          e,
          customMessage: '발행 준비 중 오류가 발생했습니다.',
        );
      }
      return;
    }

    // ✅ PostExportScreen(Step1)에서 편집한 메타데이터를 유지하기 위해 exported JSON에 주입
    // (제목은 본문 document에 없어서, 다음 화면을 다시 열면 사라지는 문제 방지)
    try {
      final Map<String, dynamic> map = jsonDecode(json) as Map<String, dynamic>;
      final t = (initialTitleForExport ?? '').trim();
      final s = (initialSummaryForExport ?? '').trim();
      final th = (initialThumbnailUrlForExport ?? '').trim();
      if (t.isNotEmpty) map['title'] = t;
      if (s.isNotEmpty) map['summary'] = s;
      if (th.isNotEmpty) map['thumbnailImageUrl'] = th;
      json = jsonEncode(map);
    } catch (_) {
      // 실패해도 다음 화면 진입은 허용
    }

    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder:
            (_, __, ___) => PostExportScreen(
              exported: json,
              sessionKey: sessionKey, // draft ID를 sessionKey로 사용
            ),
      ),
    );

    // 🎯 Step1에서 돌아올 때 뮤트 상태 복원
    final restoreMuteService = VideoMuteService();
    // 원래 뮤트 상태로 복원
    restoreMuteService.setReaderMuted(wasMutedBeforeStep1);
    // VideoCacheService의 볼륨도 복원 (VideoMuteService 상태에 맞춰)
    try {
      VideoCacheService().setVolumeForNamespace(
        'editor',
        wasMutedBeforeStep1 ? 0.0 : 1.0,
      );
      VideoCacheService().setVolumeForNamespace(
        'reader',
        wasMutedBeforeStep1 ? 0.0 : 1.0,
      );
      debugPrint(
        '[EditorAppBar] 뮤트 상태 복원: ${wasMutedBeforeStep1 ? "음소거" : "소리 켜짐"}',
      );
    } catch (e) {
      debugPrint('[EditorAppBar] 뮤트 상태 복원 실패: $e');
    }

    // ✅ 썸네일 편집 화면에서 돌아오며 메타데이터를 전달받으면 상위로 전달
    if (result is Map) {
      final thumbnailUrl = (result['thumbnailImageUrl'] ?? '').toString();
      final title = (result['title'] ?? '').toString();
      final summary = (result['summary'] ?? '').toString();
      if (thumbnailUrl.isNotEmpty || title.isNotEmpty || summary.isNotEmpty) {
        onExportMetadataChanged?.call(title, summary, thumbnailUrl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 상태바 배경도 앱바 자체에서 칠한다(외부 TopPadding 의존 제거).
    final bgColor = Theme.of(context).colorScheme.background.withOpacity(1);
    return Container(
      color: bgColor,
      child: SafeArea(
        bottom: false,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(color: bgColor),
              height: kToolbarHeight, // ✅ 표준 앱바 높이
              width: MediaQuery.of(context).size.width,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 왼쪽 버튼들 (뒤로가기 + 언두/리두)
                  Row(
                    children: [
                      // 뒤로가기 버튼
                      IconButton(
                        onPressed: () async {
                          Navigator.of(context).maybePop();
                        },
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 24,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.75),
                        ),
                      ),

                      // 언두 버튼
                      AnimatedBuilder(
                        animation: editorService,
                        builder:
                            (context, _) => Material(
                              color: Colors.transparent,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: InkWell(
                                  onTap:
                                      editorService.canUndo
                                          ? () {
                                            editorService.undo();
                                          }
                                          : null,
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    padding: const EdgeInsets.all(1),
                                    child: SvgPicture.asset(
                                      'assets/icons/editor_undo.svg',
                                      width: 30,
                                      height: 30,
                                      colorFilter: ColorFilter.mode(
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurface.withOpacity(
                                          editorService.canUndo ? 0.6 : 0.15,
                                        ),
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ),
                      const SizedBox(width: 8),

                      // 리두 버튼
                      AnimatedBuilder(
                        animation: editorService,
                        builder:
                            (context, _) => Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap:
                                      editorService.canRedo
                                          ? () {
                                            editorService.redo();
                                          }
                                          : null,
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    padding: const EdgeInsets.all(1),
                                    child: SvgPicture.asset(
                                      'assets/icons/editor_redo.svg',
                                      width: 30,
                                      height: 30,
                                      colorFilter: ColorFilter.mode(
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurface.withOpacity(
                                          editorService.canRedo ? 0.6 : 0.15,
                                        ),
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ],
                  ),

                  // 오른쪽 버튼들
                  Row(
                    children: [
                      // 더보기 메뉴 버튼
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                          size: 20,
                        ),
                        offset: const Offset(45, 45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.1),
                          ),
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(1),

                        onSelected: (value) async {
                          if (value == 'load') {
                            onLoadDraft?.call();
                          } else if (value == 'save') {
                            onSaveDraft?.call();
                          }
                        },
                        itemBuilder:
                            (context) => [
                              PopupMenuItem(
                                value: 'load',
                                child: Row(
                                  children: [
                                    Text(
                                      context.tr('load_draft'),
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'save',
                                child: Row(
                                  children: [
                                    Text(
                                      context.tr('save_draft'),
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                      ),

                      // 다음 버튼 (항상 표시, 클릭 시 검증)
                      GestureDetector(
                        onTap: () => _onNextButtonTapped(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            context.tr('next'),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(1),
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(width: 10),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String exportToJsonString(BuildContext context) {
    return PostExporter.exportToJsonString(
      editorService: editorService,
      stickerService: stickerService,
      viewportSize: MediaQuery.of(context).size,
      pretty: true,
      forPublishing: true, // 발행 시점에는 네트워크 URL로 변환
    );
  }
}
