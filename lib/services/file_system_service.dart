// lib/services/file_system_service.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:PocketServer/services/debug_logger.dart';

/// Storage location requirements
enum LocationRequirement {
  storage,      // Just needs to store files
  executable,   // Needs to run binaries
  temporary,    // Temporary files (can be cleared)
  persistent,   // Must persist across app restarts
}

/// Storage location metadata
class StorageLocation {
  final String id;
  final String basePath;
  final bool canExecute;
  final bool isExternal;
  final String description;

  StorageLocation({
    required this.id,
    required this.basePath,
    required this.canExecute,
    required this.isExternal,
    required this.description,
  });

  @override
  String toString() => '$description ($basePath) [exec: $canExecute]';
}

/// Registered path entry
class PathRegistry {
  final String key;
  final String relativePath;
  final Set<LocationRequirement> requirements;
  final String? description;
  String? _resolvedPath;

  PathRegistry({
    required this.key,
    required this.relativePath,
    this.requirements = const {},
    this.description,
  });

  String? get resolvedPath => _resolvedPath;
}

/// Centralized file system management service
/// Generic registry system for path management
class FileSystemService {
  static final FileSystemService _instance = FileSystemService._internal();
  factory FileSystemService() => _instance;
  FileSystemService._internal();

  final _logger = DebugLogger();

  // Available storage locations
  final List<StorageLocation> _availableLocations = [];
  StorageLocation? _selectedLocation;

  // Path registry - other services register their paths here
  final Map<String, PathRegistry> _pathRegistry = {};

  bool _initialized = false;

  /// Initialize the file system service
  /// Discovers and tests all available storage locations
  Future<void> initialize() async {
    if (_initialized) {
      _logger.info("FileSystemService already initialized");
      return;
    }

    _logger.info("Initializing FileSystemService...");
    await _discoverStorageLocations();
    await _selectBestLocation();
    await _resolveRegisteredPaths();
    
    _initialized = true;
    _logger.success("FileSystemService initialized");
  }

  /// Discover all available storage locations
  Future<void> _discoverStorageLocations() async {
    _availableLocations.clear();

    // 1. Internal app storage
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final canExec = await _testExecution(appDir.path);
      
      _availableLocations.add(StorageLocation(
        id: 'internal',
        basePath: appDir.path,
        canExecute: canExec,
        isExternal: false,
        description: 'Internal Storage',
      ));
      
      _logger.info("Found: Internal Storage (${appDir.path}) [exec: $canExec]");
    } catch (e) {
      _logger.error("Could not access internal storage: $e");
    }

    // 2. External app-specific storage
    try {
      final externalDir = Directory('/sdcard/Android/data/com.PocketServer/files');
      if (!await externalDir.exists()) {
        await externalDir.create(recursive: true);
      }
      
      final canExec = await _testExecution(externalDir.path);
      
      _availableLocations.add(StorageLocation(
        id: 'external',
        basePath: externalDir.path,
        canExecute: canExec,
        isExternal: true,
        description: 'External Storage',
      ));
      
      _logger.info("Found: External Storage (${externalDir.path}) [exec: $canExec]");
    } catch (e) {
      _logger.warning("Could not access external storage: $e");
    }

    // 3. Public storage (for importing files)
    try {
      final publicDir = Directory('/sdcard/PocketHost');
      if (!await publicDir.exists()) {
        await publicDir.create(recursive: true);
      }
      
      _availableLocations.add(StorageLocation(
        id: 'public',
        basePath: publicDir.path,
        canExecute: false, // Public storage typically can't execute
        isExternal: true,
        description: 'Public Storage',
      ));
      
      _logger.info("Found: Public Storage (${publicDir.path})");
    } catch (e) {
      _logger.warning("Could not access public storage: $e");
    }
  }

  /// Select the best storage location based on registered requirements
  Future<void> _selectBestLocation() async {
    if (_availableLocations.isEmpty) {
      throw Exception("No storage locations available");
    }

    // Check if any registered paths need execution
    final needsExecution = _pathRegistry.values.any(
      (path) => path.requirements.contains(LocationRequirement.executable)
    );

    if (needsExecution) {
      // Find first location that can execute
      _selectedLocation = _availableLocations.firstWhere(
        (loc) => loc.canExecute,
        orElse: () => _availableLocations.first,
      );
      
      if (!_selectedLocation!.canExecute) {
        _logger.warning("No executable storage found, using ${_selectedLocation!.id}");
      } else {
        _logger.success("Selected ${_selectedLocation!.id} (supports execution)");
      }
    } else {
      // Use internal storage by default
      _selectedLocation = _availableLocations.firstWhere(
        (loc) => loc.id == 'internal',
        orElse: () => _availableLocations.first,
      );
      _logger.success("Selected ${_selectedLocation!.id}");
    }
  }

  /// Test if binaries can be executed in a directory
  Future<bool> _testExecution(String path) async {
    try {
      final testScript = File('$path/test_exec_${DateTime.now().millisecondsSinceEpoch}.sh');
      await testScript.writeAsString('#!/system/bin/sh\necho "ok"\n');
      await Process.run('chmod', ['755', testScript.path]);
      
      final result = await Process.run(testScript.path, []).timeout(
        Duration(seconds: 2),
        onTimeout: () => throw Exception('timeout'),
      );
      
      await testScript.delete();
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Resolve all registered paths to actual filesystem paths
  Future<void> _resolveRegisteredPaths() async {
    for (var entry in _pathRegistry.values) {
      entry._resolvedPath = '${_selectedLocation!.basePath}/${entry.relativePath}';
      
      // Create directory if it doesn't exist
      final dir = Directory(entry._resolvedPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        _logger.info("Created: ${entry._resolvedPath}");
      }
    }
  }

  // ============================================================
  // PATH REGISTRATION - Other services use this
  // ============================================================

  /// Register a path that this service should manage
  /// 
  /// Example:
  /// ```dart
  /// _fs.registerPath(
  ///   'java_binary',
  ///   'bin/jdk/bin/java',
  ///   requirements: {LocationRequirement.executable},
  ///   description: 'Java binary for running Minecraft server',
  /// );
  /// ```
  void registerPath(
    String key,
    String relativePath, {
    Set<LocationRequirement> requirements = const {},
    String? description,
  }) {
    if (_pathRegistry.containsKey(key)) {
      _logger.warning("Path '$key' already registered, overwriting");
    }

    _pathRegistry[key] = PathRegistry(
      key: key,
      relativePath: relativePath,
      requirements: requirements,
      description: description,
    );

    _logger.info("Registered path: $key -> $relativePath");

    // If already initialized, resolve immediately
    if (_initialized && _selectedLocation != null) {
      _pathRegistry[key]!._resolvedPath = 
          '${_selectedLocation!.basePath}/$relativePath';
    }
  }

  /// Unregister a path
  void unregisterPath(String key) {
    if (_pathRegistry.remove(key) != null) {
      _logger.info("Unregistered path: $key");
    }
  }

  /// Get resolved path for a registered key
  String getPath(String key) {
    if (!_initialized) {
      throw Exception("FileSystemService not initialized. Call initialize() first.");
    }

    final entry = _pathRegistry[key];
    if (entry == null) {
      throw Exception("Path '$key' not registered. Call registerPath() first.");
    }

    return entry.resolvedPath!;
  }

  /// Get base path of selected storage location
  String get basePath {
    if (!_initialized || _selectedLocation == null) {
      throw Exception("FileSystemService not initialized");
    }
    return _selectedLocation!.basePath;
  }

  /// Check if selected location supports execution
  bool get canExecute {
    if (!_initialized || _selectedLocation == null) return false;
    return _selectedLocation!.canExecute;
  }

  /// Get all registered paths
  Map<String, String> getAllPaths() {
    return Map.fromEntries(
      _pathRegistry.entries.map((e) => MapEntry(e.key, e.value.resolvedPath ?? 'unresolved'))
    );
  }

  // ============================================================
  // FILE OPERATIONS
  // ============================================================

  /// Copy a file from source to destination
  Future<bool> copyFile(String sourcePath, String destPath) async {
    try {
      _logger.info("Copying: $sourcePath -> $destPath");
      
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        _logger.error("Source file does not exist: $sourcePath");
        return false;
      }

      final destFile = File(destPath);
      await destFile.parent.create(recursive: true);
      await sourceFile.copy(destPath);
      
      _logger.success("Copy successful");
      return true;
    } catch (e) {
      _logger.error("Copy failed: $e");
      return false;
    }
  }

  /// Move a file from source to destination
  Future<bool> moveFile(String sourcePath, String destPath) async {
    try {
      _logger.info("Moving: $sourcePath -> $destPath");
      
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        _logger.error("Source file does not exist: $sourcePath");
        return false;
      }

      final destFile = File(destPath);
      await destFile.parent.create(recursive: true);
      
      // Try rename first (faster if same filesystem)
      try {
        await sourceFile.rename(destPath);
        _logger.success("Move successful (rename)");
        return true;
      } catch (e) {
        // If rename fails, copy then delete
        await sourceFile.copy(destPath);
        await sourceFile.delete();
        _logger.success("Move successful (copy+delete)");
        return true;
      }
    } catch (e) {
      _logger.error("Move failed: $e");
      return false;
    }
  }

  /// Delete a file
  Future<bool> deleteFile(String filePath) async {
    try {
      _logger.info("Deleting: $filePath");
      
      final file = File(filePath);
      if (!await file.exists()) {
        _logger.warning("File does not exist: $filePath");
        return true;
      }

      await file.delete();
      _logger.success("Delete successful");
      return true;
    } catch (e) {
      _logger.error("Delete failed: $e");
      return false;
    }
  }

  /// Delete a directory and all its contents
  Future<bool> deleteDirectory(String dirPath, {bool recursive = false}) async {
    try {
      _logger.info("Deleting directory: $dirPath");
      
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        _logger.warning("Directory does not exist: $dirPath");
        return true;
      }

      await dir.delete(recursive: recursive);
      _logger.success("Directory deleted");
      return true;
    } catch (e) {
      _logger.error("Directory delete failed: $e");
      return false;
    }
  }

  /// Copy a directory and all its contents
  Future<bool> copyDirectory(String sourcePath, String destPath) async {
    try {
      _logger.info("Copying directory: $sourcePath -> $destPath");
      
      final sourceDir = Directory(sourcePath);
      if (!await sourceDir.exists()) {
        _logger.error("Source directory does not exist: $sourcePath");
        return false;
      }

      final destDir = Directory(destPath);
      await destDir.create(recursive: true);

      await for (var entity in sourceDir.list(recursive: true)) {
        final relativePath = entity.path.replaceFirst(sourcePath, '');
        final newPath = destPath + relativePath;

        if (entity is File) {
          await entity.copy(newPath);
        } else if (entity is Directory) {
          await Directory(newPath).create(recursive: true);
        }
      }

      _logger.success("Directory copy successful");
      return true;
    } catch (e) {
      _logger.error("Directory copy failed: $e");
      return false;
    }
  }

  /// Move a directory and all its contents
  Future<bool> moveDirectory(String sourcePath, String destPath) async {
    try {
      _logger.info("Moving directory: $sourcePath -> $destPath");
      
      final sourceDir = Directory(sourcePath);
      if (!await sourceDir.exists()) {
        _logger.error("Source directory does not exist: $sourcePath");
        return false;
      }

      // Try rename first
      try {
        await sourceDir.rename(destPath);
        _logger.success("Directory move successful (rename)");
        return true;
      } catch (e) {
        // If rename fails, copy then delete
        await copyDirectory(sourcePath, destPath);
        await sourceDir.delete(recursive: true);
        _logger.success("Directory move successful (copy+delete)");
        return true;
      }
    } catch (e) {
      _logger.error("Directory move failed: $e");
      return false;
    }
  }

  /// Check if file exists
  Future<bool> fileExists(String filePath) async {
    return await File(filePath).exists();
  }

  /// Check if directory exists
  Future<bool> directoryExists(String dirPath) async {
    return await Directory(dirPath).exists();
  }

  /// Get file size in bytes
  Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return 0;
      return await file.length();
    } catch (e) {
      _logger.error("Failed to get file size: $e");
      return 0;
    }
  }

  /// List files in a directory
  Future<List<FileSystemEntity>> listDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];
      return await dir.list().toList();
    } catch (e) {
      _logger.error("Failed to list directory: $e");
      return [];
    }
  }

  /// Make file executable (for binaries)
  Future<bool> makeExecutable(String filePath) async {
    try {
      _logger.info("Making executable: $filePath");
      
      final result = await Process.run('chmod', ['755', filePath]);
      
      if (result.exitCode == 0) {
        _logger.success("File is now executable");
        return true;
      } else {
        _logger.error("chmod failed: ${result.stderr}");
        return false;
      }
    } catch (e) {
      _logger.error("Failed to make executable: $e");
      return false;
    }
  }

  // ============================================================
  // UTILITY METHODS
  // ============================================================

  /// Get storage info as a readable string
  String getStorageInfo() {
    if (!_initialized) return "Not initialized";

    final buffer = StringBuffer();
    buffer.writeln('=== Storage Locations ===');
    for (var loc in _availableLocations) {
      final selected = loc.id == _selectedLocation?.id ? ' [SELECTED]' : '';
      buffer.writeln('${loc.id}: ${loc.basePath}$selected');
      buffer.writeln('  Executable: ${loc.canExecute}');
      buffer.writeln('  External: ${loc.isExternal}');
    }
    
    buffer.writeln('\n=== Registered Paths ===');
    for (var entry in _pathRegistry.entries) {
      buffer.writeln('${entry.key}:');
      buffer.writeln('  Relative: ${entry.value.relativePath}');
      buffer.writeln('  Resolved: ${entry.value.resolvedPath ?? "unresolved"}');
      if (entry.value.requirements.isNotEmpty) {
        buffer.writeln('  Requirements: ${entry.value.requirements.map((r) => r.name).join(", ")}');
      }
    }
    
    return buffer.toString();
  }

  /// Clean up temporary files
  Future<void> cleanTempFiles() async {
    try {
      final tempEntries = _pathRegistry.entries.where(
        (e) => e.value.requirements.contains(LocationRequirement.temporary)
      );
      
      for (var entry in tempEntries) {
        final path = entry.value.resolvedPath;
        if (path != null) {
          final dir = Directory(path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
            await dir.create();
            _logger.info("Cleaned: ${entry.key}");
          }
        }
      }
      _logger.success("Temporary files cleaned");
    } catch (e) {
      _logger.error("Failed to clean temp files: $e");
    }
  }
}