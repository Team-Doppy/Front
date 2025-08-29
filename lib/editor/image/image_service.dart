import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  void _handleError(dynamic error, BuildContext? context) {
    if (error.toString().contains('permission') ||
        error.toString().contains('권한') ||
        error.toString().contains('denied') ||
        error.toString().contains('access') ||
        error.toString().contains('unauthorized')) {
      if (context != null) {
        _showPermissionErrorDialog(context, _getPermissionErrorMessage());
      }
      return;
    }
  }

  // API 기본 설정
  static String _baseUrl = ApiServiceBase.baseUrl; // 테스트용  서버

  Future<bool> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isDenied) {
        final result = await Permission.storage.request();
        if (result.isDenied || result.isPermanentlyDenied) {
          return false;
        }
      }
    } else if (Platform.isIOS) {
      final photosStatus = await Permission.photos.status;
      if (photosStatus.isDenied) {
        final result = await Permission.photos.request();
        if (result.isDenied || result.isPermanentlyDenied) {
          return false;
        }
      }
    }
    return true;
  }

  void _showPermissionErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('권한 필요'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('설정으로 이동'),
            ),
          ],
        );
      },
    );
  }

  String _getPermissionErrorMessage() {
    if (Platform.isAndroid) {
      return '이미지를 선택하려면 저장소 및 사진 접근 권한이 필요합니다.\n\n설정에서 권한을 허용해주세요.';
    } else if (Platform.isIOS) {
      return '이미지를 선택하려면 사진 라이브러리 접근 권한이 필요합니다.\n\n설정에서 권한을 허용해주세요.';
    } else {
      return '이미지를 선택하려면 파일 접근 권한이 필요합니다.';
    }
  }

  // 다중 이미지 삽입 (갤러리에서 선택된 여러 이미지)
  Future<void> insertMultipleImages(
    Editor documentEditor,
    MutableDocument document,
    List<File> imageFiles,
    VoidCallback analyzeAndUpdateDocument,
  ) async {
    try {
      if (imageFiles.isEmpty) return;

      // 10개씩 배치로 나누기
      const int batchSize = 10;
      final batches = <List<File>>[];

      for (int i = 0; i < imageFiles.length; i += batchSize) {
        final end =
            (i + batchSize < imageFiles.length)
                ? i + batchSize
                : imageFiles.length;
        batches.add(imageFiles.sublist(i, end));
      }

      print('${batches.length}개 배치로 분할 (배치당 최대 $batchSize개)');

      // 배치별로 순차 처리
      for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];
        print(
          '배치 ${batchIndex + 1}/${batches.length} 처리 시작 (${batch.length}개 이미지)',
        );

        await _uploadAndInsertImages(batch, documentEditor);

        // 배치 간 간격 (서버 부하 방지)
        if (batchIndex < batches.length - 1) {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }

      analyzeAndUpdateDocument();
      print(
        '✅ 모든 배치 처리 완료 후 SpatialManager 업데이트 수행 (총 ${imageFiles.length}개 이미지)',
      );
    } catch (e) {
      print('❌ 다중 이미지 삽입 실패: $e');
    }
  }

  // 웹용 다중 이미지 삽입 (XFile 기반)
  Future<void> insertMultipleWebImages(
    List<XFile> xFiles,
    Editor documentEditor,
    MutableDocument document,
    VoidCallback analyzeAndUpdateDocument,
  ) async {
    try {
      if (xFiles.isEmpty) return;

      // 10개씩 배치로 나누기
      const int batchSize = 10;
      final batches = <List<XFile>>[];

      for (int i = 0; i < xFiles.length; i += batchSize) {
        final end =
            (i + batchSize < xFiles.length) ? i + batchSize : xFiles.length;
        batches.add(xFiles.sublist(i, end));
      }

      print('${batches.length}개 배치로 분할 (배치당 최대 $batchSize개)');

      // 배치별로 순차 처리
      for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];
        print(
          '배치 ${batchIndex + 1}/${batches.length} 처리 시작 (${batch.length}개 이미지)',
        );

        await _insertWebImagesBatch(
          batch,
          documentEditor,
          analyzeAndUpdateDocument,
        );

        // 배치 간 간격
        if (batchIndex < batches.length - 1) {
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      // 🎯 모든 배치 완료 후 한 번만 analyzeAndUpdateDocument 수행
      analyzeAndUpdateDocument();
      print(
        '✅ 모든 웹 배치 처리 완료 후 SpatialManager 업데이트 수행 (총 ${xFiles.length}개 이미지)',
      );
    } catch (e) {
      print('❌ 웹 다중 이미지 삽입 실패: $e');
    }
  }

  // 웹 이미지 배치 처리
  Future<void> _insertWebImagesBatch(
    List<XFile> xFiles,
    Editor documentEditor,
    VoidCallback analyzeAndUpdateDocument,
  ) async {
    final tempNodeIds = <String>[];

    try {
      int insertIndex = documentEditor.document.nodeCount;

      for (final xFile in xFiles) {
        try {
          final tempNodeId = Editor.createNodeId();
          tempNodeIds.add(tempNodeId);

          final bytes = await xFile.readAsBytes();
          final fileName = xFile.name;
          final mime = _getMimeType(fileName);
          final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

          final placeholderNode = ImageNode(
            id: tempNodeId,
            imageUrl: dataUrl,
            metadata: {
              'isPlaceholder': true,
              'originalFileName': fileName,
              'isWebImage': true,
              'fileSize': bytes.length,
            },
          );

          documentEditor.execute([
            InsertNodeAtIndexRequest(
              nodeIndex: insertIndex++,
              newNode: placeholderNode,
            ),
          ]);

          print('✅ 웹 플레이스홀더 생성: $fileName (${bytes.length} bytes)');
        } catch (e) {
          print('❌ 웹 이미지 처리 실패: ${xFile.name} - $e');
        }
      }

      try {
        final uploadResults = await _uploadMultipleWebImages(xFiles);

        if (uploadResults.isNotEmpty) {
          print('✅ 웹 이미지 ${uploadResults.length}개 업로드 성공');

          // 성공한 이미지로 플레이스홀더 교체
          for (
            int i = 0;
            i < tempNodeIds.length && i < uploadResults.length;
            i++
          ) {
            final tempNodeId = tempNodeIds[i];
            final result = uploadResults[i];
            final xFile = xFiles[i];

            try {
              final realImageNode = ImageNode(
                id: tempNodeId,
                imageUrl: result['accessUrl'] ?? '',
                metadata: {
                  'isPlaceholder': false,
                  'isRealImage': true,
                  'isImageNode': true,
                  'imageId': result['imageId'],
                  'originalFileName': xFile.name,
                  'isWebImage': true,
                  'fileSize': result['fileSize'],
                  'uploadTime': result['uploadTime'],
                },
              );

              documentEditor.execute([
                ReplaceNodeRequest(
                  existingNodeId: tempNodeId,
                  newNode: realImageNode,
                ),
              ]);

              print('🔄 웹 플레이스홀더 → 실제 URL 이미지 교체 완료: ${xFile.name}');
            } catch (e) {
              try {
                documentEditor.execute([DeleteNodeRequest(nodeId: tempNodeId)]);
                print('🗑️ 실패한 웹 플레이스홀더 제거: $tempNodeId');
              } catch (deleteError) {
                print('❌ 웹 플레이스홀더 제거 실패: $tempNodeId - $deleteError');
              }
            }
          }

          print('📱 웹 이미지 SpatialManager 등록 완료');
        } else {
          print('❌ 웹 이미지 업로드 성공한 것이 없습니다');
        }
      } catch (e) {
        print('❌ 웹 이미지 배치 업로드 실패: $e');
      }
    } catch (e) {
      print('❌ 웹 이미지 배치 처리 실패: $e');
    }
  }

  // 다중 이미지 업로드 (File 기반)
  Future<List<Map<String, dynamic>>> _uploadMultipleImages(
    List<File> imageFiles,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/images/upload-multiple');
      final token = await AuthService().getToken();
      final request = http.MultipartRequest('POST', uri)
        ..fields['uid'] = 'user1234'; // 실제 사용자 UID로 변경 필요
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // 각 이미지 파일 추가
      for (final imageFile in imageFiles) {
        final bytes = await imageFile.readAsBytes();
        final fileName = imageFile.path.split('/').last;

        final mediaType = _createMediaType(fileName);

        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: fileName,
            contentType: mediaType,
          ),
        );

        print('   📎 파일 추가: $fileName (${bytes.length} bytes, $mediaType)');
      }

      // 타임아웃 설정 (5초)
      final response = await request.send().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('서버 응답 시간 초과', const Duration(seconds: 5));
        },
      );

      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        try {
          final result = json.decode(responseBody);
          print('✅ 다중 이미지 업로드 응답 파싱 성공:');
          print('   응답 데이터: $result');
          return List<Map<String, dynamic>>.from(result);
        } catch (parseError) {
          print('❌ 다중 이미지 JSON 파싱 실패: $parseError');
          print('   원본 응답: $responseBody');
          throw HttpException('서버 응답 파싱 실패: $parseError');
        }
      } else {
        print('❌ 다중 이미지 업로드 실패: ${response.statusCode} - $responseBody');

        String errorMessage = _getErrorMessageFromStatusCode(
          response.statusCode,
        );
        throw HttpException('$errorMessage (${response.statusCode})');
      }
    } on TimeoutException catch (e) {
      print('❌ 다중 이미지 업로드 타임아웃: $e');
      rethrow;
    } on SocketException catch (e) {
      print('❌ 네트워크 연결 오류: $e');
      throw HttpException('네트워크 연결을 확인해주세요');
    } catch (e) {
      print('❌ 다중 이미지 업로드 중 오류: $e');
      rethrow;
    }
  }

  // 파일이 실제 이미지인지 검증
  bool _isValidImageFile(Uint8List bytes) {
    if (bytes.length < 10) return false; // 너무 작은 파일

    // 이미지 파일 시그니처 확인
    final signatures = [
      [0xFF, 0xD8, 0xFF], // JPEG
      [0x89, 0x50, 0x4E, 0x47], // PNG
      [0x47, 0x49, 0x46], // GIF
      [0x52, 0x49, 0x46, 0x46], // WebP
      [0x42, 0x4D], // BMP
    ];

    for (final signature in signatures) {
      bool isValid = true;
      for (int i = 0; i < signature.length; i++) {
        if (bytes[i] != signature[i]) {
          isValid = false;
          break;
        }
      }
      if (isValid) return true;
    }

    return false;
  }

  // 다중 이미지 업로드 (XFile 기반 - 웹용)
  Future<List<Map<String, dynamic>>> _uploadMultipleWebImages(
    List<XFile> xFiles,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/images/upload-multiple');
      final token = await AuthService().getToken();
      final request = http.MultipartRequest('POST', uri)
        ..fields['uid'] = AuthProvider().username ?? '';
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // 각 이미지 파일 추가
      for (final xFile in xFiles) {
        final bytes = await xFile.readAsBytes();
        final fileName = xFile.name;
        final cleanFileName = _cleanFileName(fileName);

        // 파일이 실제 이미지인지 검증
        if (!_isValidImageFile(bytes)) {
          continue;
        }

        final mediaType = _createMediaType(fileName);

        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: cleanFileName,
            contentType: mediaType,
          ),
        );

        print(
          '   📎 웹 파일 추가: $fileName → $cleanFileName (${bytes.length} bytes, $mediaType)',
        );
      }

      // 유효한 이미지가 없으면 에러
      if (request.files.isEmpty) {
        throw Exception('업로드할 유효한 이미지 파일이 없습니다');
      }

      // 타임아웃 설정 (5초)
      final response = await request.send().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('서버 응답 시간 초과', const Duration(seconds: 5));
        },
      );

      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        try {
          final result = json.decode(responseBody);
          print('✅ 웹 다중 이미지 업로드 응답 파싱 성공:');
          print('   응답 데이터: $result');
          return List<Map<String, dynamic>>.from(result);
        } catch (parseError) {
          print('❌ 웹 다중 이미지 JSON 파싱 실패: $parseError');
          print('   원본 응답: $responseBody');
          throw HttpException('서버 응답 파싱 실패: $parseError');
        }
      } else {
        print('❌ 웹 다중 이미지 업로드 실패: ${response.statusCode} - $responseBody');

        String errorMessage = _getErrorMessageFromStatusCode(
          response.statusCode,
        );
        throw HttpException('$errorMessage (${response.statusCode})');
      }
    } on TimeoutException catch (e) {
      print('❌ 웹 다중 이미지 업로드 타임아웃: $e');
      rethrow;
    } on SocketException catch (e) {
      print('❌ 네트워크 연결 오류: $e');
      throw HttpException('네트워크 연결을 확인해주세요');
    } catch (e) {
      print('❌ 웹 다중 이미지 업로드 중 오류: $e');
      rethrow;
    }
  }

  // 업로드 후 성공한 이미지만 문서에 삽입
  Future<void> _uploadAndInsertImages(
    List<File> imageFiles,
    Editor documentEditor,
  ) async {
    final tempNodeIds = <String>[];

    try {
      // 1. 먼저 플레이스홀더 노드들을 문서에 삽입 (일관된 방법 사용)
      int insertIndex = documentEditor.document.nodeCount;

      for (final imageFile in imageFiles) {
        final tempNodeId = Editor.createNodeId();
        tempNodeIds.add(tempNodeId);

        final placeholderNode = ImageNode(
          id: tempNodeId,
          imageUrl: 'placeholder',
          metadata: {
            'isPlaceholder': true,
            'originalFileName': imageFile.path.split('/').last,
            'isLocalFile': true, // 🎯 로컬 파일임을 표시
            'localFilePath': imageFile.path, // 🎯 로컬 파일 경로 저장
            'skipAutoMovement': true, // 🎯 자동 이동 스킵 플래그
          },
        );

        // 🎯 플레이스홀더 삽입 (단일 execute로 묶기)
        documentEditor.execute([
          InsertNodeAtIndexRequest(
            nodeIndex: insertIndex++,
            newNode: placeholderNode,
          ),
        ]);
      }

      // 2. 백그라운드에서 업로드
      final uploadResults = await _uploadMultipleImages(imageFiles);

      if (uploadResults.isNotEmpty) {
        // 🎯 모든 문서 변경사항을 하나의 execute로 묶기
        final allRequests = <EditRequest>[];

        // 실제 이미지로 교체
        for (
          int i = 0;
          i < tempNodeIds.length && i < uploadResults.length;
          i++
        ) {
          final tempNodeId = tempNodeIds[i];
          final result = uploadResults[i];

          final imageNode = ImageNode(
            id: tempNodeId,
            imageUrl: result['accessUrl'] ?? '',
            metadata: {
              'imageId': result['imageId'],
              'pxW': result['fileSize'] != null ? 400.0 : null,
              'pxH': result['fileSize'] != null ? 300.0 : null,
              'isPlaceholder': false,
              'isRealImage': true,
              'isImageNode': true,
              'uploadTime': result['uploadTime'],
              'skipAutoMovement': true,
            },
          );

          allRequests.add(
            ReplaceNodeRequest(existingNodeId: tempNodeId, newNode: imageNode),
          );
        }

        // 빈 패러그래프 노드 추가 및 자동 포커스
        final emptyParagraph = ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(''),
        );

        allRequests.addAll([
          InsertNodeAtIndexRequest(
            nodeIndex: documentEditor.document.nodeCount,
            newNode: emptyParagraph,
          ),
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: emptyParagraph.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);

        documentEditor.execute(allRequests);
      } else {
        print('❌ 업로드 성공한 이미지가 없습니다');
        // 실패 시 플레이스홀더 제거 후 SpatialManager 동기화
        _removePlaceholders(tempNodeIds, documentEditor);
      }
    } catch (e) {
      print('❌ 이미지 업로드 및 삽입 실패: $e');
      // 에러 시 플레이스홀더 제거 후 SpatialManager 동기화
      if (tempNodeIds.isNotEmpty) {
        _removePlaceholders(tempNodeIds, documentEditor);
      }
    }
  }

  // 플레이스홀더 노드들 제거
  void _removePlaceholders(List<String> tempNodeIds, Editor documentEditor) {
    for (final tempNodeId in tempNodeIds) {
      try {
        documentEditor.execute([DeleteNodeRequest(nodeId: tempNodeId)]);
      } catch (e) {
        print('❌ 플레이스홀더 제거 실패: $tempNodeId - $e');
      }
    }
  }

  // HTTP 상태 코드별 에러 메시지
  String _getErrorMessageFromStatusCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return '잘못된 요청입니다';
      case 401:
        return '인증이 필요합니다';
      case 403:
        return '접근 권한이 없습니다';
      case 404:
        return '서버를 찾을 수 없습니다';
      case 413:
        return '파일 크기가 너무 큽니다';
      case 415:
        return '지원하지 않는 이미지 형식입니다';
      case 500:
        return '서버 내부 오류가 발생했습니다';
      case 502:
        return '서버가 일시적으로 사용할 수 없습니다';
      case 503:
        return '서비스가 일시적으로 사용할 수 없습니다';
      case 504:
        return '서버 응답 시간이 초과되었습니다';
      default:
        return '알 수 없는 오류가 발생했습니다';
    }
  }

  // MIME 타입 관련 헬퍼 메서드들
  String _getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  // MIME 타입을 MediaType으로 변환
  MediaType _createMediaType(String fileName) {
    final mime = _getMimeType(fileName);
    final mimeParts = mime.split('/');
    return MediaType(mimeParts[0], mimeParts[1]);
  }

  // 파일명 정리 (한글, 특수문자 제거)
  String _cleanFileName(String originalFileName) {
    final extension = originalFileName.split('.').last.toLowerCase();
    String nameWithoutExt = originalFileName.substring(
      0,
      originalFileName.lastIndexOf('.'),
    );

    nameWithoutExt = nameWithoutExt.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    nameWithoutExt = nameWithoutExt.replaceAll(RegExp(r'_+'), '_');
    nameWithoutExt = nameWithoutExt.replaceAll(RegExp(r'^_+|_+$'), '');

    if (nameWithoutExt.isEmpty) {
      nameWithoutExt = 'image';
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanFileName = '${nameWithoutExt}_$timestamp.$extension';

    print('🔧 파일명 정리: "$originalFileName" → "$cleanFileName"');
    return cleanFileName;
  }

  // 웹: 컴퓨터 폴더에서 다중 이미지 선택
  Future<void> pickImagesFromComputer(
    Editor documentEditor,
    MutableDocument document,
    VoidCallback analyzeAndUpdateDocument, {
    dynamic spatialManager,
    BuildContext? context, // 🎯 권한 에러 다이얼로그 표시용
  }) async {
    try {
      // 🎯 권한 체크 (웹에서는 생략)
      if (!kIsWeb) {
        try {
          final hasPermission = await _checkAndRequestPermissions();
          if (!hasPermission) {
            print('❌ 권한이 없습니다');
            if (context != null) {
              _showPermissionErrorDialog(context, _getPermissionErrorMessage());
            }
            return;
          }
        } catch (e) {
          print('❌ 권한 체크 중 오류: $e');
        }
      }

      final result = await ImagePicker()
          .pickMultiImage(maxWidth: 1920, maxHeight: 1080, imageQuality: 85)
          .catchError((error) {
            if (error.toString().contains('permission') ||
                error.toString().contains('권한') ||
                error.toString().contains('denied')) {
              return <XFile>[];
            }
            throw error;
          });

      if (result.isNotEmpty) {
        // 웹에서는 ImageService의 웹용 메서드 사용
        await insertMultipleWebImages(
          result,
          documentEditor,
          document,
          analyzeAndUpdateDocument,
        );
      }
    } catch (e) {
      _handleError(e, context);
    }
  }

  // 모바일 갤러리에서 선택된 이미지들 처리
  Future<void> processMobileGalleryImages(
    List<File> imageFiles,
    Editor documentEditor,
    MutableDocument document,
    VoidCallback analyzeAndUpdateDocument, {
    dynamic spatialManager,
    BuildContext? context, // 🎯 권한 에러 다이얼로그 표시용
  }) async {
    try {
      // 🎯 insertMultipleImages를 올바른 매개변수로 호출
      await insertMultipleImages(
        documentEditor,
        document,
        imageFiles,
        analyzeAndUpdateDocument,
      );
    } catch (e) {
      _handleError(e, context);
    }
  }
}
