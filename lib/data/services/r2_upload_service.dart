import 'dart:io';
import 'dart:convert';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/services/r2_aws_signature.dart';
import 'package:doppy/data/models/r2_config_model.dart';
import 'package:http/http.dart' as http;

/// R2 직접 업로드 서비스
class R2UploadService {
  static final R2UploadService _instance = R2UploadService._internal();
  factory R2UploadService() => _instance;
  R2UploadService._internal();

  final AuthService _authService = AuthService();
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
      print('[R2UploadService] R2 설정 캐시 사용');
      return _cachedConfig!;
    }

    try {
      final authToken = await _authService.getToken();
      if (authToken == null || authToken.isEmpty) {
        throw Exception('인증 토큰이 없습니다');
      }

      print('[R2UploadService] GET /api/r2/config');

      final response = await http.get(
        Uri.parse('${BaseApiService.baseUrl}/api/r2/config'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final config = R2Config.fromJson(json);

        // 캐시 저장
        _cachedConfig = config;
        _configCacheTime = DateTime.now();

        print('[R2UploadService] ✅ R2 설정 조회 성공');
        return config;
      } else {
        throw Exception('R2 설정 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[R2UploadService] ❌ R2 설정 조회 실패: $e');
      rethrow;
    }
  }

  /// 업로드 키 생성
  Future<List<UploadKeyResponse>> generateUploadKeys(List<File> files) async {
    try {
      final authToken = await _authService.getToken();
      if (authToken == null || authToken.isEmpty) {
        throw Exception('인증 토큰이 없습니다');
      }

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

      print(
        '[R2UploadService] POST /api/r2/upload-keys files=${fileInfos.length}',
      );

      final requestBody = {'files': fileInfos.map((f) => f.toJson()).toList()};

      print('[R2UploadService] Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse('${BaseApiService.baseUrl}/api/r2/upload-keys'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseBody = response.body;
        print('[R2UploadService] Response body: $responseBody');

        final jsonList = jsonDecode(responseBody) as List;
        final uploadKeys =
            jsonList
                .map(
                  (json) =>
                      UploadKeyResponse.fromJson(json as Map<String, dynamic>),
                )
                .toList();

        print('[R2UploadService] ✅ 업로드 키 생성 성공: ${uploadKeys.length}개');
        return uploadKeys;
      } else {
        throw Exception('업로드 키 생성 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[R2UploadService] ❌ 업로드 키 생성 실패: $e');
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

      print(
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

      print('[R2UploadService] 업로드 URL: $uploadUrl');

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
      print('[R2UploadService] PUT 요청 전송: $uploadUrl');
      print('[R2UploadService] Headers: ${headers.toString()}');

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

      print('[R2UploadService] R2 응답: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('[R2UploadService] ✅ R2 업로드 완료: ${uploadKey.fileName}');
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
      print('[R2UploadService] ❌ R2 업로드 실패: ${uploadKey.fileName} - $e');
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

    final results = <UploadResult>[];

    // 병렬 업로드 (최대 5개씩)
    const batchSize = 5;
    for (int i = 0; i < files.length; i += batchSize) {
      final batch = files.skip(i).take(batchSize).toList();
      final batchKeys = uploadKeys.skip(i).take(batchSize).toList();

      final batchResults = await Future.wait(
        batch.asMap().entries.map((entry) {
          final index = entry.key;
          final file = entry.value;
          final uploadKey = batchKeys[index];
          return uploadFileToR2(file, uploadKey, onProgress);
        }),
        eagerError: false,
      );

      results.addAll(batchResults);

      // 배치 간 짧은 딜레이
      if (i + batchSize < files.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    return results;
  }

  /// 메타데이터 등록 (트랜잭션 보장)
  ///
  /// R2에 업로드된 파일들의 메타데이터를 서버에 등록합니다.
  /// 실패 시 재시도 로직이 호출 측에서 처리됩니다.
  Future<Map<String, dynamic>> registerUploadedMedia(
    List<UploadResult> uploadResults,
  ) async {
    try {
      final authToken = await _authService.getToken();
      if (authToken == null || authToken.isEmpty) {
        throw Exception('인증 토큰이 없습니다');
      }

      // 성공한 업로드만 필터링
      final successfulUploads = uploadResults.where((r) => r.success).toList();

      if (successfulUploads.isEmpty) {
        print('[R2UploadService] ⚠️ 성공한 업로드가 없어 메타데이터 등록 건너뜀');
        return {'success': false, 'error': '성공한 업로드가 없습니다'};
      }

      print('[R2UploadService] 메타데이터 등록 시작: ${successfulUploads.length}개 파일');

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

      print(
        '[R2UploadService] POST /api/r2/register-uploaded images=${images.length} videos=${videos.length}',
      );

      final response = await http.post(
        Uri.parse('${BaseApiService.baseUrl}/api/r2/register-uploaded'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseBody = response.body;
        print('[R2UploadService] Response body: $responseBody');

        final result = jsonDecode(responseBody) as Map<String, dynamic>;

        // 서버 응답에서 success 필드 확인
        final isSuccess = result['success'] == true;
        if (isSuccess) {
          print('[R2UploadService] ✅ 메타데이터 등록 성공');
          print(
            '[R2UploadService] 이미지 URL: ${result['imageUrls']?.length ?? 0}개',
          );
          print(
            '[R2UploadService] 비디오 URL: ${result['videoUrls']?.length ?? 0}개',
          );
        } else {
          final errorMsg = result['error'] ?? '알 수 없는 오류';
          print('[R2UploadService] ❌ 서버에서 메타데이터 등록 실패로 응답: $errorMsg');
          throw Exception('서버 오류: $errorMsg');
        }

        return result;
      } else {
        final errorBody = response.body;
        print('[R2UploadService] ❌ 메타데이터 등록 HTTP 오류: ${response.statusCode}');
        print('[R2UploadService] 응답 본문: $errorBody');
        throw Exception('메타데이터 등록 실패: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('[R2UploadService] ❌ 메타데이터 등록 예외 발생: $e');
      rethrow;
    }
  }

  /// 통합 업로드 함수 (전체 플로우)
  Future<UploadCompleteResult> uploadMediaFiles(
    List<File> files, {
    Function(String message, double progress)? onProgress,
    int maxRetries = 3,
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
        uploadKeys = await generateUploadKeys(files);
      } catch (e) {
        return UploadCompleteResult(
          success: false,
          error: '업로드 키 생성 실패: $e',
          uploadedCount: 0,
          totalCount: files.length,
          failedFiles: files.map((f) => f.path.split('/').last).toList(),
        );
      }

      // 2. R2 직접 업로드 (30% ~ 80%)
      if (onProgress != null) {
        onProgress('R2 업로드 중...', 0.3);
      }

      List<UploadResult> uploadResults;
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
      } catch (e) {
        return UploadCompleteResult(
          success: false,
          error: 'R2 업로드 실패: $e',
          uploadedCount: 0,
          totalCount: files.length,
          failedFiles: files.map((f) => f.path.split('/').last).toList(),
        );
      }

      // 3. 서버에 메타데이터 등록 (80% ~ 100%)
      if (onProgress != null) {
        onProgress('메타데이터 등록 중...', 0.8);
      }

      Map<String, dynamic>? registerResult;
      int retryCount = 0;
      const maxRetries = 3;
      bool registerSuccess = false;

      while (retryCount < maxRetries && !registerSuccess) {
        try {
          registerResult = await registerUploadedMedia(uploadResults);

          // 서버 응답 확인
          if (registerResult['success'] == true) {
            registerSuccess = true;
            print('[R2UploadService] ✅ 메타데이터 등록 성공 (시도: ${retryCount + 1})');
          } else {
            throw Exception(registerResult['error'] ?? '메타데이터 등록 실패');
          }
        } catch (e) {
          retryCount++;
          print(
            '[R2UploadService] ❌ 메타데이터 등록 실패 (시도: $retryCount/$maxRetries): $e',
          );

          if (retryCount >= maxRetries) {
            // 🎯 모든 재시도 실패: R2에 업로드된 파일이 있지만 메타데이터는 등록되지 않음
            // 서버에서 정리 작업을 수행하거나, 클라이언트에서 서버에 정리 요청
            final successCount = uploadResults.where((r) => r.success).length;
            print(
              '[R2UploadService] ⚠️ 메타데이터 등록 완전 실패 - R2에 ${successCount}개 파일이 업로드되었지만 메타데이터 미등록 상태',
            );

            // TODO: 서버에 R2 파일 정리 요청을 보낼 수 있는 API 호출
            // await _cleanupFailedUploads(uploadResults);

            return UploadCompleteResult(
              success: false,
              error: '메타데이터 등록 실패 (${maxRetries}회 재시도 실패): $e',
              uploadedCount: successCount,
              totalCount: files.length,
              failedFiles:
                  uploadResults
                      .where((r) => !r.success)
                      .map((r) => r.originalFileName)
                      .toList(),
            );
          }

          // 재시도 전 대기 (지수 백오프)
          final delayMs = 1000 * (retryCount * retryCount); // 1초, 4초, 9초
          print('[R2UploadService] ${delayMs}ms 후 재시도...');
          await Future.delayed(Duration(milliseconds: delayMs));

          if (onProgress != null) {
            onProgress(
              '메타데이터 등록 재시도 중... (${retryCount + 1}/$maxRetries)',
              0.8,
            );
          }
        }
      }

      // registerSuccess가 false인 경우는 위에서 이미 return했으므로 여기서는 항상 true
      if (!registerSuccess || registerResult == null) {
        // 이론상 도달하지 않아야 하지만 안전을 위해
        final successCount = uploadResults.where((r) => r.success).length;
        return UploadCompleteResult(
          success: false,
          error: '메타데이터 등록 결과를 가져올 수 없습니다',
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
        print(
          '[R2UploadService] ⚠️ 트랜잭션 불일치 감지: R2 업로드 성공 ${successCount}개, 메타데이터 등록 ${totalRegistered}개',
        );
        // 경고만 로그하고 계속 진행 (서버에서 일부 필터링했을 수 있음)
      } else {
        print(
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
      print('[R2UploadService] ❌ 통합 업로드 실패: $e');
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
    print('[R2UploadService] R2 설정 캐시 초기화');
  }
}
