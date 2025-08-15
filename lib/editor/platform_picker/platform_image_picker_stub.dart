class PickedFileData {
  final String fileName;
  final List<int> bytes;

  PickedFileData({required this.fileName, required this.bytes});
}

class PlatformImagePicker {
  Future<PickedFileData?> pickImage() async {
    // Non-web platforms use image_picker directly in calling code.
    return null;
  }
}
