// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';

class PickedFileData {
  final String fileName;
  final List<int> bytes;

  PickedFileData({required this.fileName, required this.bytes});
}

class PlatformImagePicker {
  Future<PickedFileData?> pickImage() async {
    final completer = Completer<PickedFileData?>();

    final input = html.FileUploadInputElement();
    input.accept = 'image/*';
    input.click();

    input.onChange.listen((event) async {
      final files = input.files;
      if (files == null || files.isEmpty) {
        completer.complete(null);
        return;
      }

      final file = files.first;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);

      reader.onLoadEnd.listen((_) {
        final data = reader.result;
        if (data == null) {
          completer.complete(null);
          return;
        }
        List<int> bytes;
        if (data is ByteBuffer) {
          bytes = data.asUint8List();
        } else if (data is Uint8List) {
          bytes = data;
        } else if (data is List<int>) {
          bytes = data;
        } else {
          completer.complete(null);
          return;
        }
        completer.complete(PickedFileData(fileName: file.name, bytes: bytes));
      });

      reader.onError.listen((_) {
        completer.complete(null);
      });
    });

    return completer.future;
  }
}
