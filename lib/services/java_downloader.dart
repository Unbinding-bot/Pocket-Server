// lib/services/java_downloader.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:pocket_server/services/debug_logger.dart';
import 'package:pocket_server/services/popup_service.dart';

class JavaDownloader {
  static const String jdkUrl = 
      "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.8.1%2B1/OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.8.1_1.tar.gz";
  static const String playitUrl = 
      "https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-aarch64";

  // Callback for progress updates (optional)
  Function(double)? onProgress;
  final _logger = DebugLogger();
  final _popup = PopupService();

  Future<void> initEnvironment() async {
    final appDir = await getApplicationDocumentsDirectory();
    final binDir = Directory('${appDir.path}/bin');
    final jdkDir = Directory('${binDir.path}/jdk');

    if (!binDir.existsSync()) binDir.createSync(recursive: true);

    // 1. Install JDK
    if (!jdkDir.existsSync()) {
      _logger.info("JDK not found. Starting download...");
      await _downloadAndExtractTarGz(jdkUrl, binDir.path);
    } else {
      _logger.info("JDK already installed at: ${jdkDir.path}");
    }

    // 2. Install Playit
    final playitFile = File('${binDir.path}/playit');
    if (!playitFile.existsSync()) {
      _logger.info("Downloading Playit...");
      await _downloadFileStreaming(playitUrl, playitFile.path);
      await _makeExecutable(playitFile.path);
    } else {
      _logger.info("Playit already installed");
    }

    // 3. Make Java executable
    final javaPath = '${jdkDir.path}/bin/java';
    if (await File(javaPath).exists()) {
      await _makeExecutable(javaPath);
      _logger.success("Java is ready at: $javaPath");
    } else {
      _logger.error("Java binary not found after extraction at: $javaPath");
      throw Exception("Java binary not found after extraction at: $javaPath");
    }
    
    _logger.success("System Environment Ready");
  }

  Future<void> _downloadAndExtractTarGz(String url, String targetPath) async {
    final tempFile = File('$targetPath/jdk_temp.tar.gz');
    
    _logger.info("Downloading JDK (this may take a few minutes)...");
    await _downloadFileStreaming(url, tempFile.path);
    _logger.success("Download complete (${(tempFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)");

    _logger.info("Extracting JDK (this may take a minute)...");
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
        final outputFile = File(filePath);
        outputFile.createSync(recursive: true);
        
        // Write with executable permissions for bin files
        await outputFile.writeAsBytes(data, mode: FileMode.write, flush: true);
        
        // Set permissions immediately for executables
        if (filePath.contains('/bin/')) {
          await Process.run('chmod', ['755', filePath]);
        }
        
        fileCount++;
      } else {
        Directory(filePath).createSync(recursive: true);
      }
    }
    _logger.success("Extracted $fileCount files");

    // Find the extracted JDK folder (usually named like 'jdk-17.0.8.1+1')
    final extractedFolders = Directory(targetPath)
        .listSync()
        .where((e) => e is Directory && e.path.contains("jdk-17"))
        .toList();
    
    if (extractedFolders.isEmpty) {
      _logger.error("Could not find extracted JDK folder in $targetPath");
      throw Exception("Could not find extracted JDK folder in $targetPath");
    }

    final extractedFolder = extractedFolders.first as Directory;
    final finalPath = '$targetPath/jdk';
    
    _logger.info("Renaming ${extractedFolder.path} -> $finalPath");
    await extractedFolder.rename(finalPath);
    await tempFile.delete();
    
    _logger.success("JDK extraction complete");
  }

  // Stream-based download to handle large files
  Future<void> _downloadFileStreaming(String url, String savePath) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        _logger.error("Download failed: HTTP ${response.statusCode}");
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
        
        // Log progress every 10MB
        if (downloaded % (10 * 1024 * 1024) < chunk.length) {
          final msg = "Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB" +
                (totalBytes > 0 ? " / ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB" : "");
          _logger.info(msg);
        }
      }
      
      await sink.flush();
      await sink.close();
      
      _logger.success("Download complete: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB");
    } catch (e) {
      _logger.error("Download error: $e");
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> _makeExecutable(String filePath) async {
    try {
      // Method 1: Try chmod first
      var result = await Process.run('chmod', ['755', filePath]);
      if (result.exitCode == 0) {
        _logger.success("Made executable (chmod): $filePath");
        return;
      }
      
      // Method 2: Use Dart's File API to set permissions
      final file = File(filePath);
      if (await file.exists()) {
        // Read and rewrite the file to set proper permissions
        final bytes = await file.readAsBytes();
        await file.writeAsBytes(bytes, mode: FileMode.write, flush: true);
        
        // Try running chmod again after rewriting
        result = await Process.run('chmod', ['755', filePath]);
        if (result.exitCode == 0) {
          _logger.success("Made executable (after rewrite): $filePath");
          return;
        }
      }
      
      _logger.warning("Could not set executable permissions for $filePath");
    } catch (e) {
      _logger.error("Error setting permissions for $filePath: $e");
    }
  }
}
