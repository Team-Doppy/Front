import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui';

/// Formats a [Duration] object to a human-readable string.
///
/// Example:
/// ```dart
/// final duration = Duration(hours: 1, minutes: 30, seconds: 15);
/// print(_formatDuration(duration)); // Output: 01:30:15

/// Generates a stream of thumbnails for a given video.
///
/// This function generates a specified number of thumbnails for a video at
/// different timestamps and yields them as a stream of lists of byte arrays.
///
/// Parameters:
/// - `videoPath` (required): The path to the video file.
/// - `videoDuration` (required): The duration of the video in milliseconds.
/// - `numberOfThumbnails` (required): The number of thumbnails to generate.
/// - `quality` (required): The quality of the thumbnails (percentage).
/// - `onThumbnailLoadingComplete` (required): A callback function that is
///   called when all thumbnails have been generated.
/// - `thumbnailGenerator` (required): A callback function that generates
///   thumbnail bytes from a video path and timestamp.
///
/// Returns:
/// A stream of lists of byte arrays, where each list contains the generated
/// thumbnails up to that point.
///
/// Example usage:
/// ```dart
/// final thumbnailStream = generateThumbnail(
///   videoPath: 'path/to/video.mp4',
///   videoDuration: 60000, // 1 minute
///   numberOfThumbnails: 10,
///   quality: 50,
///   onThumbnailLoadingComplete: () {
///     print('Thumbnails generated successfully!');
///   },
///   thumbnailGenerator: (path, timestamp, quality) async {
///     // Use VideoThumbnail or FFmpeg to generate thumbnail
///     return await VideoThumbnail.thumbnailData(
///       video: path,
///       imageFormat: ImageFormat.JPEG,
///       timeMs: timestamp,
///       quality: quality,
///     );
///   },
/// );
///
/// await for (final thumbnails in thumbnailStream) {
///   // Process the thumbnails
/// }
/// ```
///
/// Throws:
/// An error if the thumbnails could not be generated.
Stream<List<Uint8List?>> generateThumbnail({
  required String videoPath,
  required int videoDuration,
  required int numberOfThumbnails,
  required double thumbnailHeight,
  required int quality,
  required VoidCallback onThumbnailLoadingComplete,
  required Future<Uint8List?> Function(
    String videoPath,
    int timestamp,
    int quality,
  )
  thumbnailGenerator,
}) async* {
  final double eachPart = videoDuration / numberOfThumbnails;
  final List<Uint8List?> thumbnailBytes = [];

  try {
    // Generate video thumbnails
    for (int i = 1; i <= numberOfThumbnails; i++) {
      log('Generating thumbnail $i / $numberOfThumbnails');

      // Calculate the timestamp for the thumbnail in milliseconds
      final timestamp = (eachPart * i).toInt();

      // Generate the thumbnail image bytes using the provided callback
      final bytes = await thumbnailGenerator(videoPath, timestamp, quality);

      thumbnailBytes.add(bytes);

      if (thumbnailBytes.length == numberOfThumbnails) {
        onThumbnailLoadingComplete();
      }

      yield thumbnailBytes;
    }
  } catch (e) {
    log('ERROR: Couldn\'t generate thumbnails: $e');
  }
}
