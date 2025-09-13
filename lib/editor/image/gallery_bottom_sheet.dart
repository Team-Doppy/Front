import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:doppy/theme/app_colors.dart';

class GalleryBottomSheet extends StatefulWidget {
  final Function(List<File>) onImagesSelected;

  const GalleryBottomSheet({Key? key, required this.onImagesSelected})
    : super(key: key);

  @override
  State<GalleryBottomSheet> createState() => _GalleryBottomSheetState();
}

class _GalleryBottomSheetState extends State<GalleryBottomSheet> {
  List<AssetEntity> _assets = [];
  List<String> _selectedOrder = []; // 선택 순서 추적
  Map<String, AssetEntity> _assetById = {}; // ID로 빠른 검색
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      print('DEBUG: 갤러리 에셋 로딩 시작');

      // 권한 확인
      print('DEBUG: 사진 권한 확인 중...');
      final permission = await PhotoManager.requestPermissionExtend();
      print('DEBUG: 권한 상태: ${permission.isAuth}, ');

      if (!permission.isAuth) {
        setState(() {
          _error = '사진 접근 권한이 필요합니다. 설정에서 권한을 허용해주세요.';
          _isLoading = false;
        });
        return;
      }

      // 모든 이미지 가져오기
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );

      if (albums.isEmpty) {
        setState(() {
          _error = '사진이 없습니다';
          _isLoading = false;
        });
        return;
      }

      // 첫 번째 앨범(모든 사진)에서 에셋 가져오기
      final recentAlbum = albums.first;
      final assets = await recentAlbum.getAssetListPaged(
        page: 0,
        size: 1000, // 충분히 큰 수
      );

      print('DEBUG: 로드된 에셋 수: ${assets.length}');

      setState(() {
        _assets = assets;
        _isLoading = false;
        // ID로 빠른 검색을 위한 맵 생성
        _assetById = {for (var asset in assets) asset.id: asset};
      });
    } catch (e) {
      print('DEBUG: 에셋 로딩 오류: $e');
      setState(() {
        _error = '사진을 불러오는 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  void _togglePhotoSelection(String assetId) {
    setState(() {
      if (_selectedOrder.contains(assetId)) {
        // 이미 선택된 경우 제거
        _selectedOrder.remove(assetId);
      } else {
        // 선택되지 않은 경우 추가 (순서대로)
        _selectedOrder.add(assetId);
      }
    });
    print('DEBUG: 선택된 이미지 수: ${_selectedOrder.length}');
  }

  Future<void> _confirmSelection() async {
    if (_selectedOrder.isEmpty) {
      Navigator.pop(context);
      return;
    }

    print('DEBUG: 선택 확인 - ${_selectedOrder.length}개 이미지');

    try {
      final List<File> selectedFiles = [];

      // 선택된 순서대로 파일 처리
      for (final assetId in _selectedOrder) {
        final asset = _assetById[assetId];
        if (asset != null) {
          print('DEBUG: 에셋 처리 중: $assetId');
          try {
            // 먼저 로컬 파일 시도
            final file = await asset.file;
            if (file != null) {
              selectedFiles.add(file);
              print('DEBUG: 로컬 파일 추가됨: ${file.path}');
            } else {
              print('DEBUG: 로컬 파일이 null, 원본 시도: $assetId');
              // 로컬 파일이 없으면 원본 다운로드 시도
              try {
                final originFile = await asset.originFile;
                if (originFile != null) {
                  selectedFiles.add(originFile);
                  print('DEBUG: 원본 파일 추가됨: ${originFile.path}');
                } else {
                  print('DEBUG: 원본 파일도 null: $assetId');
                }
              } catch (originError) {
                print('DEBUG: 원본 다운로드 실패 - $assetId: $originError');
                // iCloud 오류는 무시하고 계속 진행
              }
            }
          } catch (e) {
            print('DEBUG: 파일 처리 중 오류 - $assetId: $e');
            // CloudPhotoLibraryErrorDomain 오류는 무시하고 계속 진행
            if (e.toString().contains('CloudPhotoLibraryErrorDomain')) {
              print('DEBUG: iCloud 이미지 오류 무시하고 계속 진행');
            }
          }
        }
      }

      print('DEBUG: 최종 선택된 파일 수: ${selectedFiles.length}');

      // 바텀시트 닫기
      Navigator.pop(context);

      // 이미지 선택 콜백 호출
      if (selectedFiles.isNotEmpty) {
        widget.onImagesSelected(selectedFiles);
      }
    } catch (e) {
      print('DEBUG: 선택 확인 중 오류: $e');
    }
  }

  Widget _buildOptimizedImage(AssetEntity asset) {
    return ClipRRect(
      child: AssetEntityImage(
        asset,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        thumbnailSize: const ThumbnailSize(200, 250), // 썸네일 크기 줄임
        isOriginal: false,
        errorBuilder: (context, error, stackTrace) {
          print('DEBUG: 이미지 로딩 실패 - ${asset.id}: $error');
          return Container(
            color: AppColors.darkSurfaceVariant,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image,
                  color: AppColors.darkTextSecondary,
                  size: 32,
                ),
                SizedBox(height: 4),
                Text(
                  '로딩 실패',
                  style: TextStyle(
                    color: AppColors.darkTextSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: AppColors.darkSurfaceVariant,
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectionBadge(int index) {
    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 32, 32, 32).withOpacity(0.9),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.darkBorder, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '취소',
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),

                TextButton(
                  onPressed: _confirmSelection,
                  child: Text(
                    '완료 (${_selectedOrder.length})',
                    style: TextStyle(
                      color:
                          _selectedOrder.isNotEmpty
                              ? AppColors.primary
                              : AppColors.darkTextSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 갤러리 그리드
          Expanded(
            child:
                _isLoading
                    ? Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                    : _error != null
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: AppColors.darkTextSecondary,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: AppColors.darkTextSecondary,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadAssets,
                            child: Text('다시 시도'),
                          ),
                        ],
                      ),
                    )
                    : _assets.isEmpty
                    ? Center(
                      child: Text(
                        '사진이 없습니다',
                        style: TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontSize: 16,
                        ),
                      ),
                    )
                    : GridView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                        childAspectRatio: 4 / 5, // 4:5 비율
                      ),
                      itemCount: _assets.length,
                      itemBuilder: (context, index) {
                        final asset = _assets[index];
                        final isSelected = _selectedOrder.contains(asset.id);
                        final selectionIndex =
                            isSelected ? _selectedOrder.indexOf(asset.id) : -1;

                        return GestureDetector(
                          onTap: () => _togglePhotoSelection(asset.id),
                          child: Stack(
                            children: [
                              _buildOptimizedImage(asset),
                              if (isSelected)
                                _buildSelectionBadge(selectionIndex),
                            ],
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
