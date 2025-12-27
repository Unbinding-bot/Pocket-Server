// lib/main.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:PocketServer/services/java_downloader.dart';
import 'package:PocketServer/services/debug_logger.dart';
import 'package:PocketServer/services/popup_service.dart';
import 'package:PocketServer/services/permission_handler.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketHost - Java Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: JavaTestScreen(),
    );
  }
}

class JavaTestScreen extends StatefulWidget {
  const JavaTestScreen({super.key});

  @override
  State<JavaTestScreen> createState() => _JavaTestScreenState();
}

class _JavaTestScreenState extends State<JavaTestScreen> {
  String _statusText = 'Press button to test Java installation';
  bool _isTesting = false;
  bool _isDownloading = false;
  bool _hasStoragePermission = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  final _logger = DebugLogger();
  final _popup = PopupService();

  @override
  void initState() {
    super.initState();
    // Set global context for services after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logger.setContext(context);
      _popup.setContext(context);
      _checkPermissions();
    });
  }

  /// Check and request necessary permissions using the handler
  Future<void> _checkPermissions() async {
    final granted = await AppPermissionHandler.checkAndRequestWithUI(context);
    
    setState(() {
      _hasStoragePermission = granted;
      _statusText = granted 
          ? 'Ready! All permissions granted.' 
          : 'Permissions required to continue';
    });

    if (granted) {
      _testStorageAccess();
    }
  }

  /// Test if we can actually write to storage
  Future<void> _testStorageAccess() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _logger.info("App directory: ${appDir.path}");
      
      // Test write access
      final testFile = File('${appDir.path}/test.txt');
      await testFile.writeAsString('test');
      await testFile.delete();
      
      _logger.success("Storage access confirmed: ${appDir.path}");
      
      setState(() {
        _statusText = 'Ready! Storage access confirmed.';
      });
    } catch (e) {
      _logger.error("Storage access test failed: $e");
      _popup.showErrorDialog(
        title: "Storage Access Failed",
        message: "Cannot write to app directory:\n\n$e",
      );
    }
  }

  /// Debug method to check file structure
  Future<void> _checkFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final binDir = Directory('${appDir.path}/bin');
      final jdkDir = Directory('${appDir.path}/bin/jdk');
      final javaPath = "${appDir.path}/bin/jdk/bin/java";
      
      String info = 'Base path: ${appDir.path}\n\n';
      
      info += 'bin/ exists: ${await binDir.exists()}\n';
      info += 'jdk/ exists: ${await jdkDir.exists()}\n';
      info += 'java binary exists: ${await File(javaPath).exists()}\n\n';
      
      if (await jdkDir.exists()) {
        info += 'JDK contents:\n';
        await for (var entity in jdkDir.list(recursive: false)) {
          info += '  ${entity.path.split('/').last}\n';
        }
      }
      
      final javaBinDir = Directory('${appDir.path}/bin/jdk/bin');
      if (await javaBinDir.exists()) {
        info += '\nbin/ contents:\n';
        await for (var entity in javaBinDir.list()) {
          final name = entity.path.split('/').last;
          if (entity is File) {
            final stat = await entity.stat();
            info += '  $name (${stat.size} bytes)\n';
          } else {
            info += '  $name/\n';
          }
        }
      }
      
      _showResult('File Structure', info, isError: false);
    } catch (e) {
      _showResult('Debug Error', 'Error: $e', isError: true);
    }
  }

  /// Method to download and install Java environment
  Future<void> _downloadJava() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Preparing download...';
    });

    try {
      final downloader = JavaDownloader();
      
      // Set up progress callback - just update state, don't touch dialogs
      downloader.onProgress = (progress) {
        setState(() {
          _downloadProgress = progress;
          _downloadStatus = 'Downloading JDK... ${(progress * 100).toStringAsFixed(0)}%';
        });
      };

      _logger.info("Starting Java download...");
      
      // Show the download dialog with live progress
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DownloadProgressDialog(
          getProgress: () => _downloadProgress,
          getMessage: () => _downloadStatus,
          onMinimize: () {
            Navigator.pop(context);
            _showMinimizedDownload();
          },
        ),
      );
      
      await downloader.initEnvironment();
      
      // Close dialog
      if (mounted) Navigator.pop(context);
      _popup.closeMinimized(); // Also close if minimized
      
      // Show success
      await _popup.showSuccessDialog(
        title: '✓ Installation Complete', 
        message: 'Java has been downloaded and installed successfully.\n\nYou can now test the installation.',
      );
      
      setState(() {
        _statusText = 'Java installed successfully! Ready to test.';
      });
    } catch (e) {
      _logger.error("Download failed: $e");
      
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      _popup.closeMinimized();
      
      // Show error with retry option
      final shouldRetry = await _popup.showConfirmation(
        title: 'Download Failed',
        message: 'Error during download:\n\n$e\n\nThis usually happens due to network issues. Would you like to retry?',
        confirmText: 'Retry',
        cancelText: 'Cancel',
      );
      
      if (shouldRetry) {
        // Retry the download
        await Future.delayed(Duration(seconds: 1));
        _downloadJava();
        return;
      }
    } finally {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
    }
  }

  void _showMinimizedDownload() {
    // Create minimized floating button manually
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        right: 16,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(30),
          child: InkWell(
            onTap: () {
              overlayEntry.remove();
              // Restore the dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => _DownloadProgressDialog(
                  getProgress: () => _downloadProgress,
                  getMessage: () => _downloadStatus,
                  onMinimize: () {
                    Navigator.pop(context);
                    _showMinimizedDownload();
                  },
                ),
              );
            },
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                      value: _downloadProgress,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Downloading ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      overlayEntry.remove();
                    },
                    child: Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
  }

  /// Method to run the 'java -version' command to verify installation
  Future<void> testJava() async {
    setState(() {
      _isTesting = true;
      _statusText = 'Testing Java...';
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final javaPath = "${appDir.path}/bin/jdk/bin/java";

      _logger.info("Checking Java at: $javaPath");

      final javaFile = File(javaPath);
      if (!await javaFile.exists()) {
        _logger.error("Java binary not found at: $javaPath");
        
        await _popup.showErrorDialog(
          title: 'Java Not Found',
          message: 'Java binary does not exist at:\n$javaPath\n\nPlease run "Step 1: Download Java" first.',
        );
        return;
      }

      _logger.info("Running: java -version");
      
      // Show loading while testing
      _popup.showLoading(message: "Testing Java...", canMinimize: false);
      
      ProcessResult result;
      
      // Try Method 1: Direct execution
      try {
        _logger.info("Attempt 1: Direct execution");
        result = await Process.run(javaPath, ['-version']);
      } catch (e) {
        _logger.warning("Direct execution failed: $e");
        
        // Try Method 2: Via sh wrapper
        try {
          _logger.info("Attempt 2: Via sh wrapper");
          result = await Process.run('sh', ['$javaPath.sh', '-version']);
        } catch (e2) {
          _logger.warning("Sh wrapper failed: $e2");
          
          // Try Method 3: Via /system/bin/sh
          _logger.info("Attempt 3: Via system shell");
          result = await Process.run('/system/bin/sh', [javaPath, '-version']);
        }
      }

      final output = result.stderr.toString().trim();
      final stdoutput = result.stdout.toString().trim();

      // Close loading
      _popup.closeDialog();

      if (result.exitCode == 0) {
        final version = output.split('\n').first;
        _logger.success("Java test successful: $version");
        
        await _popup.showSuccessDialog(
          title: '✓ Java Works!',
          message: 'Java is working correctly!\n\nVersion: $version\n\nFull output:\n$output${stdoutput.isNotEmpty ? '\n\nStdout:\n$stdoutput' : ''}',
        );
        
        setState(() {
          _statusText = 'Java is working! ✓';
        });
      } else {
        _logger.error("Java test failed with exit code: ${result.exitCode}");
        
        await _popup.showErrorDialog(
          title: 'Java Error',
          message: 'Java returned an error.\n\nExit code: ${result.exitCode}\n\nStderr: $output\nStdout: $stdoutput',
        );
      }
    } catch (e) {
      _logger.error("Java test error: $e");
      _popup.closeDialog(); // Make sure to close loading if error
      
      await _popup.showErrorDialog(
        title: 'Test Failed',
        message: 'Failed to run Java test:\n\n$e\n\nCheck the debug console for details.',
      );
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  void _showResult(String title, String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(title),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: isError ? Colors.red : Colors.green,
            ),
            SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            message,
            style: TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PocketHost - Java Test'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.code,
                size: 80,
                color: Colors.blue,
              ),
              SizedBox(height: 24),
              
              // Storage permission indicator
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _hasStoragePermission ? Colors.green[50] : Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _hasStoragePermission ? Colors.green : Colors.orange,
                    width: 1,
                  ),
                ),
                child: InkWell(
                  onTap: () => AppPermissionHandler.showPermissionStatus(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hasStoragePermission ? Icons.check_circle : Icons.warning,
                        color: _hasStoragePermission ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        _hasStoragePermission 
                            ? 'Storage Access: OK' 
                            : 'Storage Access: Required',
                        style: TextStyle(
                          color: _hasStoragePermission ? Colors.green[900] : Colors.orange[900],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: _hasStoragePermission ? Colors.green[700] : Colors.orange[700],
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 16),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 32),
              
              // --- DOWNLOAD BUTTON ---
              ElevatedButton.icon(
                onPressed: (_isDownloading || _isTesting || !_hasStoragePermission) ? null : _downloadJava,
                icon: _isDownloading 
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : Icon(Icons.download),
                label: Text(_isDownloading ? 'Downloading...' : 'Step 1: Download Java'),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Colors.green.shade50,
                ),
              ),
              
              SizedBox(height: 16),

              // --- TEST BUTTON ---
              ElevatedButton.icon(
                onPressed: _isTesting || _isDownloading ? null : testJava,
                icon: _isTesting 
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.play_arrow),
                label: Text(_isTesting ? 'Testing...' : 'Step 2: Test Installation'),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
              
              SizedBox(height: 8),
              
              // --- DEBUG BUTTON ---
              TextButton.icon(
                onPressed: _checkFiles,
                icon: Icon(Icons.info_outline, size: 16),
                label: Text('Debug: Check Files', style: TextStyle(fontSize: 12)),
              ),
              
              SizedBox(height: 8),
              
              // --- CONSOLE BUTTON ---
              ElevatedButton.icon(
                onPressed: () => DebugLogger.showDebugConsole(context),
                icon: Icon(Icons.terminal),
                label: Text('View Debug Console'),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Colors.grey[850],
                  foregroundColor: Colors.greenAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom dialog that updates its content live
class _DownloadProgressDialog extends StatefulWidget {
  final double Function() getProgress;
  final String Function() getMessage;
  final VoidCallback onMinimize;

  const _DownloadProgressDialog({
    required this.getProgress,
    required this.getMessage,
    required this.onMinimize,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  @override
  void initState() {
    super.initState();
    // Rebuild every 100ms to show live progress
    _startPeriodicUpdate();
  }

  void _startPeriodicUpdate() {
    Future.delayed(Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {});
        _startPeriodicUpdate();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.getProgress();
    final message = widget.getMessage();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title bar with minimize button
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 12, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Downloading Java',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.minimize, size: 20),
                  onPressed: widget.onMinimize,
                  tooltip: "Minimize",
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, style: TextStyle(fontSize: 16)),
                SizedBox(height: 16),
                LinearProgressIndicator(value: progress, minHeight: 8),
                SizedBox(height: 8),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}