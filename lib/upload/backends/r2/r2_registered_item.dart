/// R2 업로드 완료 후 서버 메타데이터 등록 시 전달하는 항목
class R2RegisteredItem {
  final String storageUrl;
  final int fileSize;
  final String mimeType;
  final String originalFileName;

  const R2RegisteredItem({
    required this.storageUrl,
    required this.fileSize,
    required this.mimeType,
    required this.originalFileName,
  });

  Map<String, dynamic> toJson() => {
        'storageUrl': storageUrl,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'originalFileName': originalFileName,
      };
}
