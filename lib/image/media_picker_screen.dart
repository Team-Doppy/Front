import 'dart:io';
import 'dart:typed_data';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/image/simple_image_editor_screen.dart';
import 'package:doppy/image/video_trim_screen.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// iOS 스타일 미디어 선택 화면
class MediaPickerScreen extends StatefulWidget {
  final Function(File) onMediaSelected;
  final VoidCallback? onCancel;
  final MediaType initialMediaType; // 초기 미디어 타입
  final int maxSelectionCount; // 최대 선택 개수
  final bool enableToggle; // 토글 가능 여부
  // ✅ "팝(pop) 전에" 상위 화면(에디터 등)에서 노드 삽입/프리캐시 같은 작업을 수행할 수 있도록 훅 제공
  final Future<void> Function(MediaPickerResult result)? onBeforePop;
  // ✅ onBeforePop 이후, 짧은 여유 시간(디코드/캐시/프레임 안정화)을 주기 위한 딜레이
  final Duration beforePopDelay;

  const MediaPickerScreen({
    super.key,
    required this.onMediaSelected,
    this.onCancel,
    this.initialMediaType = MediaType.video,
    this.maxSelectionCount = 1,
    this.enableToggle = true,
    this.onBeforePop,
    this.beforePopDelay = const Duration(milliseconds: 180),
  });

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

/// MediaPickerScreen에서 반환되는 결과
class MediaPickerResult {
  final List<File> files;
  final MediaType selectedMediaType; // 실제로 선택된 미디어 타입
  final GroupImageLayout? groupLayout; // 🎯 그룹 이미지 레이아웃 (선택된 경우만)
  final String? thumbnailPath; // 🎯 비디오 썸네일 경로 (비디오인 경우만)

  MediaPickerResult({
    required this.files,
    required this.selectedMediaType,
    this.groupLayout,
    this.thumbnailPath,
  });
}

enum MediaType { video, image }

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  List<AssetEntity> _media = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  final List<String> _selectedMediaIds = []; // 선택된 미디어 ID들 (선택 순서 유지)
  MediaType _mediaType = MediaType.video; // 현재 선택된 미디어 타입
  int _crossAxisCount = 3; // 그리드 열 수 (5열(최소) -> 3열(기본) -> 1열(최대))
  double _lastScale = 1.0; // 마지막 핀치 스케일
  final Duration _gridAnimationDuration = const Duration(milliseconds: 300);
  int _maxSelectionCount = 1; // 현재 최대 선택 개수 (미디어 타입에 따라 동적 변경)

  // 🎯 페이지네이션
  int _currentPage = 0;
  final int _pageSize = 100; // 한 번에 로드할 개수
  bool _hasMoreMedia = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  bool _isSubmitting = false;
  Future<void> _popWithResult(MediaPickerResult result) async {
    if (!mounted) return;
    if (_isSubmitting) return;
    _isSubmitting = true;

    try {
      if (widget.onBeforePop != null) {
        await widget.onBeforePop!(result);
        if (widget.beforePopDelay > Duration.zero) {
          await Future.delayed(widget.beforePopDelay);
        }
      }
    } catch (e) {
      debugPrint('[MediaPicker] onBeforePop 실패: $e');
    }

    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  // 🎯 All 앨범 캐시 (미디어 목록은 캐시하지 않음)
  AssetPathEntity? _cachedAllAlbum;
  MediaType? _cachedAllAlbumType;

  Future<AssetPathEntity?> _getAllAlbum(MediaType type) async {
    if (_cachedAllAlbum != null && _cachedAllAlbumType == type) {
      return _cachedAllAlbum;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: type == MediaType.video ? RequestType.video : RequestType.image,
      hasAll: true,
    );
    if (paths.isEmpty) return null;
    // '전체/최근' 앨범 우선
    final allAlbum = paths.firstWhere(
      (p) => p.isAll,
      orElse: () => paths.first,
    );
    _cachedAllAlbum = allAlbum;
    _cachedAllAlbumType = type;
    return allAlbum;
  }

  @override
  void initState() {
    super.initState();
    _mediaType = widget.initialMediaType;
    // 미디어 타입에 따라 최대 선택 개수 설정
    if (_mediaType == MediaType.image) {
      // 이미지: widget.maxSelectionCount가 명시적으로 1이면 1, 아니면 최소 5개
      _maxSelectionCount =
          widget.maxSelectionCount == 1
              ? 1 // 🎯 명시적으로 1이면 1개만 선택 가능 (프로필, 그룹 이미지 등)
              : (widget.maxSelectionCount > 1
                  ? widget.maxSelectionCount
                  : 6); // 기본값 5개
    } else {
      // 영상: 항상 1개만 선택 가능
      _maxSelectionCount = 1;
    }

    // 🎯 스크롤 리스너 추가 (페이지네이션)
    _scrollController.addListener(_onScroll);

    _requestPermissionAndLoadVideos();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // 🎯 스크롤 끝에 가까워지면 추가 로드
  void _onScroll() {
    if (_isLoadingMore || !_hasMoreMedia) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // 80% 지점에서 추가 로드
    if (currentScroll >= maxScroll * 0.8) {
      _loadMoreMedia();
    }
  }

  Future<void> _requestPermissionAndLoadVideos() async {
    try {
      // 권한 상태 확인
      final PermissionState ps = await PhotoManager.requestPermissionExtend();

      if (!mounted) return;

      if (ps.isAuth) {
        setState(() {
          _hasPermission = true;
        });
        await _loadMedia();
      } else if (ps == PermissionState.denied) {
        // 권한이 거부된 경우 설정으로 이동
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
        if (mounted) {
          // build 중이 아닐 때 호출
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              PhotoManager.openSetting();
            }
          });
        }
      } else {
        // 권한이 제한된 경우
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('권한 요청 오류: $e');
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMedia() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _currentPage = 0;
        _hasMoreMedia = true;
        _media = [];
      });
    }

    try {
      final allAlbum = await _getAllAlbum(_mediaType);
      if (allAlbum == null) {
        debugPrint(
          '[MediaPicker] ${_mediaType == MediaType.video ? "영상" : "이미지"} All 앨범이 없습니다',
        );
        if (!mounted) return;
        setState(() {
          _media = [];
          _isLoading = false;
          _hasMoreMedia = false;
        });
        return;
      }

      // ✅ 정석: 진짜 페이지네이션 (전체를 메모리에 올리지 않음)
      final pageAssets = await allAlbum.getAssetListPaged(
        page: 0,
        size: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _media = pageAssets;
        _hasMoreMedia = pageAssets.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('미디어 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 🎯 추가 미디어 로드 (페이지네이션)
  Future<void> _loadMoreMedia() async {
    if (_isLoadingMore || !_hasMoreMedia) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final allAlbum = await _getAllAlbum(_mediaType);
      if (allAlbum == null) {
        if (!mounted) return;
        setState(() {
          _hasMoreMedia = false;
          _isLoadingMore = false;
        });
        return;
      }

      _currentPage++;
      final nextPage = await allAlbum.getAssetListPaged(
        page: _currentPage,
        size: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _media.addAll(nextPage);
        _hasMoreMedia = nextPage.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('[MediaPicker] ❌ 추가 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _hasMoreMedia = false;
        });
      }
    }
  }

  void _toggleMediaSelection(AssetEntity asset) {
    setState(() {
      // ★ 1) 영상 선택 모드: 항상 단일 선택, 토글 가능 (다시 탭하면 해제)
      final isVideoMode =
          _mediaType == MediaType.video && _maxSelectionCount == 1;

      if (isVideoMode) {
        final alreadySelected = _selectedMediaIds.contains(asset.id);
        if (alreadySelected) {
          // 다시 탭하면 해제
          _selectedMediaIds.clear();
          return;
        } else {
          // 다른 영상을 선택하면 교체
          _selectedMediaIds.clear();
          _selectedMediaIds.add(asset.id);
          return;
        }
      }

      // ★ 2) 단일 이미지 모드 + 토글 불가 (영상처럼 동작)
      final isSingleNoToggle =
          _mediaType == MediaType.image &&
          _maxSelectionCount == 1 &&
          !widget.enableToggle;

      if (isSingleNoToggle) {
        final alreadySelected = _selectedMediaIds.contains(asset.id);
        if (alreadySelected) {
          // 다시 탭해도 해제 안함
          return;
        } else {
          // 다른 이미지를 선택하면 교체
          _selectedMediaIds.clear();
          _selectedMediaIds.add(asset.id);
          return;
        }
      }

      // ★ 3) 단일 이미지 모드 + 토글 가능 (기존 iOS 사진앱 방식)
      final isSingleWithToggle =
          _mediaType == MediaType.image &&
          _maxSelectionCount == 1 &&
          widget.enableToggle;

      if (isSingleWithToggle) {
        if (_selectedMediaIds.contains(asset.id)) {
          // 선택된 것 다시 누르면 해제됨
          _selectedMediaIds.clear();
        } else {
          // 다른 것 탭하면 교체
          _selectedMediaIds.clear();
          _selectedMediaIds.add(asset.id);
        }
        return;
      }

      // ★ 4) 다중 선택 모드
      if (_selectedMediaIds.contains(asset.id)) {
        _selectedMediaIds.remove(asset.id);
      } else {
        if (_selectedMediaIds.length >= _maxSelectionCount) {
          // 가장 오래된 선택 제거 (리스트의 첫 번째 요소)
          _selectedMediaIds.removeAt(0);
        }
        _selectedMediaIds.add(asset.id);
      }
    });
  }

  void _onMediaTypeChanged(MediaType type) async {
    if (_mediaType != type && widget.enableToggle) {
      // 🎯 타입 변경 시 선택 초기화 및 모든 설정 동기화
      setState(() {
        _mediaType = type;
        _selectedMediaIds.clear(); // 선택 초기화
        // 미디어 타입에 따라 최대 선택 개수 변경
        if (type == MediaType.image) {
          // 🎯 이미지로 변경 시:
          // - 토글 가능하고(enableToggle: true) + 초기 타입이 비디오였던 경우 → 에디터에서 들어온 것 → 무조건 5개
          // - 그 외의 경우는 widget.maxSelectionCount를 따름
          if (widget.enableToggle &&
              widget.initialMediaType == MediaType.video) {
            _maxSelectionCount = 6; // 에디터에서 영상으로 들어왔다가 이미지로 토글 → 6개
          } else {
            _maxSelectionCount =
                widget.maxSelectionCount == 1
                    ? 1 // 명시적으로 1이면 1개만 (프로필 이미지 등)
                    : (widget.maxSelectionCount > 1
                        ? widget.maxSelectionCount
                        : 6); // 기본값 6개
          }
        } else {
          // 영상으로 변경 시: 항상 1개만 선택 가능
          _maxSelectionCount = 1;
        }
        // 그리드 열 수 초기화 (미디어 타입 변경 시 기본값으로)
        _crossAxisCount = 3;
        // 핀치 스케일 초기화
        _lastScale = 1.0;
        // 🎯 페이지네이션 초기화
        _currentPage = 0;
        _hasMoreMedia = true;
        _isLoadingMore = false;
        _media = [];
      });

      // 🎯 타입 변경 시 All 앨범 캐시 갱신(무효화)
      _cachedAllAlbum = null;
      _cachedAllAlbumType = null;

      _loadMedia();
    }
  }

  Future<void> _handleImageEdit(List<AssetEntity> selectedAssets) async {
    // ✅ selectedAssets는 이미 선택 순서대로 정렬되어 있음
    try {
      // 선택된 이미지들을 Uint8List로 변환
      final List<Uint8List> imageBytesList = [];

      for (final asset in selectedAssets) {
        final file = await asset.originFile;
        if (file != null) {
          final bytes = await file.readAsBytes();
          imageBytesList.add(bytes);
        }
      }

      if (imageBytesList.isEmpty || !mounted) return;

      // 이미지 편집 화면으로 이동
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (editorContext) {
            return SimpleImageEditorScreen(
              imageBytesList: imageBytesList,
              onDone: (editorContext, result) async {
                if (_isSubmitting) return;
                if (!mounted) return;
                _isSubmitting = true;

                // ✅ SimpleImageEditorScreen 반환값 호환:
                // - 단일: Uint8List
                // - 다중(구형): List<Uint8List>
                // - 다중(신규): { 'images': List<Uint8List>, 'layout': GroupImageLayout }
                List<Uint8List>? editedImages;
                GroupImageLayout? selectedLayout;

                if (result is Uint8List) {
                  editedImages = [result];
                  selectedLayout = null;
                } else if (result is List<Uint8List>) {
                  if (result.isEmpty) return;
                  editedImages = result;
                  // 구형 반환(레이아웃 없음)은 개별 이미지로 간주
                  selectedLayout = GroupImageLayout.individual;
                } else if (result is Map) {
                  final dynamic imagesAny = result['images'];
                  final dynamic layoutAny = result['layout'];

                  if (imagesAny is List<Uint8List> && imagesAny.isNotEmpty) {
                    editedImages = imagesAny;
                  } else {
                    return;
                  }

                  if (layoutAny is GroupImageLayout) {
                    selectedLayout = layoutAny;
                  } else {
                    // 레이아웃이 없으면 개별 이미지로 간주
                    selectedLayout = GroupImageLayout.individual;
                  }
                } else {
                  return;
                }

                // ✅ 업로드/에디터 삽입을 위해 임시 파일로 저장 (삭제하지 않음)
                final tempDir = await Directory.systemTemp.createTemp();
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final List<File> files = [];

                for (int i = 0; i < editedImages.length; i++) {
                  final tempFile = File(
                    '${tempDir.path}/edited_${timestamp}_$i.jpg',
                  );
                  await tempFile.writeAsBytes(editedImages[i]);
                  files.add(tempFile);
                }

                if (!mounted) return;

                // 기존 콜백 유지
                for (final f in files) {
                  widget.onMediaSelected(f);
                }

                final pickerResult = MediaPickerResult(
                  files: files,
                  selectedMediaType: MediaType.image,
                  groupLayout: selectedLayout,
                );

                // ✅ onBeforePop + 딜레이를 먼저 수행한 뒤, "에디터 + 피커"를 연속으로 pop
                try {
                  if (widget.onBeforePop != null) {
                    await widget.onBeforePop!(pickerResult);
                    if (widget.beforePopDelay > Duration.zero) {
                      await Future.delayed(widget.beforePopDelay);
                    }
                  }
                } catch (e) {
                  debugPrint('[MediaPicker] onBeforePop 실패: $e');
                }

                if (!mounted) return;

                final nav = Navigator.of(editorContext);
                nav.pop(); // 에디터 닫기
                nav.pop(pickerResult); // 피커 닫기 (같은 타이밍)
              },
            );
          },
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      debugPrint('이미지 편집 오류: $e');
      if (mounted) {
        await DialogUtils.showInfoDialog(
          context,
          title: '오류',
          message: '이미지를 불러올 수 없습니다.',
        );
      }
    }
  }

  Future<void> _handleGroupImage(List<AssetEntity> selectedAssets) async {
    try {
      // 선택된 이미지들을 File로 변환
      final List<File> imageFiles = [];

      for (final asset in selectedAssets) {
        final file = await asset.originFile;
        if (file != null) {
          imageFiles.add(file);
        }
      }

      if (imageFiles.isEmpty || !mounted) return;

      debugPrint('그룹이미지: ${imageFiles.length}개 이미지 변환 완료');

      // 🎯 레이아웃 선택 화면을 모달 바텀시트로 표시 (일관된 UX)
      bool didSelectLayout = false;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder:
            (sheetContext) => GroupImageLayoutSelector(
              previewImages: imageFiles,
              onSelected: (layout) async {
                if (didSelectLayout) return;
                if (!mounted) return;
                if (_isSubmitting) return;

                didSelectLayout = true;
                _isSubmitting = true;

                debugPrint(
                  '[MediaPicker] ✅ 그룹이미지 선택 완료: ${imageFiles.length}개, 레이아웃: $layout',
                );

                final result = MediaPickerResult(
                  files: imageFiles,
                  selectedMediaType: MediaType.image,
                  groupLayout: layout,
                );

                // ✅ 여기서는 "시트 + 피커"를 마지막에 함께 닫기 위해,
                // onBeforePop/딜레이를 먼저 수행한 뒤 pop을 연속 호출한다.
                try {
                  if (widget.onBeforePop != null) {
                    await widget.onBeforePop!(result);
                    if (widget.beforePopDelay > Duration.zero) {
                      await Future.delayed(widget.beforePopDelay);
                    }
                  }
                } catch (e) {
                  debugPrint('[MediaPicker] onBeforePop 실패: $e');
                }

                if (!mounted) return;

                // 🎯 같은 타이밍에 닫히도록 pop을 연속 호출
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pop(result);
              },
            ),
      );

      if (!didSelectLayout) {
        debugPrint('[MediaPicker] ⚠️ 레이아웃 선택 취소됨');
      }
    } catch (e) {
      debugPrint('그룹이미지 오류: $e');
      if (mounted) {
        await DialogUtils.showInfoDialog(
          context,
          title: AppLocalizations.of(context).t('error'),
          message: AppLocalizations.of(context).t('cannot_load_image'),
        );
      }
    }
  }

  Future<void> _handleAdd() async {
    if (_selectedMediaIds.isEmpty) return;

    try {
      // 선택된 미디어들 찾기 (선택 순서대로 유지)
      final selectedAssets = <AssetEntity>[];
      final mediaMap = {for (var asset in _media) asset.id: asset};
      for (final id in _selectedMediaIds) {
        final asset = mediaMap[id];
        if (asset != null) {
          selectedAssets.add(asset);
        }
      }

      if (selectedAssets.isEmpty) return;

      // 최대 1개만 선택 가능한 경우
      if (_maxSelectionCount == 1) {
        final asset = selectedAssets.first;
        final File? file = await asset.originFile;
        if (file != null && mounted) {
          // 🎯 영상이면 모든 경우에 편집 화면으로 이동
          if (asset.type == AssetType.video) {
            try {
              final duration = asset.videoDuration;
              // 모든 영상에 대해 편집 화면으로 이동 (애니메이션 없이 바로 표시)
              final trimResult = await Navigator.push<TrimmedVideoResult>(
                context,
                PageRouteBuilder(
                  pageBuilder:
                      (context, animation, secondaryAnimation) =>
                          VideoTrimScreen(
                            videoFile: file,
                            videoDuration: duration,
                          ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );

              if (trimResult != null && mounted) {
                widget.onMediaSelected(trimResult.videoFile);
                Navigator.of(context).pop(
                  MediaPickerResult(
                    files: [trimResult.videoFile],
                    selectedMediaType: _mediaType,
                    thumbnailPath: trimResult.thumbnailPath, // 🎯 썸네일 경로 포함
                  ),
                );
              }
              return;
            } catch (e) {
              debugPrint('영상 길이 확인 오류: $e');
            }
          }

          // 이미지는 바로 반환
          widget.onMediaSelected(file);
          Navigator.of(context).pop(
            MediaPickerResult(files: [file], selectedMediaType: _mediaType),
          );
        }
      } else {
        // 여러 개 선택 가능한 경우 - 모든 파일 반환
        final List<File> files = [];
        for (final asset in selectedAssets) {
          final File? file = await asset.originFile;
          if (file != null) {
            files.add(file);
          }
        }

        if (files.isNotEmpty && mounted) {
          // 모든 파일을 한 번에 전달하기 위해 각각 호출
          for (final file in files) {
            widget.onMediaSelected(file);
          }
          // 🎯 실제로 선택된 미디어 타입과 함께 반환
          await _popWithResult(
            MediaPickerResult(files: files, selectedMediaType: _mediaType),
          );
        }
      }
    } catch (e) {
      debugPrint('미디어 선택 오류: $e');
      if (mounted) {
        await DialogUtils.showInfoDialog(
          context,
          title: AppLocalizations.of(context).t('error'),
          message: AppLocalizations.of(context).t('cannot_load_media'),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // null을 반환하여 취소를 나타냄
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(null);
        }
      },
      child: CupertinoPageScaffold(
        backgroundColor: colorScheme.surface,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.onSurface.withOpacity(0.1),
              width: 0.5,
            ),
          ),
          middle:
              widget.enableToggle
                  ? CupertinoSlidingSegmentedControl<MediaType>(
                    groupValue: _mediaType,
                    backgroundColor: colorScheme.surface.withOpacity(0.1),
                    thumbColor: colorScheme.onSurface,
                    onValueChanged: (value) {
                      if (value != null) {
                        _onMediaTypeChanged(value);
                      }
                    },
                    children: {
                      MediaType.video: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          AppLocalizations.of(context).t('media_type_video'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                _mediaType == MediaType.image
                                    ? colorScheme.onSurface.withOpacity(0.5)
                                    : colorScheme.surface,
                          ),
                        ),
                      ),
                      MediaType.image: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          AppLocalizations.of(context).t('media_type_image'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                _mediaType == MediaType.image
                                    ? colorScheme.surface
                                    : colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ),
                    },
                  )
                  : Text(
                    _mediaType == MediaType.video
                        ? AppLocalizations.of(context).t('select_video')
                        : AppLocalizations.of(context).t('select_image'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: Text(
              AppLocalizations.of(context).t('cancel'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _selectedMediaIds.isNotEmpty ? _handleAdd : null,
                child: Text(
                  _mediaType == MediaType.video
                      ? AppLocalizations.of(context).t('next')
                      : _maxSelectionCount > 1 && _selectedMediaIds.isNotEmpty
                      ? AppLocalizations.of(context)
                          .t('add_with_count')
                          .replaceAll('{count}', '${_selectedMediaIds.length}')
                      : AppLocalizations.of(context).t('add'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color:
                        _selectedMediaIds.isNotEmpty
                            ? colorScheme.onSurface
                            : colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(child: _buildBody()),

            // 하단 툴바 (선택된 미디어가 있을 때만 표시)
            if (_selectedMediaIds.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomToolbar(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final colorScheme = Theme.of(context).colorScheme;
    // 선택된 미디어들 찾기 (선택 순서대로 유지)
    final selectedAssets = <AssetEntity>[];
    final mediaMap = {for (var asset in _media) asset.id: asset};
    for (final id in _selectedMediaIds) {
      final asset = mediaMap[id];
      if (asset != null) {
        selectedAssets.add(asset);
      }
    }

    // 선택된 미디어 타입 확인 (모두 같은 타입이어야 함)
    final isVideo =
        selectedAssets.isNotEmpty &&
        selectedAssets.first.type == AssetType.video;

    return Container(
      decoration: BoxDecoration(color: colorScheme.surface),
      padding: EdgeInsets.only(bottom: 0, top: 12, left: 16, right: 16),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (!isVideo) ...[
              // 이미지일 때: 그룹이미지, 이미지 편집
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: Colors.transparent,
                  onPressed: () => _handleGroupImage(selectedAssets),
                  child: Text(
                    AppLocalizations.of(context).t('group_image'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 4),
              Divider(color: colorScheme.onSurface.withOpacity(1), height: 24),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),

                  color: Colors.transparent,
                  onPressed: () => _handleImageEdit(selectedAssets),
                  child: Text(
                    AppLocalizations.of(context).t('edit_image'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
            /*
             else ...[
              // 영상일 때: 영상 편집
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: colorScheme.primary,
                  onPressed: () {
                    // TODO: 영상 편집 처리
                    debugPrint('영상 편집 선택');
                  },
                  child: Text(
                    AppLocalizations.of(context).t('edit_video'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],*/
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.photo_on_rectangle,
              size: 64,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(
                context,
              ).t('photo_library_permission_required'),
              style: const TextStyle(
                fontSize: 17,
                color: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton(
              onPressed: _requestPermissionAndLoadVideos,
              child: Text(
                AppLocalizations.of(context).t('open_permission_settings'),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (_media.isEmpty) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Text(
            _mediaType == MediaType.video
                ? AppLocalizations.of(context).t('no_videos')
                : AppLocalizations.of(context).t('no_images'),
            style: const TextStyle(
              fontSize: 17,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onScaleStart: (details) {
        _lastScale = 1.0;
      },
      onScaleUpdate: (details) {
        final currentScale = details.scale;
        final scaleDelta = currentScale - _lastScale;

        // 핀치 아웃 (늘리기) - 스케일이 증가하면 열 수 감소 (5 -> 3 -> 1)
        if (scaleDelta > 0.3) {
          final newCount =
              _crossAxisCount == 5
                  ? 3
                  : (_crossAxisCount == 3 ? 1 : _crossAxisCount);
          if (newCount != _crossAxisCount) {
            setState(() {
              _crossAxisCount = newCount;
            });
          }
          _lastScale = currentScale;
        }
        // 핀치 인 (줄이기) - 스케일이 감소하면 열 수 증가 (1 -> 3 -> 5)
        else if (scaleDelta < -0.3) {
          final newCount =
              _crossAxisCount == 1
                  ? 3
                  : (_crossAxisCount == 3 ? 5 : _crossAxisCount);
          if (newCount != _crossAxisCount) {
            setState(() {
              _crossAxisCount = newCount;
            });
          }
          _lastScale = currentScale;
        }
      },
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: _gridAnimationDuration,
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: GridView.builder(
              controller: _scrollController, // 🎯 스크롤 컨트롤러 연결
              key: ValueKey('${_crossAxisCount}_$_mediaType'),
              padding: const EdgeInsets.all(2),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _crossAxisCount,
                crossAxisSpacing: 1,
                mainAxisSpacing: 1,
                childAspectRatio:
                    _mediaType == MediaType.video
                        ? 2 / 3
                        : 4 / 5, // 영상: 2:3, 이미지: 4:5
              ),
              itemCount: _media.length,
              itemBuilder: (context, index) {
                final asset = _media[index];
                return _buildMediaThumbnail(asset, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaThumbnail(AssetEntity asset, int index) {
    final isSelected = _selectedMediaIds.contains(asset.id);
    final isVideo = asset.type == AssetType.video;

    // 🎯 비활성화 로직:
    // - 영상: 항상 활성화
    // - 단일 이미지 모드 (maxSelectionCount == 1): 항상 활성화 (다른 이미지 선택 시 교체되므로)
    // - 다중 이미지 모드: 최대 개수에 도달했고 선택되지 않은 이미지만 비활성화
    final isDisabled =
        !isVideo &&
        !isSelected &&
        _mediaType == MediaType.image &&
        _maxSelectionCount > 1 && // 🎯 다중 선택 모드일 때만 비활성화
        _selectedMediaIds.length >= _maxSelectionCount;

    if (isVideo) {
      return _VideoThumbnailWidget(
        key: ValueKey('video_thumbnail_${asset.id}_$index'),
        asset: asset,
        isSelected: isSelected,
        isDisabled: false, // 🎯 모든 영상 선택 가능 (2분 초과도 편집 화면에서 자를 수 있음)
        onTap: () => _toggleMediaSelection(asset),
        formatDuration: _formatDuration,
      );
    } else {
      return _ImageThumbnailWidget(
        key: ValueKey('image_thumbnail_${asset.id}_$index'),
        asset: asset,
        isSelected: isSelected,
        isDisabled: isDisabled, // 🎯 비활성화 상태 전달
        onTap: () => _toggleMediaSelection(asset),
      );
    }
  }
}

/// 비디오 썸네일 위젯 (photo_manager의 내장 썸네일 사용)
class _VideoThumbnailWidget extends StatelessWidget {
  final AssetEntity asset;
  final bool isSelected;
  final bool isDisabled; // 🎯 비활성화 상태 (3분 초과 영상)
  final VoidCallback onTap;
  final String Function(Duration) formatDuration;

  const _VideoThumbnailWidget({
    super.key,
    required this.asset,
    this.isSelected = false,
    this.isDisabled = false,
    required this.onTap,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap, // 🎯 비활성화 상태면 탭 불가
      child: Stack(
        fit: StackFit.expand,
        children: [
          // photo_manager의 내장 썸네일 사용
          AssetEntityImage(
            asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize(400, 400),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: CupertinoColors.systemGrey5,
                child: const Icon(
                  CupertinoIcons.videocam,
                  color: CupertinoColors.systemGrey,
                ),
              );
            },
          ),
          // 선택 오버레이

          // 재생 아이콘 및 재생 시간 오버레이
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [_buildDurationText()],
              ),
            ),
          ),
          // 🎯 선택된 영상에 흰색 투명 fill 적용
          if (isSelected)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.6), // 흰색 30% 투명도
              ),
            ),
          // 선택 표시 (우측 상단)
          if (isSelected)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 24,
                  height: 24,

                  child: Icon(Icons.check, color: Colors.black, size: 50),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDurationText() {
    try {
      final duration = asset.videoDuration;
      if (duration.inSeconds > 0) {
        return Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              formatDuration(duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('재생 시간 가져오기 오류: $e');
    }
    return const SizedBox.shrink();
  }
}

/// 이미지 썸네일 위젯
class _ImageThumbnailWidget extends StatelessWidget {
  final AssetEntity asset;
  final bool isSelected;
  final bool isDisabled; // 🎯 비활성화 상태 (5개 이상 선택된 경우)
  final VoidCallback onTap;

  const _ImageThumbnailWidget({
    super.key,
    required this.asset,
    this.isSelected = false,
    this.isDisabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap, // 🎯 비활성화 상태면 탭 불가
      child: Stack(
        fit: StackFit.expand,
        children: [
          // photo_manager의 내장 썸네일 사용
          AssetEntityImage(
            asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize(400, 400),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: CupertinoColors.systemGrey5,
                child: const Icon(
                  CupertinoIcons.photo,
                  color: CupertinoColors.systemGrey,
                ),
              );
            },
          ),
          // 🎯 비활성화된 이미지만 어둡게 처리
          if (isDisabled)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3), // 비활성화된 이미지만 어둡게
              ),
            ),
          // 🎯 선택된 이미지에 흰색 반투명 오버레이
          if (isSelected)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.6), // 흰색 30% 투명도
              ),
            ),
          // 선택 표시 (우측 상단)
          if (isSelected)
            Positioned(
              top: 8,
              right: 8,
              bottom: 8,
              left: 8,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 26,
                  height: 26,

                  child: Icon(Icons.check, color: Colors.black, size: 50),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
