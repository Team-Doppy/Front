/// 파일명 → MIME 타입 (모든 백엔드 공통)
class UploadMimeTypes {
  UploadMimeTypes._();

  static String fromFileName(String fileNameOrPath) {
    final name = fileNameOrPath.split('/').last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    switch (ext) {
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
      case 'm4v':
        return 'video/x-m4v';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }
}
