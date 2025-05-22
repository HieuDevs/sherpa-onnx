// Copyright (c)  2024  Xiaomi Corporation
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum DownloadStage {
  downloading,
  downloadComplete,
  archiveFound,
  decompressing,
  extracting,
  writingFiles,
  extractionComplete,
  error,
}

Future<String> generateWaveFilename([String suffix = '']) async {
  final Directory directory = await getApplicationDocumentsDirectory();
  DateTime now = DateTime.now();
  final filename =
      '${now.year.toString()}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}$suffix.wav';

  return p.join(directory.path, filename);
}

Future<bool> isTTSSherpaModelAvailable(String modelDir) async {
  final Directory directory = await getApplicationDocumentsDirectory();
  final Directory modelDirectory = Directory(p.join(directory.path, modelDir));
  return await modelDirectory.exists();
}

Future<bool> downloadAndExtractBzTar({
  required String url,
  required void Function(double progress, DownloadStage stage) onProgress,
}) async {
  try {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String archiveName = url.split('/').last;
    final String archivePath = p.join(directory.path, archiveName);

    final File archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      // Download
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();
      if (response.statusCode != 200) {
        onProgress(0, DownloadStage.error);
        return false;
      }
      final contentLength = response.contentLength ?? 0;
      int received = 0;
      final file = archiveFile.openWrite();
      await response.stream.listen((chunk) {
        received += chunk.length;
        file.add(chunk);
        if (contentLength > 0) {
          onProgress(received / contentLength, DownloadStage.downloading);
        }
      }).asFuture();
      await file.close();
      onProgress(1.0, DownloadStage.downloadComplete);
    } else {
      onProgress(1.0, DownloadStage.archiveFound);
    }

    // Read the .tar.bz2 file
    final bytes = await archiveFile.readAsBytes();
    onProgress(0.05, DownloadStage.decompressing);
    final tarData = BZip2Decoder().decodeBytes(bytes);
    onProgress(0.25, DownloadStage.extracting);
    final archive = TarDecoder().decodeBytes(tarData);

    int totalFiles = archive.files.length;
    int extracted = 0;
    for (final file in archive.files) {
      final filename = file.name;
      final outPath = p.join(directory.path, filename);
      if (file.isFile) {
        await File(outPath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(file.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
      extracted++;
      onProgress(0.85 + 0.15 * (extracted / totalFiles), DownloadStage.writingFiles);
    }
    onProgress(1.0, DownloadStage.extractionComplete);

    // Remove archive
    await archiveFile.delete();
    return true;
  } catch (e) {
    onProgress(0, DownloadStage.error);
    return false;
  }
}
