// lib/services/java_downloader.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';
import 'package:PocketServer/services/debug_logger.dart';
import 'package:PocketServer/services/popup_service.dart';
import 'package:PocketServer/services/file_system_service.dart';

class JavaDownloader {
  static const String jdkUrl = 
      "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.8.1%2B1/OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.8.1_1.tar.gz";
  static const String playitUrl = 
      "https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-aarch64";

  // Callback for progress updates (optional)
  Function(double)? onProgress;
  final _logger = DebugLogger();
  final _popup = PopupService();
  final _fs = FileSystemService();

  Future<void> initEnvironment() async {
    // Register our paths with the file system service
    _registerPaths();
    
    // Ensure file system is initialized
    await _fs.initialize();
    
    _logger.info("Using storage: ${_fs.basePath}");
    _logger.info("Executable: ${_fs.canExecute}");

    // 1. Install JDK
    final jdkPath = _fs.getPath('java_jdk');
    if (!await _fs.directoryExists(jdkPath)) {
      _logger.info("JDK not found. Starting download...");
      final binPath = _fs.getPath('java_bin');
      await _downloadAndExtractTarGz(jdkUrl, binPath);
    } else {
      _logger.info("JDK already installed at: $jdkPath");
    }

    // 2. Install Playit
    final playitPath = _fs.getPath('playit_binary');
    if (!await _fs.fileExists(playitPath)) {
      _logger.info("Downloading Playit...");
      await _downloadFileStreaming(playitUrl, playitPath);
      await _fs.makeExecutable(playitPath);
    } else {
      _logger.info("Playit already installed");
    }

    // 3. Make Java executable and test
    final javaPath = _fs.getPath('java_binary');
    if (await _fs.fileExists(javaPath)) {
      await _fs.makeExecutable(javaPath);
      
      // Test execution
      try {
        _logger.info("Testing Java execution...");
        final testResult = await Process.run(javaPath, ['--version']).timeout(
          Duration(seconds: 5),
          onTimeout: () => throw Exception('Java test timeout'),
        );
        
        if (testResult.exitCode == 0 || testResult.stderr.toString().contains('version')) {
          _logger.success("Java is executable and working!");
        } else {
          throw Exception("Java returned unexpected output");
        }
      } catch (e) {
        _logger.error("Java execution test failed: $e");
        
        if (!_fs.canExecute) {
          throw Exception(
            "Device does not support binary execution.\n\n"
            "Your device prevents running executable files (noexec flag).\n"
            "Try: Settings → Storage → Format as Internal Storage"
          );
        }
        
        throw Exception("Java binary cannot be executed: $e");
      }
      
      _logger.success("Java is ready at: $javaPath");
    } else {
      _logger.error("Java binary not found after extraction");
      throw Exception("Java binary not found after extraction");
    }
    
    _logger.success("System Environment Ready");
    _logger.info("Storage location: ${_fs.basePath}");
  }

  /// Register all paths that JavaDownloader needs
  void _registerPaths() {
    // Binary folder (needs execution support)
    _fs.registerPath(
      'java_bin',
      'bin',
      requirements: {LocationRequirement.executable, LocationRequirement.persistent},
      description: 'Binary storage for Java and Playit',
    );

    // JDK installation directory
    _fs.registerPath(
      'java_jdk',
      'bin/jdk',
      requirements: {LocationRequirement.executable, LocationRequirement.persistent},
      description: 'Java Development Kit installation',
    );

    // Java binary itself
    _fs.registerPath(
      'java_binary',
      'bin/jdk/bin/java',
      requirements: {LocationRequirement.executable, LocationRequirement.persistent},
      description: 'Java executable binary',
    );

    // Playit binary
    _fs.registerPath(
      'playit_binary',
      'bin/playit',
      requirements: {LocationRequirement.executable, LocationRequirement.persistent},
      description: 'Playit.gg tunnel binary',
    );

    _logger.info("JavaDownloader paths registered");
  }

  Future<void> _downloadAndExtractTarGz(String url, String targetPath) async {
    final tempFile = File('$targetPath/jdk_temp.tar.gz');
    
    _logger.info("Downloading JDK (this may take a few minutes)...");
    await _downloadFileStreaming(url, tempFile.path);
    _logger.success("Download complete (${(tempFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)");

    _logger.info("Extracting JDK (this may take a minute)...");
    
    try {
      final bytes = await tempFile.readAsBytes();
      _logger.info("Read ${bytes.length} bytes from archive");
      
      final decoded = GZipDecoder().decodeBytes(bytes);
      _logger.info("GZip decoded: ${decoded.length} bytes");
      
      final archive = TarDecoder().decodeBytes(decoded);
      _logger.info("Tar archive contains ${archive.length} files");

      // Extract all files
      int fileCount = 0;
      int dirCount = 0;
      
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
          
          // Log key files
          if (filename.contains('bin/java')) {
            _logger.info("Extracted: $filename (${data.length} bytes)");
          }
        } else {
          Directory(filePath).createSync(recursive: true);
          dirCount++;
        }
      }
      _logger.success("Extracted $fileCount files and $dirCount directories");

      // List what was actually extracted in targetPath
      _logger.info("Contents of $targetPath:");
      final contents = Directory(targetPath).listSync();
      for (var item in contents) {
        final name = item.path.split('/').last;
        if (item is Directory) {
          _logger.info("  DIR: $name");
        } else if (item is File) {
          final size = (item as File).lengthSync();
          _logger.info("  FILE: $name (${size} bytes)");
        }
      }

      // Find the extracted JDK folder (usually named like 'jdk-17.0.8.1+1')
      final extractedFolders = Directory(targetPath)
          .listSync()
          .where((e) => e is Directory && e.path.contains("jdk-17"))
          .toList();
      
      if (extractedFolders.isEmpty) {
        _logger.error("Could not find extracted JDK folder in $targetPath");
        _logger.error("Looking for folders containing 'jdk-17'");
        throw Exception("Could not find extracted JDK folder in $targetPath");
      }

      final extractedFolder = extractedFolders.first as Directory;
      final finalPath = '$targetPath/jdk';
      
      _logger.info("Found JDK folder: ${extractedFolder.path}");
      _logger.info("Renaming to: $finalPath");
      
      // Check if jdk folder already exists and delete it
      final existingJdk = Directory(finalPath);
      if (await existingJdk.exists()) {
        _logger.warning("Removing existing jdk folder");
        await existingJdk.delete(recursive: true);
      }
      
      await extractedFolder.rename(finalPath);
      await tempFile.delete();
      
      // Verify the java binary exists
      final javaPath = '$finalPath/bin/java';
      final javaFile = File(javaPath);
      if (await javaFile.exists()) {
        final javaSize = await javaFile.length();
        _logger.success("Java binary found: $javaPath (${javaSize} bytes)");
      } else {
        _logger.error("Java binary NOT found at: $javaPath");
        // List what's in the bin directory
        final binDir = Directory('$finalPath/bin');
        if (await binDir.exists()) {
          _logger.info("Contents of bin/:");
          await for (var item in binDir.list()) {
            _logger.info("  ${item.path.split('/').last}");
          }
        } else {
          _logger.error("bin/ directory does not exist!");
        }
      }
      
      _logger.success("JDK extraction complete");
    } catch (e, stackTrace) {
      _logger.error("Extraction failed: $e");
      _logger.error("Stack trace: $stackTrace");
      rethrow;
    }
  }

  // Stream-based download to handle large files
  Future<void> _downloadFileStreaming(String url, String savePath) async {
    const maxRetries = 3;
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        await _attemptDownload(url, savePath);
        return; // Success, exit
      } catch (e) {
        retryCount++;
        _logger.warning("Download attempt $retryCount failed: $e");
        
        if (retryCount < maxRetries) {
          _logger.info("Retrying in 3 seconds...");
          await Future.delayed(Duration(seconds: 3));
        } else {
          _logger.error("Download failed after $maxRetries attempts");
          rethrow;
        }
      }
    }
  }

  Future<void> _attemptDownload(String url, String savePath) async {
    final client = http.Client();
    try {
      _logger.info("Starting download from: $url");
      
      final request = http.Request('GET', Uri.parse(url));
      
      // Add headers to help with connection stability
      request.headers.addAll({
        'User-Agent': 'PocketHost/1.0',
        'Accept': '*/*',
        'Connection': 'keep-alive',
      });
      
      final response = await client.send(request).timeout(
        Duration(minutes: 10),
        onTimeout: () {
          throw Exception('Download timeout after 10 minutes');
        },
      );
      
      if (response.statusCode != 200) {
        _logger.error("Download failed: HTTP ${response.statusCode}");
        throw Exception("Download failed: HTTP ${response.statusCode}");
      }

      final file = File(savePath);
      final sink = file.openWrite();
      
      int downloaded = 0;
      final totalBytes = response.contentLength ?? 0;
      int lastProgressUpdate = 0;
      
      _logger.info("Downloading ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB");
      
      await for (var chunk in response.stream.timeout(
        Duration(seconds: 30), // Timeout if no data for 30 seconds
        onTimeout: (sink) {
          sink.addError(Exception('Stream timeout - no data received for 30 seconds'));
        },
      )) {
        sink.add(chunk);
        downloaded += chunk.length;
        
        if (totalBytes > 0 && onProgress != null) {
          onProgress!(downloaded / totalBytes);
        }
        
        // Log progress every 10MB
        if (downloaded - lastProgressUpdate >= 10 * 1024 * 1024) {
          lastProgressUpdate = downloaded;
          final msg = "Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB" +
                (totalBytes > 0 ? " / ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB" : "");
          _logger.info(msg);
        }
      }
      
      await sink.flush();
      await sink.close();
      
      _logger.success("Download complete: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB");
      
      // Verify file size
      if (totalBytes > 0 && downloaded != totalBytes) {
        throw Exception('Download incomplete: got $downloaded bytes, expected $totalBytes bytes');
      }
      
    } catch (e) {
      _logger.error("Download error: $e");
      
      // Clean up partial file
      try {
        final file = File(savePath);
        if (await file.exists()) {
          await file.delete();
          _logger.info("Deleted partial download file");
        }
      } catch (_) {}
      
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
