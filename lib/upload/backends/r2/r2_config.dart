/// Cloudflare R2 설정 (서버 /api/r2/config 응답 또는 직접 설정)
class R2Config {
  final String endpoint;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final String region;
  final String publicUrl;

  const R2Config({
    required this.endpoint,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.region,
    required this.publicUrl,
  });

  factory R2Config.fromJson(Map<String, dynamic> json) {
    return R2Config(
      endpoint: json['endpoint'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      accessKeyId: json['accessKeyId'] as String? ?? '',
      secretAccessKey: json['secretAccessKey'] as String? ?? '',
      region: json['region'] as String? ?? 'auto',
      publicUrl: json['publicUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'bucket': bucket,
        'accessKeyId': accessKeyId,
        'secretAccessKey': secretAccessKey,
        'region': region,
        'publicUrl': publicUrl,
      };
}
