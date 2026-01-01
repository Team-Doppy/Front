import 'dart:ui';

import 'package:doppy/editor/publish/post_export_screen.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/component/clip_component.dart' show muteAllVideos;
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
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
  });

  @override
  State<EditModeAppBar> createState() => _EditModeAppBarState();
}

class _EditModeAppBarState extends State<EditModeAppBar> {
  String? _thumbnailUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[EditModeAppBar] 썸네일 초기화: $_thumbnailUrl');

    // 수정 모드 진입 시 썸네일만 로드
    if (widget.postId != null) {
      _loadThumbnail();
    }
  }

  /// 수정 모드 진입 시 썸네일만 로드
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

      debugPrint('[EditModeAppBar] 썸네일 로드 완료: $_thumbnailUrl');
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
                  GestureDetector(
                    onTap: () async {
                      Navigator.of(context).maybePop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 24,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.75),
                      ),
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

                  // 영상 업로드 중일 때는 인디케이터 표시, 아니면 기존 버튼들 표시
                  ValueListenableBuilder<bool>(
                    valueListenable:
                        widget.videoUploadIndicatorNotifier ??
                        ValueNotifier<bool>(false),
                    builder: (context, showIndicator, child) {
                      if (showIndicator) {
                        // 영상 업로드 중 인디케이터
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        );
                      }

                      // 기존 버튼들
                      return Row(
                        children: [
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
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
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
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
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
    // 업로드 가드: 업로드 중인 미디어가 있으면 진행 차단
    if (editorService.hasUnuploadedImages()) {
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
                      GestureDetector(
                        onTap: () async {
                          Navigator.of(context).maybePop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 24,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.75),
                          ),
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
