import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// AWS Signature V4 헬퍼 (Cloudflare R2 업로드용)
///
/// Cloudflare R2는 Amazon S3와 호환되는 API를 제공하므로,
/// S3 업로드에 사용하는 AWS Signature V4 인증 방식을 그대로 사용합니다.
/// 이 클래스는 R2 업로드를 위한 서명을 생성합니다.
class AwsSignatureV4 {
  /// AWS Signature V4 서명 생성 (Cloudflare R2 업로드용)
  ///
  /// Cloudflare R2는 S3 호환 API를 사용하므로 AWS Signature V4 방식을 사용합니다.
  /// 이 메서드는 R2에 직접 업로드하기 위한 인증 헤더를 생성합니다.
  static Map<String, String> signRequest({
    required String method,
    required String endpoint,
    required String bucket,
    required String key,
    required String accessKeyId,
    required String secretAccessKey,
    required String region,
    required String contentType,
    required int contentLength,
    Uint8List? bodyBytes,
  }) {
    final uri = Uri.parse(endpoint);
    final host = uri.host;
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);
    final credentialScope = '$dateStamp/$region/s3/aws4_request';

    // 1. Canonical Request 생성
    // Cloudflare R2는 S3 path-style 형식 사용: /bucket/key
    // key가 이미 /로 시작할 수 있으므로 중복 방지
    final normalizedKey = key.startsWith('/') ? key : '/$key';
    final canonicalUri = '/$bucket$normalizedKey';
    final canonicalQueryString = '';

    // Payload Hash 계산 (x-amz-content-sha256에 사용)
    final payloadHash =
        bodyBytes != null
            ? sha256.convert(bodyBytes).toString()
            : sha256.convert(utf8.encode('')).toString();

    // Canonical Headers: AWS Signature V4에서는 헤더를 알파벳 순으로 정렬해야 함
    // 순서: content-type, host, x-amz-content-sha256, x-amz-date
    final canonicalHeaders =
        '${['content-type:$contentType', 'host:$host', 'x-amz-content-sha256:$payloadHash', 'x-amz-date:$amzDate'].join('\n')}\n';
    final signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date';
    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    // 2. String to Sign 생성
    final algorithm = 'AWS4-HMAC-SHA256';
    final stringToSign = [
      algorithm,
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    // 3. Signing Key 생성
    // R2는 S3 호환 API이므로 's3' 서비스 이름 사용
    final kDate = _hmacSha256(utf8.encode('AWS4$secretAccessKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, region);
    final kService = _hmacSha256(kRegion, 's3'); // R2는 S3 호환 API
    final kSigning = _hmacSha256(kService, 'aws4_request');

    // 4. Signature 생성
    final signature =
        _hmacSha256(
          kSigning,
          stringToSign,
        ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    // 5. Authorization Header 생성
    final authorization =
        '$algorithm Credential=$accessKeyId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    return {
      'Authorization': authorization,
      'x-amz-content-sha256': payloadHash, // 🎯 R2에서 필수인 payload hash 헤더
      'x-amz-date': amzDate,
      'Content-Type': contentType,
      'Content-Length': contentLength.toString(),
    };
  }

  static String _formatDateStamp(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String _formatAmzDate(DateTime date) {
    return '${_formatDateStamp(date)}T${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}Z';
  }

  static List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }
}
