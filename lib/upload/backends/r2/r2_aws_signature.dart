import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// AWS Signature V4 (R2는 S3 호환 API)
class R2AwsSignatureV4 {
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

    final normalizedKey = key.startsWith('/') ? key : '/$key';
    final canonicalUri = '/$bucket$normalizedKey';
    const canonicalQueryString = '';

    final payloadHash = bodyBytes != null
        ? sha256.convert(bodyBytes).toString()
        : sha256.convert(utf8.encode('')).toString();

    final canonicalHeaders = [
      'content-type:$contentType',
      'host:$host',
      'x-amz-content-sha256:$payloadHash',
      'x-amz-date:$amzDate',
    ].join('\n') +
        '\n';
    const signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date';
    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    const algorithm = 'AWS4-HMAC-SHA256';
    final stringToSign = [
      algorithm,
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final kDate = _hmacSha256(utf8.encode('AWS4$secretAccessKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, region);
    final kService = _hmacSha256(kRegion, 's3');
    final kSigning = _hmacSha256(kService, 'aws4_request');

    final signature = _hmacSha256(kSigning, stringToSign)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    final authorization =
        '$algorithm Credential=$accessKeyId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    return {
      'Authorization': authorization,
      'x-amz-content-sha256': payloadHash,
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
    return '${_formatDateStamp(date)}T'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}Z';
  }

  static List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }
}
