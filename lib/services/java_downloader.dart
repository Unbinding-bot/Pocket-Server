// lib/services/java_downloader.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';

class JavaDownloader {
  static const String jdkUrl = 
      "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.8.1%2B1/OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.8.1_1.tar.gz";
  static const String playitUrl = 
      "https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-aarch64";

  // Callback for progress updates (optional)
  Function(double)? onProgress;

  Future<void> initEnvironment() async {
    final appDir = await getApplicationDocumentsDirectory();
    final binDir = Directory('${appDir.path}/bin');
    final jdkDir = Directory('${binDir.path}/jdk');

    if (!binDir.existsSync()) binDir.createSync(recursive: true);

    // 1. Install JDK
    if (!jdkDir.existsSync()) {
      print("JDK not found. Starting download...");
      await _downloadAndExtractTarGz(jdkUrl, binDir.path);
    } else {
      print("JDK already installed at: ${jdkDir.path}");
    }

    // 2. Install Playit
    final playitFile = File('${binDir.path}/playit');
    if (!playitFile.existsSync()) {
      print("Downloading Playit...");
      await _downloadFileStreaming(playitUrl, playitFile.path);
      await _makeExecutable(playitFile.path);
    } else {
      print("Playit already installed");
    }

    // 3. Make Java executable
    final javaPath = '${jdkDir.path}/bin/java';
    if (await File(javaPath).exists()) {
      await _makeExecutable(javaPath);
      print("✓ Java is ready at: $javaPath");
    } else {
      throw Exception("Java binary not found after extraction at: $javaPath");
    }
    
    print("✓ System Environment Ready");
  }

  Future<void> _downloadAndExtractTarGz(String url, String targetPath) async {
    final tempFile = File('$targetPath/jdk_temp.tar.gz');
    
    print("Downloading JDK (this may take a few minutes)...");
    await _downloadFileStreaming(url, tempFile.path);
    print("✓ Download complete (${(tempFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)");

    print("Extracting JDK (this may take a minute)...");
    final bytes = tempFile.readAsBytesSync();
    final decoded = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(decoded);

    // Extract all files
    int fileCount = 0;
    for (final file in archive) {
      final filename = file.name;
      final filePath = '$targetPath/$filename';
      
      if (file.isFile) {
        final data = file.content as List<int>;
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
        fileCount++;
      } else {
        Directory(filePath).createSync(recursive: true);
      }
    }
    print("✓ Extracted $fileCount files");

    // Find the extracted JDK folder (usually named like 'jdk-17.0.8.1+1')
    final extractedFolders = Directory(targetPath)
        .listSync()
        .where((e) => e is Directory && e.path.contains("jdk-17"))
        .toList();
    
    if (extractedFolders.isEmpty) {
      throw Exception("Could not find extracted JDK folder in $targetPath");
    }

    final extractedFolder = extractedFolders.first as Directory;
    final finalPath = '$targetPath/jdk';
    
    print("Renaming ${extractedFolder.path} -> $finalPath");
    await extractedFolder.rename(finalPath);
    await tempFile.delete();
    
    print("✓ JDK extraction complete");
  }

  // Stream-based download to handle large files
  Future<void> _downloadFileStreaming(String url, String savePath) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        throw Exception("Download failed: HTTP ${response.statusCode}");
      }

      final file = File(savePath);
      final sink = file.openWrite();
      
      int downloaded = 0;
      final totalBytes = response.contentLength ?? 0;
      
      await for (var chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        
        if (totalBytes > 0 && onProgress != null) {
          onProgress!(downloaded / totalBytes);
        }
        
        // Print progress every 10MB
        if (downloaded % (10 * 1024 * 1024) < chunk.length) {
          print("Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB" +
                (totalBytes > 0 ? " / ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB" : ""));
        }
      }
      
      await sink.flush();
      await sink.close();
      
      print("✓ Download complete: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB");
    } finally {
      client.close();
    }
  }

  Future<void> _makeExecutable(String filePath) async {
    try {
      final result = await Process.run('chmod', ['+x', filePath]);
      if (result.exitCode == 0) {
        print("✓ Made executable: $filePath");
      } else {
        print("Warning: chmod failed for $filePath: ${result.stderr}");
      }
    } catch (e) {
      print("Error setting permissions for $filePath: $e");
    }
  }
}
