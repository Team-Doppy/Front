import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/upload_backend.dart';
import '../../core/upload_types.dart';
import '../../core/mime_types.dart';
import 'r2_config.dart';
import 'r2_upload_key.dart';
import 'r2_registered_item.dart';
import 'r2_aws_signature.dart';

/// Cloudflare R2 직접 업로드 백엔드
///
/// 플로우: 서버에서 키 발급 → R2 PUT → 서버 메타등록
///
/// ## 패키지처럼 초기화 (서버 API 경로 규약 따를 때)
///
/// [fromDio]에 Dio + baseUrl만 넘기면 됨. 서버에 아래 3개 API가 있으면 동작.
/// - GET  [baseUrl]/api/r2/config         → R2 설정
/// - POST [baseUrl]/api/r2/upload-keys    → 업로드 키 발급
/// - POST [baseUrl]/api/r2/register-uploaded → 메타데이터 등록
class R2UploadBackend implements UploadBackend {
  final Future<R2Config> Function() getR2Config;
  final Future<List<R2UploadKeyResponse>> Function(
    List<R2FileInfo> fileInfos, {
    String? pathPrefix,
  }) getUploadKeys;
  final Future<Map<String, dynamic>> Function(List<R2RegisteredItem> items)
      registerUploaded;

  R2Config? _cachedConfig;
  static const Duration _putTimeoutDefault = Duration(minutes: 1);
  static const Duration _putTimeoutVideo = Duration(minutes: 5);

  R2UploadBackend({
    required this.getR2Config,
    required this.getUploadKeys,
    required this.registerUploaded,
  });

  /// Dio + baseUrl만 넘기면 R2 사용. (서버 API 경로가 /api/r2/* 일 때)
  ///
  /// [dio]에 인증 헤더 등 이미 설정되어 있으면 그대로 사용됨.
  factory R2UploadBackend.fromDio({
    required Dio dio,
    String baseUrl = '',
    String configPath = '/api/r2/config',
    String uploadKeysPath = '/api/r2/upload-keys',
    String registerPath = '/api/r2/register-uploaded',
  }) {
    String url(String path) {
      if (baseUrl.isEmpty) return path;
      final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      return base + (path.startsWith('/') ? path.substring(1) : path);
    }

    return R2UploadBackend(
      getR2Config: () async {
        final res = await dio.get(url(configPath));
        return R2Config.fromJson(res.data as Map<String, dynamic>);
      },
      getUploadKeys: (List<R2FileInfo> fileInfos, {String? pathPrefix}) async {
        final res = await dio.post(
          url(uploadKeysPath),
          data: {
            'files': fileInfos.map((f) => f.toJson()).toList(),
            if (pathPrefix != null) 'pathPrefix': pathPrefix,
          },
        );
        final list = res.data as List;
        return list
            .map((e) =>
                R2UploadKeyResponse.fromJson(e as Map<String, dynamic>))
            .toList();
      },
      registerUploaded: (List<R2RegisteredItem> items) async {
        final images =
            items.where((i) => i.mimeType.startsWith('image/')).toList();
        final videos =
            items.where((i) => i.mimeType.startsWith('video/')).toList();
        final res = await dio.post(
          url(registerPath),
          data: {
            if (images.isNotEmpty) 'images': images.map((e) => e.toJson()).toList(),
            if (videos.isNotEmpty) 'videos': videos.map((e) => e.toJson()).toList(),
          },
        );
        return res.data as Map<String, dynamic>;
      },
    );
  }

  @override
  Future<void> initialize(Map<String, dynamic> settings) async {}

  @override
  Future<void> dispose() async {
    _cachedConfig = null;
  }

  Duration _putTimeout(String mimeType) {
    return mimeType.startsWith('video/') ? _putTimeoutVideo : _putTimeoutDefault;
  }

  Future<R2Config> _config() async {
    _cachedConfig ??= await getR2Config();
    return _cachedConfig!;
  }

  @override
  Future<UploadResult> uploadFile({
    required File file,
    String? fileName,
    String? pathPrefix,
    void Function(double progress)? onProgress,
    dynamic cancelToken,
  }) async {
    return retryOnConnectionFailure(
      action: () async {
        final name = fileName ?? file.path.split('/').last;
        final fileSize = await file.length();
        final mimeType = UploadMimeTypes.fromFileName(name);

        final config = await _config();
        final fileInfos = [
          R2FileInfo(fileName: name, mimeType: mimeType, fileSize: fileSize),
        ];
        final keys = await getUploadKeys(fileInfos, pathPrefix: pathPrefix);
        if (keys.isEmpty) throw Exception('R2 업로드 키를 받지 못했습니다.');
        final uploadKey = keys.first;

        onProgress?.call(0.2);

        final fileBytes = await file.readAsBytes();
        final headers = R2AwsSignatureV4.signRequest(
          method: 'PUT',
          endpoint: uploadKey.endpoint,
          bucket: uploadKey.bucket,
          key: uploadKey.r2Key,
          accessKeyId: config.accessKeyId,
          secretAccessKey: config.secretAccessKey,
          region: config.region,
          contentType: mimeType,
          contentLength: fileBytes.length,
          bodyBytes: Uint8List.fromList(fileBytes),
        );

        final endpointUri = Uri.parse(uploadKey.endpoint);
        final r2KeyPath =
            uploadKey.r2Key.startsWith('/') ? uploadKey.r2Key : '/${uploadKey.r2Key}';
        final uploadUrl = Uri(
          scheme: endpointUri.scheme,
          host: endpointUri.host,
          path: '/${uploadKey.bucket}$r2KeyPath',
        );

        onProgress?.call(0.5);

        final request = http.Request('PUT', uploadUrl)
          ..headers.addAll(headers)
          ..bodyBytes = fileBytes;

        final client = http.Client();
        try {
          final streamedResponse = await client.send(request).timeout(
                _putTimeout(mimeType),
                onTimeout: () {
                  client.close();
                  throw Exception('R2 PUT timeout');
                },
              );
          final body = await streamedResponse.stream.toBytes();
          final status = streamedResponse.statusCode;
          if (status != 200 && status != 204) {
            throw Exception('R2 업로드 실패: $status ${String.fromCharCodes(body)}');
          }
        } finally {
          client.close();
        }

        onProgress?.call(0.9);

        await registerUploaded([
          R2RegisteredItem(
            storageUrl: uploadKey.publicUrl,
            fileSize: fileSize,
            mimeType: mimeType,
            originalFileName: uploadKey.fileName,
          ),
        ]);

        onProgress?.call(1.0);
        if (kDebugMode) debugPrint('[R2UploadBackend] ✅ ${uploadKey.fileName}');

        return UploadResult(
          accessUrl: uploadKey.publicUrl,
          url: uploadKey.publicUrl,
          metadata: {
            'fileSize': fileSize,
            'mimeType': mimeType,
            'originalFileName': uploadKey.fileName,
          },
        );
      },
    );
  }

  @override
  Future<List<UploadResult>> uploadFiles({
    required List<File> files,
    String? pathPrefix,
    void Function(int current, int total, double progress)? onProgress,
    dynamic cancelToken,
  }) async {
    if (files.isEmpty) return [];

    final config = await _config();
    final fileInfos = await Future.wait(
      files.map((file) async {
        final name = file.path.split('/').last;
        return R2FileInfo(
          fileName: name,
          mimeType: UploadMimeTypes.fromFileName(name),
          fileSize: await file.length(),
        );
      }),
    );

    final keys = await getUploadKeys(fileInfos, pathPrefix: pathPrefix);
    if (keys.length != files.length) {
      throw Exception('업로드 키 개수 불일치: ${files.length} vs ${keys.length}');
    }

    final results = <UploadResult>[];
    final registeredItems = <R2RegisteredItem>[];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final uploadKey = keys[i];
      final mimeType = UploadMimeTypes.fromFileName(uploadKey.fileName);

      onProgress?.call(i, files.length, i / files.length);

      final fileBytes = await file.readAsBytes();
      final headers = R2AwsSignatureV4.signRequest(
        method: 'PUT',
        endpoint: uploadKey.endpoint,
        bucket: uploadKey.bucket,
        key: uploadKey.r2Key,
        accessKeyId: config.accessKeyId,
        secretAccessKey: config.secretAccessKey,
        region: config.region,
        contentType: mimeType,
        contentLength: fileBytes.length,
        bodyBytes: Uint8List.fromList(fileBytes),
      );

      final endpointUri = Uri.parse(uploadKey.endpoint);
      final r2KeyPath =
          uploadKey.r2Key.startsWith('/') ? uploadKey.r2Key : '/${uploadKey.r2Key}';
      final uploadUrl = Uri(
        scheme: endpointUri.scheme,
        host: endpointUri.host,
        path: '/${uploadKey.bucket}$r2KeyPath',
      );

      final request = http.Request('PUT', uploadUrl)
        ..headers.addAll(headers)
        ..bodyBytes = fileBytes;

      final client = http.Client();
      try {
        final streamedResponse = await client.send(request).timeout(
              _putTimeout(mimeType),
              onTimeout: () {
                client.close();
                throw Exception('R2 PUT timeout');
              },
            );
        final body = await streamedResponse.stream.toBytes();
        final status = streamedResponse.statusCode;
        if (status != 200 && status != 204) {
          throw Exception(
            'R2 업로드 실패: ${uploadKey.fileName} $status ${String.fromCharCodes(body)}',
          );
        }
      } finally {
        client.close();
      }

      final fileSize = fileBytes.length;
      results.add(UploadResult(
        accessUrl: uploadKey.publicUrl,
        url: uploadKey.publicUrl,
        metadata: {
          'fileSize': fileSize,
          'mimeType': mimeType,
          'originalFileName': uploadKey.fileName,
        },
      ));
      registeredItems.add(R2RegisteredItem(
        storageUrl: uploadKey.publicUrl,
        fileSize: fileSize,
        mimeType: mimeType,
        originalFileName: uploadKey.fileName,
      ));
    }

    onProgress?.call(files.length, files.length, 0.95);
    await registerUploaded(registeredItems);
    onProgress?.call(files.length, files.length, 1.0);

    if (kDebugMode) debugPrint('[R2UploadBackend] ✅ 배치 ${files.length}개');
    return results;
  }

  @override
  Future<UploadResult> uploadBytes({
    required List<int> bytes,
    required String fileName,
    String? pathPrefix,
    void Function(double progress)? onProgress,
    dynamic cancelToken,
  }) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      '${tempDir.path}/r2_upload_${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      await tempFile.writeAsBytes(bytes);
      return uploadFile(
        file: tempFile,
        fileName: fileName,
        pathPrefix: pathPrefix,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }
}
