/// R2 설정 모델
class R2Config {
  final String endpoint;
  final String bucket;
  final String publicUrl;
  final String region;
  final String accessKeyId;
  final String secretAccessKey;

  R2Config({
    required this.endpoint,
    required this.bucket,
    required this.publicUrl,
    required this.region,
    required this.accessKeyId,
    required this.secretAccessKey,
  });

  factory R2Config.fromJson(Map<String, dynamic> json) {
    return R2Config(
      endpoint: json['endpoint'] as String,
      bucket: json['bucket'] as String,
      publicUrl: json['publicUrl'] as String,
      region: json['region'] as String,
      accessKeyId: json['accessKeyId'] as String,
      secretAccessKey: json['secretAccessKey'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'endpoint': endpoint,
      'bucket': bucket,
      'publicUrl': publicUrl,
      'region': region,
      'accessKeyId': accessKeyId,
      'secretAccessKey': secretAccessKey,
    };
  }
}

/// 파일 정보 모델 (업로드 키 생성용)
class FileInfo {
  final String fileName;
  final String mimeType;
  final int fileSize;

  FileInfo({
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() {
    return {'fileName': fileName, 'mimeType': mimeType, 'fileSize': fileSize};
  }
}

/// 업로드 키 응답 모델
class UploadKeyResponse {
  final String r2Key;
  final String publicUrl;
  final String fileName;
  final String bucket;
  final String endpoint;
  final String region;

  UploadKeyResponse({
    required this.r2Key,
    required this.publicUrl,
    required this.fileName,
    required this.bucket,
    required this.endpoint,
    required this.region,
  });

  factory UploadKeyResponse.fromJson(Map<String, dynamic> json) {
    return UploadKeyResponse(
      r2Key: json['r2Key'] as String,
      publicUrl: json['publicUrl'] as String,
      fileName: json['fileName'] as String,
      bucket: json['bucket'] as String,
      endpoint: json['endpoint'] as String,
      region: json['region'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'r2Key': r2Key,
      'publicUrl': publicUrl,
      'fileName': fileName,
      'bucket': bucket,
      'endpoint': endpoint,
      'region': region,
    };
  }
}

/// 미디어 파일 모델 (메타데이터 등록용)
class MediaFile {
  final String storageUrl;
  final int fileSize;
  final String mimeType;
  final String originalFileName;

  MediaFile({
    required this.storageUrl,
    required this.fileSize,
    required this.mimeType,
    required this.originalFileName,
  });

  Map<String, dynamic> toJson() {
    return {
      'storageUrl': storageUrl,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'originalFileName': originalFileName,
    };
  }
}

/// 업로드된 미디어 요청 모델
class UploadedMediaRequest {
  final List<MediaFile>? images;
  final List<MediaFile>? videos;

  UploadedMediaRequest({this.images, this.videos});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    if (images != null && images!.isNotEmpty) {
      json['images'] = images!.map((img) => img.toJson()).toList();
    }
    if (videos != null && videos!.isNotEmpty) {
      json['videos'] = videos!.map((vid) => vid.toJson()).toList();
    }
    return json;
  }
}

/// 업로드 결과 모델
class UploadResult {
  final bool success;
  final String? storageUrl;
  final int? fileSize;
  final String? mimeType;
  final String originalFileName;
  final String? error;

  UploadResult({
    required this.success,
    this.storageUrl,
    this.fileSize,
    this.mimeType,
    required this.originalFileName,
    this.error,
  });
}

/// 업로드 완료 결과 모델
class UploadCompleteResult {
  final bool success;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final int uploadedCount;
  final int totalCount;
  final List<String> failedFiles;
  final String? error;

  UploadCompleteResult({
    required this.success,
    this.imageUrls = const [],
    this.videoUrls = const [],
    required this.uploadedCount,
    required this.totalCount,
    this.failedFiles = const [],
    this.error,
  });
}
