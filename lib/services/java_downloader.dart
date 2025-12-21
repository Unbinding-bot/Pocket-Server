// lib/services/java_downloader.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';

class JavaDownloader {
  // URLs for aarch64 (ARM64) Linux binaries
  static const String jdkUrl = 
      "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.8.1%2B1/OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.8.1_1.tar.gz";
  static const String playitUrl = 
      "https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-aarch64";

  Future<void> initEnvironment() async {
    final appDir = await getApplicationDocumentsDirectory();
    final binDir = Directory('${appDir.path}/bin');
    final jdkDir = Directory('${binDir.path}/jdk');

    if (!binDir.existsSync()) binDir.createSync(recursive: true);

    // 1. Install JDK
    if (!jdkDir.existsSync()) {
      await _downloadAndExtractTarGz(jdkUrl, binDir.path, "jdk_temp.tar.gz", "jdk");
    }

    // 2. Install Playit
    final playitFile = File('${binDir.path}/playit');
    if (!playitFile.existsSync()) {
      await _downloadFile(playitUrl, playitFile.path);
    }

    // 3. SET EXECUTABLE PERMISSIONS (Critical for Linux binaries on Android)
    await _makeExecutable('${jdkDir.path}/bin/java');
    await _makeExecutable(playitFile.path);
    
    print("System Environment Ready");
  }

  Future<void> _downloadAndExtractTarGz(String url, String targetPath, String tempFileName, String finalFolderName) async {
    final tempFile = File('$targetPath/$tempFileName');
    print("Downloading JDK...");
    await _downloadFile(url, tempFile.path);

    print("Extracting JDK (This may take a minute)...");
    final bytes = tempFile.readAsBytesSync();
    final decoded = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(decoded);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File('$targetPath/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory('$targetPath/$filename').createSync(recursive: true);
      }
    }

    // Find the extracted folder (it usually has a long name like 'jdk-17.0.8+7')
    final extractedFolder = Directory(targetPath).listSync().firstWhere(
      (e) => e is Directory && e.path.contains("jdk-17")
    ) as Directory;
    
    await extractedFolder.rename('$targetPath/$finalFolderName');
    await tempFile.delete();
  }

  Future<void> _downloadFile(String url, String savePath) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      await File(savePath).writeAsBytes(response.bodyBytes);
    } else {
      throw Exception("Download failed: ${response.statusCode}");
    }
  }

  Future<void> _makeExecutable(String filePath) async {
    // Android is Linux-based; we must 'chmod +x' to run the files
    try {
      await Process.run('chmod', ['+x', filePath]);
    } catch (e) {
      print("Error setting permissions: $e");
    }
  }
}