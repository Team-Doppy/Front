import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/data/services/auth_service.dart';

class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  // API 기본 설정
  static String _baseUrl = ApiServiceBase.baseUrl; // 테스트용 로컬 서버

  // 다중 이미지 삽입 (갤러리에서 선택된 여러 이미지)
  Future<void> insertMultipleImages(
    Editor documentEditor,
    MutableDocument document,
    List<File> imageFiles,
    VoidCallback analyzeAndUpdateDocument, {
    dynamic spatialManager, // SpatialManager 참조 (선택적)
  }) async {
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

        await _uploadAndInsertImages(
          batch,
          documentEditor,
          analyzeAndUpdateDocument,
          spatialManager: spatialManager,
        );

        // 배치 간 간격 (서버 부하 방지)
        if (batchIndex < batches.length - 1) {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }

      print('✅ 모든 배치 처리 완료 (총 ${imageFiles.length}개 이미지)');
    } catch (e) {
      print('❌ 다중 이미지 삽입 실패: $e');
    }
  }

  // 웹용 다중 이미지 삽입 (XFile 기반)
  Future<void> insertMultipleWebImages(
    List<XFile> xFiles,
    Editor documentEditor,
    MutableDocument document,
    VoidCallback analyzeAndUpdateDocument, {
    dynamic spatialManager, // SpatialManager 참조 (선택적)
  }) async {
    try {
      if (xFiles.isEmpty) return;

      print('🌐 웹 이미지 처리 시작: ${xFiles.length}개');

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
          spatialManager: spatialManager,
        );

        // 배치 간 간격
        if (batchIndex < batches.length - 1) {
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      print('✅ 모든 웹 배치 처리 완료 (총 ${xFiles.length}개 이미지)');
    } catch (e) {
      print('❌ 웹 다중 이미지 삽입 실패: $e');
    }
  }

  // 웹 이미지 배치 처리
  Future<void> _insertWebImagesBatch(
    List<XFile> xFiles,
    Editor documentEditor,
    VoidCallback analyzeAndUpdateDocument, {
    dynamic spatialManager,
  }) async {
    final tempNodeIds = <String>[];

    try {
      // 1. 플레이스홀더 노드들을 문서에 삽입
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

      // 🔑 웹에서도 배치 업로드 후 실제 이미지로 교체
      try {
        // 배치로 한 번에 업로드
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
              print('❌ 웹 이미지 교체 실패: ${xFile.name} - $e');
              // 교체 실패 시 플레이스홀더 제거
              try {
                documentEditor.execute([DeleteNodeRequest(nodeId: tempNodeId)]);
                print('🗑️ 실패한 웹 플레이스홀더 제거: $tempNodeId');
              } catch (deleteError) {
                print('❌ 웹 플레이스홀더 제거 실패: $tempNodeId - $deleteError');
              }
            }
          }

          // 모든 이미지 교체 후 SpatialManager에 등록
          analyzeAndUpdateDocument();
          print('📱 웹 이미지 SpatialManager 등록 완료');
        } else {
          print('❌ 웹 이미지 업로드 성공한 것이 없습니다');
          // 업로드 실패 시 모든 플레이스홀더 제거
          _removePlaceholders(
            tempNodeIds,
            documentEditor,
            analyzeAndUpdateDocument,
          );
        }
      } catch (e) {
        print('❌ 웹 이미지 배치 업로드 실패: $e');
        print('🔄 개별 업로드로 fallback 시도...');

        // 배치 업로드 실패 시 개별 업로드로 fallback
        await _fallbackToIndividualUploads(
          xFiles,
          tempNodeIds,
          documentEditor,
          analyzeAndUpdateDocument,
        );
      }
    } catch (e) {
      print('❌ 웹 이미지 배치 처리 실패: $e');
      // 에러 시 플레이스홀더 제거
      if (tempNodeIds.isNotEmpty) {
        _removePlaceholders(
          tempNodeIds,
          documentEditor,
          analyzeAndUpdateDocument,
        );
      }
    }
  }

  // placeholder 노드 제거
  void _removePlaceholderNode(
    String nodeId,
    Editor documentEditor,
    VoidCallback analyzeAndUpdateDocument,
  ) {
    try {
      documentEditor.execute([DeleteNodeRequest(nodeId: nodeId)]);
      analyzeAndUpdateDocument();
    } catch (e) {
      print('❌ placeholder 노드 제거 실패: $e');
    }
  }

  // 단일 이미지 업로드
  Future<Map<String, dynamic>?> _uploadSingleImage(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/images/upload');

      final mediaType = _createMediaType(fileName);
      final token = await AuthService().getToken();

      final request =
          http.MultipartRequest('POST', uri)
            ..fields['uid'] =
                'user1234' // 실제 사용자 UID로 변경 필요
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: fileName,
                contentType: mediaType,
              ),
            );
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // 요청 전송 전 로깅
      print('📤 이미지 업로드 요청 전송:');
      print('   URL: $uri');
      print('   파일명: $fileName');
      print('   파일 크기: ${bytes.length} bytes');
      print('   MIME 타입: $mediaType');
      print('   사용자 ID: user1234');

      // 타임아웃 설정 (5초)
      final response = await request.send().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('서버 응답 시간 초과', const Duration(seconds: 5));
        },
      );

      final responseBody = await response.stream.bytesToString();

      // 서버 응답 상세 로깅
      print('📡 서버 응답 수신:');
      print('   상태 코드: ${response.statusCode}');
      print('   응답 헤더: ${response.headers}');
      print('   응답 본문: $responseBody');

      if (response.statusCode == 200) {
        try {
          final result = json.decode(responseBody);
          print('✅ 서버 응답 파싱 성공:');
          print('   응답 데이터: $result');
          return result;
        } catch (parseError) {
          print('❌ JSON 파싱 실패: $parseError');
          print('   원본 응답: $responseBody');
          throw HttpException('서버 응답 파싱 실패: $parseError');
        }
      } else {
        print('❌ 이미지 업로드 실패: ${response.statusCode} - $responseBody');

        // HTTP 상태 코드별 구체적인 에러 메시지
        String errorMessage = _getErrorMessageFromStatusCode(
          response.statusCode,
        );
        throw HttpException('$errorMessage (${response.statusCode})');
      }
    } on TimeoutException catch (e) {
      print('❌ 이미지 업로드 타임아웃: $e');
      rethrow;
    } on SocketException catch (e) {
      print('❌ 네트워크 연결 오류: $e');
      throw HttpException('네트워크 연결을 확인해주세요');
    } catch (e) {
      print('❌ 이미지 업로드 중 오류: $e');
      rethrow;
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

      // 서버 응답 상세 로깅
      print('📡 웹 다중 이미지 업로드 서버 응답 수신:');
      print('   상태 코드: ${response.statusCode}');
      print('   응답 헤더: ${response.headers}');
      print('   응답 본문: $responseBody');

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
    VoidCallback analyzeAndUpdateDocument, {
    dynamic spatialManager, // SpatialManager 참조 (선택적)
  }) async {
    final tempNodeIds = <String>[];

    try {
      // 1. 먼저 플레이스홀더 노드들을 문서에 삽입
      int insertIndex = documentEditor.document.nodeCount;

      for (final imageFile in imageFiles) {
        final tempNodeId = Editor.createNodeId();
        tempNodeIds.add(tempNodeId);

        // 임시 data URL 생성
        final bytes = await imageFile.readAsBytes();
        final mime = _mimeFromFile(imageFile);
        final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

        final placeholderNode = ImageNode(
          id: tempNodeId,
          imageUrl: dataUrl,
          metadata: {
            'isPlaceholder': true,
            'originalFileName': imageFile.path.split('/').last,
          },
        );

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
        print('✅ ${uploadResults.length}개 이미지 업로드 성공');

        // 3. 성공한 이미지로 플레이스홀더 교체
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
              'isImageNode': true, // 🔑 SpatialManager에서 이미지 노드로 인식
              'uploadTime': result['uploadTime'],
            },
          );

          documentEditor.execute([
            ReplaceNodeRequest(existingNodeId: tempNodeId, newNode: imageNode),
          ]);

          print('🔄 플레이스홀더 → 실제 이미지 교체 완료: ${result['imageId']}');
        }

        // 4. 마지막에 빈 패러그래프 노드 추가 및 자동 포커스

        final emptyParagraph = ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(''),
        );

        documentEditor.execute([
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
        print('빈 패러그래프 노드 추가 및 자동 포커스 완료');

        // 5. 남아있는 플레이스홀더 노드 제거
        final doc = documentEditor.document;
        final placeholderIds = <String>[];
        for (int i = 0; i < doc.nodeCount; i++) {
          final node = doc.getNodeAt(i);
          if (node is ImageNode && (node.metadata['isPlaceholder'] == true)) {
            placeholderIds.add(node.id);
          }
        }
        for (final id in placeholderIds) {
          documentEditor.execute([DeleteNodeRequest(nodeId: id)]);
          print('남은 플레이스홀더 제거: $id');
        }

        // 실제 이미지로 교체된 후에만 SpatialManager에 등록
        analyzeAndUpdateDocument();
      } else {
        print('❌ 업로드 성공한 이미지가 없습니다');
        // 실패 시 플레이스홀더 제거 후 SpatialManager 동기화
        _removePlaceholders(
          tempNodeIds,
          documentEditor,
          analyzeAndUpdateDocument,
        );
      }
    } catch (e) {
      print('❌ 이미지 업로드 및 삽입 실패: $e');
      // 에러 시 플레이스홀더 제거 후 SpatialManager 동기화
      if (tempNodeIds.isNotEmpty) {
        _removePlaceholders(
          tempNodeIds,
          documentEditor,
          analyzeAndUpdateDocument,
        );
      }
    }
  }

  // 플레이스홀더 노드들 제거
  void _removePlaceholders(
    List<String> tempNodeIds,
    Editor documentEditor,
    VoidCallback analyzeAndUpdateDocument,
  ) {
    for (final tempNodeId in tempNodeIds) {
      try {
        documentEditor.execute([DeleteNodeRequest(nodeId: tempNodeId)]);
        print('🗑️ 플레이스홀더 제거: $tempNodeId');
      } catch (e) {
        print('❌ 플레이스홀더 제거 실패: $tempNodeId - $e');
      }
    }
    analyzeAndUpdateDocument();
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

  // 파일에서 MIME 타입 추출 (File 기반)
  String _mimeFromFile(File file) {
    final ext = file.path.split('.').last.toLowerCase();
    return _getMimeType('dummy.$ext');
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
  }) async {
    try {
      final result = await ImagePicker().pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (result.isNotEmpty) {
        // 웹에서는 ImageService의 웹용 메서드 사용
        await insertMultipleWebImages(
          result,
          documentEditor,
          document,
          analyzeAndUpdateDocument,
          spatialManager: spatialManager,
        );
      }
    } catch (e) {
      print('❌ 웹 이미지 선택 실패: $e');
      rethrow;
    }
  }

  // 모바일: 갤러리에서 다중 이미지 선택
  Future<void> showMobileGallery(
    Editor documentEditor,
    MutableDocument document,
    VoidCallback analyzeAndUpdateDocument, {
    dynamic spatialManager,
  }) async {
    try {
      // 모바일에서는 갤러리 바텀시트를 통해 이미지 선택
      // 이 메서드는 갤러리에서 선택된 이미지들을 처리
      print('📱 모바일 갤러리 이미지 처리 준비 완료');
    } catch (e) {
      print('❌ 모바일 갤러리 처리 실패: $e');
      rethrow;
    }
  }

  // 모바일 갤러리에서 선택된 이미지들 처리
  Future<void> processMobileGalleryImages(
    List<File> imageFiles,
    Editor documentEditor,
    MutableDocument document,
    VoidCallback analyzeAndUpdateDocument, {
    dynamic spatialManager,
  }) async {
    try {
      await insertMultipleImages(
        documentEditor,
        document,
        imageFiles,
        analyzeAndUpdateDocument,
        spatialManager: spatialManager,
      );
    } catch (e) {
      print('❌ 모바일 갤러리 이미지 처리 실패: $e');
      rethrow;
    }
  }

  // 배치 업로드 실패 시 개별 업로드로 fallback
  Future<void> _fallbackToIndividualUploads(
    List<XFile> xFiles,
    List<String> tempNodeIds,
    Editor documentEditor,
    VoidCallback analyzeAndUpdateDocument,
  ) async {
    print('🔄 개별 업로드 fallback 시작: ${xFiles.length}개 이미지');

    int successCount = 0;

    for (int i = 0; i < xFiles.length; i++) {
      final xFile = xFiles[i];
      final tempNodeId = tempNodeIds[i];

      try {
        final bytes = await xFile.readAsBytes();
        final fileName = xFile.name;
        final cleanFileName = _cleanFileName(fileName);

        print('📤 개별 업로드 시도: $fileName');
        print(
          '📊 파일 정보: ${bytes.length} bytes, MIME: ${_getMimeType(fileName)}',
        );

        // 파일이 실제 이미지인지 검증
        if (!_isValidImageFile(bytes)) {
          print('❌ 유효하지 않은 이미지 파일: $fileName');
          documentEditor.execute([DeleteNodeRequest(nodeId: tempNodeId)]);
          continue;
        }

        // 개별 업로드 시도
        final uploadResult = await _uploadSingleImage(bytes, cleanFileName);

        if (uploadResult != null) {
          // 업로드 성공: 실제 URL로 교체
          final realImageNode = ImageNode(
            id: tempNodeId,
            imageUrl: uploadResult['accessUrl'] ?? '',
            metadata: {
              'isPlaceholder': false,
              'isRealImage': true,
              'isImageNode': true,
              'imageId': uploadResult['imageId'],
              'originalFileName': fileName,
              'isWebImage': true,
              'fileSize': bytes.length,
              'uploadTime': uploadResult['uploadTime'],
            },
          );

          documentEditor.execute([
            ReplaceNodeRequest(
              existingNodeId: tempNodeId,
              newNode: realImageNode,
            ),
          ]);

          print('✅ 개별 업로드 성공: $fileName');
          successCount++;
        } else {
          // 개별 업로드도 실패: 플레이스홀더 제거
          documentEditor.execute([DeleteNodeRequest(nodeId: tempNodeId)]);
          print('❌ 개별 업로드 실패, 플레이스홀더 제거: $fileName');
        }
      } catch (e) {
        print('❌ 개별 업로드 중 오류: ${xFile.name} - $e');
        // 오류 발생 시 플레이스홀더 제거
        try {
          documentEditor.execute([DeleteNodeRequest(nodeId: tempNodeId)]);
          print('🗑️ 오류로 인한 플레이스홀더 제거: $tempNodeId');
        } catch (deleteError) {
          print('❌ 플레이스홀더 제거 실패: $tempNodeId - $deleteError');
        }
      }
    }

    // 개별 업로드 완료 후 SpatialManager 동기화
    if (successCount > 0) {
      analyzeAndUpdateDocument();
      print('📱 개별 업로드 fallback 완료: $successCount개 성공');
    } else {
      print('❌ 개별 업로드 fallback도 모두 실패');
    }
  }
}

/// 이미지 노드 삽입 (기존 호환성 유지)
Future<void> insertImageNode({
  required Editor documentEditor,
  required MutableDocument document,
  required File imageFile,
}) async {
  try {
    final bytes = await imageFile.readAsBytes();

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;

    final imageNode = ImageNode(
      id: Editor.createNodeId(),
      imageUrl: 'placeholder',
      metadata: {
        'isImageNode': true,
        'pxW': width,
        'pxH': height,
        'scale': 1.0,
        'text': '이미지',
      },
    );

    documentEditor.execute([
      InsertNodeAtIndexRequest(
        nodeIndex: document.nodeCount,
        newNode: imageNode,
      ),
    ]);

    print('✅ 이미지 노드 삽입 완료: ${width}x${height}');
  } catch (e) {
    print('❌ 이미지 노드 삽입 실패: $e');
    rethrow;
  }
}
