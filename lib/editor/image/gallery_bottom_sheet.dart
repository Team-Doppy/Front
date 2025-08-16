import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';
import 'package:flutter/services.dart';

class GalleryBottomSheet extends StatefulWidget {
  final Function(List<File>) onImagesSelected;

  const GalleryBottomSheet({
    Key? key,
    required this.onImagesSelected,
  }) : super(key: key);

  @override
  State<GalleryBottomSheet> createState() => _GalleryBottomSheetState();
}

class _GalleryBottomSheetState extends State<GalleryBottomSheet>
    with WidgetsBindingObserver {
  List<AssetEntity> _photos = [];
  Set<String> _selectedPhotoIds = {};
  bool _isLoading = true;
  String? _error;
  bool _isPermissionRequesting = false;

  // 메모리 관리를 위한 변수들
  final Map<String, File?> _imageCache = {};
  final Map<String, Uint8List> _imageDataCache = {};
  static const int _maxCacheSize = 20;

  // 이미지 로드 상태 관리 (깜빡임 방지)
  final Map<String, bool> _imageLoadingStates = {};
  final Map<String, File?> _imageResults = {};

  // 임시 파일 관리 - Instagram 방식으로 복원
  final List<Directory> _tempDirs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionStatus();

    // 권한이 있으면 사진 로드 후 이미지들도 미리 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_photos.isNotEmpty) {
        _preloadAllImages();
      }
    });
  }

  // 모든 이미지를 미리 로드 (빌드 중 setState 방지)
  Future<void> _preloadAllImages() async {
    for (final photo in _photos) {
      final photoId = photo.id;

      // 이미 로드된 이미지는 건너뛰기
      if (_imageResults.containsKey(photoId) &&
          _imageResults[photoId] != null) {
        continue;
      }

      // 이미 로딩 중인 이미지는 건너뛰기
      if (_imageLoadingStates[photoId] == true) {
        continue;
      }

      // 로딩 상태 시작
      setState(() {
        _imageLoadingStates[photoId] = true;
      });

      // 비동기로 이미지 로드
      _loadImageAsync(photo);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // 메모리 정리
    _imageCache.clear();
    _imageDataCache.clear();
    _photos.clear();
    _selectedPhotoIds.clear();

    // 임시 파일 정리 - Instagram 방식
    _cleanupTempFiles();

    super.dispose();
  }

  // 임시 파일 정리 - Instagram 방식
  Future<void> _cleanupTempFiles() async {
    for (final tempDir in _tempDirs) {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (e) {
        print('임시 디렉토리 정리 실패: $e');
      }
    }
    _tempDirs.clear();
  }

  // 임시 디렉토리 생성 (iOS 시뮬레이터 경로 길이 문제 해결)
  Future<Directory> _createTempDirectory() async {
    // 경로를 단순화하여 iOS 시뮬레이터 제한 우회
    final tempDir = await Directory.systemTemp.createTemp('img_');
    _tempDirs.add(tempDir);
    return tempDir;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 앱이 포그라운드로 돌아왔을 때 권한 상태 재확인
    if (state == AppLifecycleState.resumed && _isPermissionRequesting) {
      _checkPermissionAfterResume();
    }
  }

  Future<void> _checkPermissionAfterResume() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (permission.isAuth) {
        await _loadPhotos();
      }
    } catch (e) {
      print('앱 재개 후 권한 확인 오류: $e');
    }
  }

  // 권한 상태 확인
  Future<void> _checkPermissionStatus() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();

      if (permission.isAuth) {
        await _loadPhotos();
      } else {
        setState(() {
          _error = '갤러리 접근 권한이 필요합니다.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '권한 확인 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    if (_isPermissionRequesting) return; // 중복 요청 방지

    try {
      setState(() {
        _isPermissionRequesting = true;
        _error = null;
      });

      // iOS 권한 요청 UI가 안정화되도록 대기
      await Future.delayed(const Duration(milliseconds: 300));

      // 권한 요청 전에 현재 상태 재확인
      final currentPermission = await PhotoManager.requestPermissionExtend();
      if (currentPermission.isAuth) {
        // 이미 권한이 있으면 바로 로드
        await _loadPhotos();
        return;
      }

      // 권한 요청 (더 안전한 방식)
      final permission = await PhotoManager.requestPermissionExtend();

      if (permission.isAuth) {
        // 권한이 허용되면 사진 로드
        await _loadPhotos();
      } else {
        // 권한이 거부되면 설정으로 이동 안내
        setState(() {
          _error = '갤러리 접근 권한이 거부되었습니다. 설정에서 권한을 허용해주세요.';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('권한 요청 오류: $e');

      // 권한 요청 실패 시 fallback: 현재 상태 재확인
      try {
        final fallbackPermission = await PhotoManager.requestPermissionExtend();
        if (fallbackPermission.isAuth) {
          await _loadPhotos();
          return;
        }
      } catch (fallbackError) {
        print('Fallback 권한 확인 실패: $fallbackError');
      }

      setState(() {
        _error = '권한 요청 중 오류가 발생했습니다. 설정에서 갤러리 권한을 허용해주세요.';
        _isLoading = false;
      });
    } finally {
      setState(() {
        _isPermissionRequesting = false;
      });
    }
  }

  Future<void> _loadPhotos() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // 더 안전한 방식으로 사진 가져오기
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final recentAlbum = albums.first;

        // 사진 개수를 제한하여 메모리 사용량 줄이기
        final photos = await recentAlbum.getAssetListRange(start: 0, end: 50);

        setState(() {
          _photos = photos;
          _isLoading = false;
        });

        // 이미지 로드 상태 초기화 (깜빡임 방지)
        _initializeImageStates();

        // 사진 로드 완료 후 이미지들 프리로드
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _preloadAllImages();
        });
      } else {
        setState(() {
          _error = '사진을 찾을 수 없습니다.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '사진을 불러오는 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  // 이미지 캐시 관리 (파일과 이미지 데이터 모두)
  void _addToCache(String id, File? file, {Uint8List? imageData}) {
    if (_imageCache.length >= _maxCacheSize) {
      // 가장 오래된 항목 제거 (LRU 방식)
      final oldestKey = _imageCache.keys.first;
      _imageCache.remove(oldestKey);
      _imageDataCache.remove(oldestKey);
    }
    _imageCache[id] = file;
    if (imageData != null) {
      _imageDataCache[id] = imageData;
    }
  }

  // 이미지 데이터가 있는지 확인
  bool _hasImageData(String id) {
    return _imageDataCache.containsKey(id) && _imageDataCache[id]!.isNotEmpty;
  }

  // 이미지 데이터 가져오기
  Uint8List? _getImageData(String id) {
    return _imageDataCache[id];
  }

  Future<File?> _getImageFileSafely(AssetEntity asset) async {
    final String assetId = asset.id;

    // 캐시에서 먼저 확인
    if (_imageCache.containsKey(assetId)) {
      final cachedFile = _imageCache[assetId];
      if (cachedFile != null && await cachedFile.exists()) {
        return cachedFile;
      } else {
        // 캐시된 파일이 존재하지 않으면 캐시에서 제거
        _imageCache.remove(assetId);
      }
    }

    try {
      // 1단계: 로컬 파일 시도 (Instagram 방식 - 원본 우선)
      final file = await asset.file;
      if (file != null && await file.exists()) {
        _addToCache(assetId, file);
        return file;
      } else {}
    } catch (e) {}

    // 2단계: 이미지 데이터를 임시 File로 변환 (Instagram 방식)
    try {
      final imageData = await asset.thumbnailData;
      if (imageData != null && imageData.isNotEmpty) {
        // Instagram 방식: 이미지 데이터를 임시 File로 변환
        try {
          final tempDir = await _createTempDirectory();
          // 파일명을 단순화하여 경로 길이 문제 해결
          final tempFile =
              File('${tempDir.path}/img_${assetId.substring(0, 8)}.jpg');
          await tempFile.writeAsBytes(imageData);

          _addToCache(assetId, tempFile);
          return tempFile; // 성공으로 처리!
        } catch (fileError) {
          print('❌ 임시 File 변환 실패: $fileError');
          // 변환 실패 시에도 이미지 데이터는 캐시에 저장
          _addToCache(assetId, null, imageData: imageData);
        }
      } else {}
    } catch (e) {}

    // 모든 방법 실패
    _addToCache(assetId, null);
    return null;
  }

  void _togglePhotoSelection(String photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
      } else {
        _selectedPhotoIds.add(photoId);
      }
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedPhotoIds.isEmpty) {
      return;
    }

    try {
      setState(() {
        _isLoading = true; // 로딩 상태 표시
      });

      final selectedPhotos = _photos
          .where((photo) => _selectedPhotoIds.contains(photo.id))
          .toList();

      final files = <File>[];
      int successCount = 0;
      int failCount = 0;

      for (int i = 0; i < selectedPhotos.length; i++) {
        final photo = selectedPhotos[i];

        try {
          // 안전한 이미지 파일 로드 메서드 사용
          final file = await _getImageFileSafely(photo);

          if (file != null && await file.exists()) {
            files.add(file);
            successCount++;
          } else {
            failCount++;
          }
        } catch (e) {
          failCount++;
          // 개별 이미지 로드 실패는 건너뛰고 계속 진행
          continue;
        }
      }

      if (files.isNotEmpty) {
        // 성공한 이미지들만 전달
        widget.onImagesSelected(files);
        Navigator.of(context).pop();
      } else {
        // 모든 이미지 로드 실패
        setState(() {
          _isLoading = false;
        });

        print('❌ 선택된 이미지를 로드할 수 없습니다. (실패: $failCount개)');
      }
    } catch (e) {
      print('❌ 이미지 선택 확인 중 치명적 오류: $e');
      setState(() {
        _isLoading = false;
      });
      print('🚨 이미지 선택 중 오류가 발생했습니다: $e');
    }
  }

  // 이미지 로드 상태 초기화 (깜빡임 방지)
  void _initializeImageStates() {
    for (final photo in _photos) {
      final photoId = photo.id;
      // 모든 이미지를 로딩되지 않은 상태로 초기화
      _imageLoadingStates[photoId] = false;
      _imageResults[photoId] = null;
    }
  }

  // 이미지 로드 완료 (상태 고정)
  void _completeImageLoad(String photoId, File? file) {
    setState(() {
      _imageLoadingStates[photoId] = false;
      _imageResults[photoId] = file;
    });
  }

  Widget _buildOptimizedImage(AssetEntity photo) {
    final photoId = photo.id;
    final isLoading = _imageLoadingStates[photoId] ?? false;
    final hasResult = _imageResults.containsKey(photoId);
    final result = _imageResults[photoId];

    // 이미 로드된 결과가 있으면 바로 반환 (깜빡임 방지)
    if (hasResult && result != null) {
      return Image.file(
        result,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[200],
            child: Icon(
              Icons.image_not_supported,
              color: Colors.grey[400],
            ),
          );
        },
      );
    }

    // 이미지 데이터가 있으면 표시
    if (_hasImageData(photoId)) {
      final imageData = _getImageData(photoId);
      if (imageData != null) {
        return Image.memory(
          imageData,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              child: Icon(
                Icons.image_not_supported,
                color: Colors.grey[400],
              ),
            );
          },
        );
      }
    }

    // 로딩 중이면 로딩 표시
    if (isLoading) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 로드되지 않은 이미지는 기본 아이콘 표시
    return Container(
      color: Colors.grey[200],
      child: Icon(
        Icons.image_not_supported,
        color: Colors.grey[400],
      ),
    );
  }

  // 비동기 이미지 로드 (깜빡임 방지)
  Future<void> _loadImageAsync(AssetEntity photo) async {
    final photoId = photo.id;

    try {
      final file = await _getImageFileSafely(photo);
      _completeImageLoad(photoId, file);
    } catch (e) {
      _completeImageLoad(photoId, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '갤러리에서 선택',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_selectedPhotoIds.length}개 선택됨',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_selectedPhotoIds.isNotEmpty)
                      TextButton(
                        onPressed: _isLoading ? null : _confirmSelection,
                        child: _isLoading
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('처리 중...'),
                                ],
                              )
                            : const Text(
                                '선택 완료',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    IconButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 갤러리 그리드
          Expanded(
            child: _buildGalleryContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_error!.contains('권한이 필요합니다') || _error!.contains('권한을 허용해주세요'))
              ElevatedButton(
                onPressed: _isPermissionRequesting ? null : _requestPermission,
                child: _isPermissionRequesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('권한 허용'),
              )
            else
              ElevatedButton(
                onPressed: _checkPermissionStatus,
                child: const Text('다시 시도'),
              ),
          ],
        ),
      );
    }

    if (_photos.isEmpty) {
      return const Center(
        child: Text(
          '사진이 없습니다.',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        final isSelected = _selectedPhotoIds.contains(photo.id);

        return GestureDetector(
          onTap: () => _togglePhotoSelection(photo.id),
          child: Stack(
            children: [
              // 이미지
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildOptimizedImage(photo),
                ),
              ),

              // 체크박스
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey[400]!,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
