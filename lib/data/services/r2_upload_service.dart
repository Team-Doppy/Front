import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/services/r2_aws_signature.dart';
import 'package:doppy/data/models/r2_config_model.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// R2 직접 업로드 서비스
class R2UploadService {
  static final R2UploadService _instance = R2UploadService._internal();
  factory R2UploadService() => _instance;
  R2UploadService._internal();

  final BaseApiService _baseApiService = BaseApiService();
  R2Config? _cachedConfig;
  DateTime? _configCacheTime;
  static const Duration _configCacheDuration = Duration(hours: 1);

  /// MIME 타입 가져오기
  String _getMimeType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
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
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }

  /// R2 설정 조회 (캐시 사용)
  Future<R2Config> getR2Config({bool forceRefresh = false}) async {
    // 캐시 확인
    if (!forceRefresh &&
        _cachedConfig != null &&
        _configCacheTime != null &&
        DateTime.now().difference(_configCacheTime!) < _configCacheDuration) {
      debugPrint('[R2UploadService] R2 설정 캐시 사용');
      return _cachedConfig!;
    }

    try {
      debugPrint('[R2UploadService] GET /api/r2/config');

      // 🎯 BaseApiService의 dio를 사용하여 자동 토큰 갱신 지원
      final response = await _baseApiService.dio.get('/api/r2/config');

      if (response.statusCode == 200) {
        final responseData = response.data as Map<String, dynamic>;
        final config = R2Config.fromJson(responseData);

        // 캐시 저장
        _cachedConfig = config;
        _configCacheTime = DateTime.now();

        debugPrint('[R2UploadService] ✅ R2 설정 조회 성공');
        return config;
      } else {
        throw Exception('R2 설정 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[R2UploadService] ❌ R2 설정 조회 실패: $e');
      rethrow;
    }
  }

  /// 업로드 키 생성
  Future<List<UploadKeyResponse>> generateUploadKeys(
    List<File> files, {
    String? pathPrefix, // 🎯 경로 prefix (예: 'chat/username')
  }) async {
    try {
      // 파일 정보 준비
      final fileInfos = await Future.wait(
        files.map(
          (file) async => FileInfo(
            fileName: file.path.split('/').last,
            mimeType: _getMimeType(file.path),
            fileSize: await file.length(),
          ),
        ),
      );

      debugPrint(
        '[R2UploadService] POST /api/r2/upload-keys files=${fileInfos.length} pathPrefix=$pathPrefix',
      );

      final requestBody = {
        'files': fileInfos.map((f) => f.toJson()).toList(),
        if (pathPrefix != null) 'pathPrefix': pathPrefix, // 🎯 경로 prefix 전달
      };

      debugPrint('[R2UploadService] Request body: ${jsonEncode(requestBody)}');

      // 🎯 BaseApiService의 dio를 사용하여 자동 토큰 갱신 지원
      final response = await _baseApiService.dio.post(
        '/api/r2/upload-keys',
        data: requestBody,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = response.data as List;
        debugPrint('[R2UploadService] Response body: $responseData');

        final uploadKeys =
            responseData
                .map(
                  (json) =>
                      UploadKeyResponse.fromJson(json as Map<String, dynamic>),
                )
                .toList();

        debugPrint('[R2UploadService] ✅ 업로드 키 생성 성공: ${uploadKeys.length}개');
        return uploadKeys;
      } else {
        throw Exception('업로드 키 생성 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[R2UploadService] ❌ 업로드 키 생성 실패: $e');
      rethrow;
    }
  }

  /// R2 직접 업로드 (단일 파일) - AWS Signature V4 사용
  Future<UploadResult> uploadFileToR2(
    File file,
    UploadKeyResponse uploadKey,
    Function(String fileName, double progress)? onProgress,
  ) async {
    try {
      final config = await getR2Config();
      final fileSize = await file.length();
      final mimeType = _getMimeType(file.path);

      debugPrint(
        '[R2UploadService] R2 업로드 시작: ${uploadKey.fileName} (${fileSize} bytes)',
      );

      if (onProgress != null) {
        onProgress(uploadKey.fileName, 0.0);
      }

      // 파일 읽기
      final fileBytes = await file.readAsBytes();

      // AWS Signature V4 생성 (R2는 S3 호환 API이므로 AWS Signature V4 사용)
      final headers = AwsSignatureV4.signRequest(
        method: 'PUT',
        endpoint: uploadKey.endpoint,
        bucket: uploadKey.bucket,
        key: uploadKey.r2Key,
        accessKeyId: config.accessKeyId,
        secretAccessKey: config.secretAccessKey,
        region: config.region,
        contentType: mimeType,
        contentLength: fileSize,
        bodyBytes: fileBytes,
      );

      // 업로드 URL 생성 (R2 path-style: endpoint/bucket/key)
      // endpoint 예: https://xxx.r2.cloudflarestorage.com
      // r2Key는 이미 "users/username/uuid.jpg" 형식이므로 슬래시 조정 필요
      final endpointUri = Uri.parse(uploadKey.endpoint);
      final r2KeyPath =
          uploadKey.r2Key.startsWith('/')
              ? uploadKey.r2Key
              : '/${uploadKey.r2Key}';
      final uploadUrl = Uri(
        scheme: endpointUri.scheme,
        host: endpointUri.host,
        path: '/${uploadKey.bucket}$r2KeyPath',
      );

      debugPrint('[R2UploadService] 업로드 URL: $uploadUrl');

      // 진행률 콜백을 위한 스트림 업로드는 복잡하므로,
      // 작은 파일은 직접 업로드하고 큰 파일은 청크 단위로 업로드
      final request =
          http.Request('PUT', uploadUrl)
            ..headers.addAll(headers)
            ..bodyBytes = fileBytes;

      if (onProgress != null) {
        onProgress(uploadKey.fileName, 0.5);
      }

      // R2에 직접 업로드
      debugPrint('[R2UploadService] PUT 요청 전송: $uploadUrl');
      debugPrint('[R2UploadService] Headers: ${headers.toString()}');

      final streamedResponse = await request.send();

      // 스트림 응답을 읽어서 진행률 업데이트
      final responseBytes = <int>[];
      await for (final chunk in streamedResponse.stream) {
        responseBytes.addAll(chunk);
        // 업로드는 이미 전송 완료되었으므로 90%로 설정
        if (onProgress != null) {
          onProgress(uploadKey.fileName, 0.9);
        }
      }

      final response = http.Response.bytes(
        responseBytes,
        streamedResponse.statusCode,
        headers: streamedResponse.headers,
      );

      if (onProgress != null) {
        onProgress(uploadKey.fileName, 1.0);
      }

      debugPrint(
        '[R2UploadService] R2 응답: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[R2UploadService] ✅ R2 업로드 완료: ${uploadKey.fileName}');
        return UploadResult(
          success: true,
          storageUrl: uploadKey.publicUrl,
          fileSize: fileSize,
          mimeType: mimeType,
          originalFileName: uploadKey.fileName,
        );
      } else {
        throw Exception('R2 업로드 실패: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[R2UploadService] ❌ R2 업로드 실패: ${uploadKey.fileName} - $e');
      return UploadResult(
        success: false,
        originalFileName: uploadKey.fileName,
        error: e.toString(),
      );
    }
  }

  /// R2 직접 업로드 (여러 파일, 병렬 처리)
  Future<List<UploadResult>> uploadFilesToR2(
    List<File> files,
    List<UploadKeyResponse> uploadKeys,
    Function(String fileName, double progress)? onProgress,
  ) async {
    if (files.length != uploadKeys.length) {
      throw Exception('파일 개수와 업로드 키 개수가 일치하지 않습니다');
    }

    // 병렬 업로드 (모든 파일을 동시에 처리)
    final results = await Future.wait(
      files.asMap().entries.map((entry) {
        final index = entry.key;
        final file = entry.value;
        final uploadKey = uploadKeys[index];
        return uploadFileToR2(file, uploadKey, onProgress);
      }),
      eagerError: false, // 일부 실패해도 나머지 결과 반환
    );

    return results;
  }

  /// 🎯 R2에서 파일 삭제 (이미지 URL 기반)
  Future<bool> deleteFileFromR2ByUrl(String imageUrl) async {
    try {
      final config = await getR2Config();

      // 🎯 이미지 URL에서 r2Key 추출
      // R2 public URL 형식: https://{publicUrl}/{r2Key}
      // 또는 storage URL 형식: https://{endpoint}/{bucket}/{r2Key}

      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;

      if (pathSegments.isEmpty) {
        debugPrint('[R2UploadService] ⚠️ 이미지 URL에서 r2Key를 추출할 수 없음: $imageUrl');
        return false;
      }

      // publicUrl을 사용하는 경우: publicUrl 이후가 r2Key
      String r2Key;
      if (imageUrl.startsWith(config.publicUrl)) {
        // publicUrl 이후의 경로가 r2Key
        final publicUri = Uri.parse(config.publicUrl);
        final imagePath = uri.path;
        final publicPath = publicUri.path;
        if (imagePath.startsWith(publicPath)) {
          r2Key = imagePath.substring(publicPath.length);
          if (r2Key.startsWith('/')) {
            r2Key = r2Key.substring(1);
          }
        } else {
          // 전체 경로를 r2Key로 사용
          r2Key = pathSegments.join('/');
        }
      } else {
        // endpoint를 사용하는 경우: bucket 이후가 r2Key
        // 첫 번째가 bucket, 나머지가 r2Key
        if (pathSegments.length < 2) {
          debugPrint(
            '[R2UploadService] ⚠️ 이미지 URL에서 r2Key를 추출할 수 없음: $imageUrl',
          );
          return false;
        }
        r2Key = pathSegments.sublist(1).join('/');
      }

      debugPrint('[R2UploadService] R2 파일 삭제 시작: r2Key=$r2Key');

      // AWS Signature V4 생성 (DELETE 메서드)
      final headers = AwsSignatureV4.signRequest(
        method: 'DELETE',
        endpoint: config.endpoint,
        bucket: config.bucket,
        key: r2Key,
        accessKeyId: config.accessKeyId,
        secretAccessKey: config.secretAccessKey,
        region: config.region,
        contentType: '',
        contentLength: 0,
        bodyBytes: null,
      );

      // 삭제 URL 생성
      final endpointUri = Uri.parse(config.endpoint);
      final r2KeyPath = r2Key.startsWith('/') ? r2Key : '/$r2Key';
      final deleteUrl = Uri(
        scheme: endpointUri.scheme,
        host: endpointUri.host,
        path: '/${config.bucket}$r2KeyPath',
      );

      debugPrint('[R2UploadService] 삭제 URL: $deleteUrl');

      // DELETE 요청 전송
      final request = http.Request('DELETE', deleteUrl)
        ..headers.addAll(headers);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint(
        '[R2UploadService] R2 삭제 응답: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[R2UploadService] ✅ R2 파일 삭제 완료: $r2Key');
        return true;
      } else {
        debugPrint(
          '[R2UploadService] ❌ R2 파일 삭제 실패: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[R2UploadService] ❌ R2 파일 삭제 예외: $imageUrl - $e');
      return false;
    }
  }

  /// R2에서 파일 삭제 (메타데이터 등록 실패 시 정리용)
  Future<bool> deleteFileFromR2(UploadKeyResponse uploadKey) async {
    try {
      final config = await getR2Config();

      debugPrint(
        '[R2UploadService] R2 파일 삭제 시작: ${uploadKey.fileName} (${uploadKey.r2Key})',
      );

      // AWS Signature V4 생성 (DELETE 메서드)
      final headers = AwsSignatureV4.signRequest(
        method: 'DELETE',
        endpoint: uploadKey.endpoint,
        bucket: uploadKey.bucket,
        key: uploadKey.r2Key,
        accessKeyId: config.accessKeyId,
        secretAccessKey: config.secretAccessKey,
        region: config.region,
        contentType: '',
        contentLength: 0,
        bodyBytes: null,
      );

      // 삭제 URL 생성 (PUT과 동일한 형식)
      final endpointUri = Uri.parse(uploadKey.endpoint);
      final r2KeyPath =
          uploadKey.r2Key.startsWith('/')
              ? uploadKey.r2Key
              : '/${uploadKey.r2Key}';
      final deleteUrl = Uri(
        scheme: endpointUri.scheme,
        host: endpointUri.host,
        path: '/${uploadKey.bucket}$r2KeyPath',
      );

      debugPrint('[R2UploadService] 삭제 URL: $deleteUrl');

      // DELETE 요청 전송
      final request = http.Request('DELETE', deleteUrl)
        ..headers.addAll(headers);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint(
        '[R2UploadService] R2 삭제 응답: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[R2UploadService] ✅ R2 파일 삭제 완료: ${uploadKey.fileName}');
        return true;
      } else {
        debugPrint(
          '[R2UploadService] ❌ R2 파일 삭제 실패: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[R2UploadService] ❌ R2 파일 삭제 예외: ${uploadKey.fileName} - $e');
      return false;
    }
  }

  /// 🎯 메타데이터 등록 (재시도 로직 포함, 비동기 실행)
  void _registerMetadataWithRetry(
    List<UploadResult> uploadResults,
    Completer<Map<String, dynamic>> completer,
    List<UploadKeyResponse> uploadKeys, // 🎯 업로드 키 (삭제용)
    Function(String message, double progress)? onProgress,
  ) async {
    int retryCount = 0;
    const maxRetries = 3;
    bool cleanupDone = false; // 🎯 중복 삭제 방지 플래그

    while (retryCount < maxRetries) {
      try {
        final result = await registerUploadedMedia(uploadResults);
        if (result['success'] == true) {
          debugPrint('[R2UploadService] ✅ 메타데이터 등록 성공 (시도: ${retryCount + 1})');
          if (!completer.isCompleted) {
            completer.complete(result);
          }
          return;
        } else {
          throw Exception(result['error'] ?? '메타데이터 등록 실패');
        }
      } catch (e) {
        retryCount++;

        if (retryCount >= maxRetries) {
          // 🎯 메타데이터 등록 완전 실패 시 R2에서 업로드된 파일 삭제 (한 번만)
          if (!cleanupDone) {
            cleanupDone = true;
            await _cleanupFailedUploads(uploadResults, uploadKeys);
          }

          if (!completer.isCompleted) {
            completer.completeError(
              Exception('메타데이터 등록 실패 (${maxRetries}회 재시도 실패): $e'),
            );
          }
          return;
        }

        // 재시도 전 대기 (지수 백오프)
        final delayMs = 1000 * (retryCount * retryCount); // 1초, 4초, 9초
        debugPrint('[R2UploadService] ${delayMs}ms 후 재시도...');
        await Future.delayed(Duration(milliseconds: delayMs));
        if (onProgress != null) {
          onProgress('메타데이터 등록 재시도 중... (${retryCount + 1}/$maxRetries)', 0.85);
        }
      }
    }
  }

  /// 🎯 메타데이터 등록 실패 시 R2에서 업로드된 파일 삭제
  Future<void> _cleanupFailedUploads(
    List<UploadResult> uploadResults,
    List<UploadKeyResponse> uploadKeys,
  ) async {
    try {
      // 성공한 업로드만 필터링 (R2에 실제로 업로드된 파일들)
      final successfulUploads =
          uploadResults
              .asMap()
              .entries
              .where((entry) => entry.value.success)
              .toList();

      if (successfulUploads.isEmpty) {
        debugPrint('[R2UploadService] 삭제할 파일이 없음');
        return;
      }

      debugPrint(
        '[R2UploadService] 🗑️ 메타데이터 등록 실패로 R2 파일 ${successfulUploads.length}개 삭제 시작',
      );

      // 병렬로 삭제 (빠른 정리)
      final deleteResults = await Future.wait(
        successfulUploads.map((entry) {
          final index = entry.key;
          final uploadKey = uploadKeys[index];
          return deleteFileFromR2(uploadKey);
        }),
        eagerError: false,
      );

      final successCount = deleteResults.where((r) => r == true).length;
      final failCount = deleteResults.length - successCount;

      debugPrint(
        '[R2UploadService] 🗑️ R2 파일 삭제 완료: 성공 ${successCount}개, 실패 ${failCount}개',
      );
    } catch (e) {
      debugPrint('[R2UploadService] ❌ R2 파일 삭제 중 오류: $e');
    }
  }

  /// 메타데이터 등록 (트랜잭션 보장)
  ///
  /// R2에 업로드된 파일들의 메타데이터를 서버에 등록합니다.
  /// 실패 시 재시도 로직이 호출 측에서 처리됩니다.
  Future<Map<String, dynamic>> registerUploadedMedia(
    List<UploadResult> uploadResults,
  ) async {
    try {
      // 성공한 업로드만 필터링
      final successfulUploads = uploadResults.where((r) => r.success).toList();

      if (successfulUploads.isEmpty) {
        debugPrint('[R2UploadService] ⚠️ 성공한 업로드가 없어 메타데이터 등록 건너뜀');
        return {'success': false, 'error': '성공한 업로드가 없습니다'};
      }

      debugPrint(
        '[R2UploadService] 메타데이터 등록 시작: ${successfulUploads.length}개 파일',
      );

      // 이미지와 동영상 분리
      final images = <MediaFile>[];
      final videos = <MediaFile>[];

      for (final result in successfulUploads) {
        final mediaFile = MediaFile(
          storageUrl: result.storageUrl!,
          fileSize: result.fileSize!,
          mimeType: result.mimeType!,
          originalFileName: result.originalFileName,
        );

        if (result.mimeType!.startsWith('image/')) {
          images.add(mediaFile);
        } else if (result.mimeType!.startsWith('video/')) {
          videos.add(mediaFile);
        }
      }

      final request = UploadedMediaRequest(
        images: images.isNotEmpty ? images : null,
        videos: videos.isNotEmpty ? videos : null,
      );

      debugPrint(
        '[R2UploadService] POST /api/r2/register-uploaded images=${images.length} videos=${videos.length}',
      );

      // 🎯 BaseApiService의 dio를 사용하여 자동 토큰 갱신 지원
      final response = await _baseApiService.dio.post(
        '/api/r2/register-uploaded',
        data: request.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = response.data as Map<String, dynamic>;
        debugPrint('[R2UploadService] Response body: $responseData');

        // 서버 응답에서 success 필드 확인
        final isSuccess = responseData['success'] == true;
        if (isSuccess) {
          debugPrint('[R2UploadService] ✅ 메타데이터 등록 성공');
          debugPrint(
            '[R2UploadService] 이미지 URL: ${responseData['imageUrls']?.length ?? 0}개',
          );
          debugPrint(
            '[R2UploadService] 비디오 URL: ${responseData['videoUrls']?.length ?? 0}개',
          );
        } else {
          final errorMsg = responseData['error'] ?? '알 수 없는 오류';
          debugPrint('[R2UploadService] ❌ 서버에서 메타데이터 등록 실패로 응답: $errorMsg');
          throw Exception('서버 오류: $errorMsg');
        }

        return responseData;
      } else {
        final errorBody = response.data?.toString() ?? '알 수 없는 오류';
        debugPrint(
          '[R2UploadService] ❌ 메타데이터 등록 HTTP 오류: ${response.statusCode}',
        );
        debugPrint('[R2UploadService] 응답 본문: $errorBody');
        throw Exception('메타데이터 등록 실패: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      debugPrint('[R2UploadService] ❌ 메타데이터 등록 예외 발생: $e');
      rethrow;
    }
  }

  /// 통합 업로드 함수 (전체 플로우)
  Future<UploadCompleteResult> uploadMediaFiles(
    List<File> files, {
    Function(String message, double progress)? onProgress,
    int maxRetries = 3,
    String? pathPrefix, // 🎯 경로 prefix (예: 'chat/username')
  }) async {
    try {
      if (files.isEmpty) {
        return UploadCompleteResult(
          success: false,
          error: '업로드할 파일이 없습니다',
          uploadedCount: 0,
          totalCount: 0,
        );
      }

      // 1. 업로드 키 생성 (10%)
      if (onProgress != null) {
        onProgress('업로드 키 생성 중...', 0.1);
      }

      List<UploadKeyResponse> uploadKeys;
      try {
        uploadKeys = await generateUploadKeys(files, pathPrefix: pathPrefix);
      } catch (e) {
        return UploadCompleteResult(
          success: false,
          error: '업로드 키 생성 실패: $e',
          uploadedCount: 0,
          totalCount: files.length,
          failedFiles: files.map((f) => f.path.split('/').last).toList(),
        );
      }

      // 2. R2 직접 업로드와 메타데이터 전송을 병렬로 처리
      if (onProgress != null) {
        onProgress('R2 업로드 중...', 0.3);
      }

      final metadataCompleter = Completer<Map<String, dynamic>>();

      // 🎯 R2 업로드를 시작하고, 업로드 완료 즉시 메타데이터 전송을 병렬로 시작
      List<UploadResult> uploadResults = [];
      try {
        uploadResults = await uploadFilesToR2(files, uploadKeys, (
          fileName,
          fileProgress,
        ) {
          if (onProgress != null) {
            // 전체 진행률 계산: 30% + (파일 진행률 * 50%)
            final totalProgress = 0.3 + (fileProgress * 0.5);
            onProgress('$fileName 업로드 중...', totalProgress);
          }
        });

        // 🎯 업로드 완료 즉시 메타데이터 전송 시작 (병렬로 실행, 기다리지 않음)
        _registerMetadataWithRetry(
          uploadResults,
          metadataCompleter,
          uploadKeys, // 🎯 업로드 키 전달 (삭제용)
          onProgress,
        );
      } catch (e) {
        // 🎯 R2 업로드 중 예외 발생 시 성공한 파일들 정리
        final successCount = uploadResults.where((r) => r.success).length;
        if (successCount > 0) {
          debugPrint(
            '[R2UploadService] ⚠️ R2 업로드 중 예외 발생 - 성공한 ${successCount}개 파일 정리 시작',
          );
          await _cleanupFailedUploads(uploadResults, uploadKeys);
        }
        return UploadCompleteResult(
          success: false,
          error: 'R2 업로드 실패: $e',
          uploadedCount: successCount,
          totalCount: files.length,
          failedFiles: files.map((f) => f.path.split('/').last).toList(),
        );
      }

      // 3. 메타데이터 등록 완료 대기 (업로드와 병렬로 실행되었음)
      if (onProgress != null) {
        onProgress('메타데이터 등록 중...', 0.85);
      }

      Map<String, dynamic>? registerResult;
      try {
        registerResult = await metadataCompleter.future;
        bool registerSuccess = registerResult['success'] == true;

        if (!registerSuccess) {
          final successCount = uploadResults.where((r) => r.success).length;
          debugPrint(
            '[R2UploadService] ⚠️ 메타데이터 등록 완전 실패 - R2에 ${successCount}개 파일이 업로드되었지만 메타데이터 미등록 상태',
          );

          // 🎯 메타데이터 등록 실패 시 R2에서 업로드된 파일 삭제
          // (_registerMetadataWithRetry에서 이미 삭제했을 수 있지만, 안전을 위해 재시도)
          await _cleanupFailedUploads(uploadResults, uploadKeys);

          return UploadCompleteResult(
            success: false,
            error: '메타데이터 등록 실패: ${registerResult['error'] ?? '알 수 없는 오류'}',
            uploadedCount: successCount,
            totalCount: files.length,
            failedFiles:
                uploadResults
                    .where((r) => !r.success)
                    .map((r) => r.originalFileName)
                    .toList(),
          );
        }
      } catch (e) {
        // 메타데이터 등록 실패 (재시도 모두 실패)
        final successCount = uploadResults.where((r) => r.success).length;
        debugPrint(
          '[R2UploadService] ⚠️ 메타데이터 등록 완전 실패 - R2에 ${successCount}개 파일이 업로드되었지만 메타데이터 미등록 상태',
        );

        // 🎯 메타데이터 등록 실패 시 R2에서 업로드된 파일 삭제
        // (_registerMetadataWithRetry에서 이미 삭제했을 수 있지만, 안전을 위해 재시도)
        await _cleanupFailedUploads(uploadResults, uploadKeys);

        return UploadCompleteResult(
          success: false,
          error: '메타데이터 등록 실패: $e',
          uploadedCount: successCount,
          totalCount: files.length,
          failedFiles:
              uploadResults
                  .where((r) => !r.success)
                  .map((r) => r.originalFileName)
                  .toList(),
        );
      }

      if (onProgress != null) {
        onProgress('업로드 완료', 1.0);
      }

      // 4. 트랜잭션 검증: R2 업로드 성공한 파일 수와 메타데이터 등록된 URL 수 일치 확인
      final successCount = uploadResults.where((r) => r.success).length;
      final imageUrls = List<String>.from(registerResult['imageUrls'] ?? []);
      final videoUrls = List<String>.from(registerResult['videoUrls'] ?? []);
      final totalRegistered = imageUrls.length + videoUrls.length;

      if (successCount != totalRegistered) {
        debugPrint(
          '[R2UploadService] ⚠️ 트랜잭션 불일치 감지: R2 업로드 성공 ${successCount}개, 메타데이터 등록 ${totalRegistered}개',
        );

        // 🎯 트랜잭션 불일치: 메타데이터가 등록되지 않은 파일들 찾아서 삭제
        final registeredUrls =
            <String>{}
              ..addAll(imageUrls)
              ..addAll(videoUrls);
        final unregisteredResults = <int>[];

        for (int i = 0; i < uploadResults.length; i++) {
          final result = uploadResults[i];
          if (result.success &&
              result.storageUrl != null &&
              !registeredUrls.contains(result.storageUrl)) {
            unregisteredResults.add(i);
          }
        }

        if (unregisteredResults.isNotEmpty) {
          debugPrint(
            '[R2UploadService] 🗑️ 메타데이터 미등록 파일 ${unregisteredResults.length}개 삭제 시작',
          );

          // 미등록된 파일들만 삭제
          final unregisteredKeys =
              unregisteredResults.map((idx) => uploadKeys[idx]).toList();
          final unregisteredUploadResults =
              unregisteredResults.map((idx) => uploadResults[idx]).toList();

          await _cleanupFailedUploads(
            unregisteredUploadResults,
            unregisteredKeys,
          );
        }

        debugPrint(
          '[R2UploadService] 일부만 성공: ${totalRegistered}개 등록 완료, ${successCount - totalRegistered}개 실패',
        );
      } else {
        debugPrint(
          '[R2UploadService] ✅ 트랜잭션 검증 통과: 업로드 ${successCount}개 = 메타데이터 등록 ${totalRegistered}개',
        );
      }

      final failedFiles =
          uploadResults
              .where((r) => !r.success)
              .map((r) => r.originalFileName)
              .toList();

      return UploadCompleteResult(
        success: true, // registerSuccess가 true이므로 항상 true
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        uploadedCount: successCount,
        totalCount: files.length,
        failedFiles: failedFiles,
      );
    } catch (e) {
      debugPrint('[R2UploadService] ❌ 통합 업로드 실패: $e');
      return UploadCompleteResult(
        success: false,
        error: e.toString(),
        uploadedCount: 0,
        totalCount: files.length,
        failedFiles: files.map((f) => f.path.split('/').last).toList(),
      );
    }
  }

  /// R2 설정 캐시 초기화
  void clearConfigCache() {
    _cachedConfig = null;
    _configCacheTime = null;
    debugPrint('[R2UploadService] R2 설정 캐시 초기화');
  }
}
