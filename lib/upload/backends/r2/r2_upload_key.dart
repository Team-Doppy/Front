/// 업로드 키 요청 시 서버에 보낼 파일 정보 (POST /api/r2/upload-keys body.files[])
class R2FileInfo {
  final String fileName;
  final String mimeType;
  final int fileSize;

  const R2FileInfo({
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'mimeType': mimeType,
        'fileSize': fileSize,
      };
}

/// 서버에서 발급한 R2 업로드 키 (POST /api/r2/upload-keys 응답 항목)
class R2UploadKeyResponse {
  final String endpoint;
  final String bucket;
  final String r2Key;
  final String publicUrl;
  final String fileName;

  const R2UploadKeyResponse({
    required this.endpoint,
    required this.bucket,
    required this.r2Key,
    required this.publicUrl,
    required this.fileName,
  });

  factory R2UploadKeyResponse.fromJson(Map<String, dynamic> json) {
    return R2UploadKeyResponse(
      endpoint: json['endpoint'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      r2Key: json['r2Key'] as String? ?? json['key'] as String? ?? '',
      publicUrl:
          json['publicUrl'] as String? ?? json['storageUrl'] as String? ?? '',
      fileName:
          json['fileName'] as String? ?? json['originalFileName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'bucket': bucket,
        'r2Key': r2Key,
        'publicUrl': publicUrl,
        'fileName': fileName,
      };
}
