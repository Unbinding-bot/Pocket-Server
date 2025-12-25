// lib/main.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:pocket_server/services/java_downloader.dart';
import 'package:pocket_server/services/debug_logger.dart';
import 'package:pocket_server/services/popup_service.dart';

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
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  final _logger = DebugLogger();
  final _popup = PopupService();

  @override
  void initState() {
    super.initState();
    // Set global context for both services after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logger.setContext(context);
      _popup.setContext(context);
    });
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

    // Show minimizable loading dialog
    _popup.showLoadingWithProgress(
      message: 'Preparing download...',
      progress: 0.0,
      canMinimize: true,
    );

    try {
      final downloader = JavaDownloader();
      
      // Set up progress callback
      downloader.onProgress = (progress) {
        setState(() {
          _downloadProgress = progress;
          _downloadStatus = 'Downloading JDK... ${(progress * 100).toStringAsFixed(0)}%';
        });
        
        // Update the dialog
        _popup.closeDialog();
        _popup.showLoadingWithProgress(
          message: 'Downloading JDK... ${(progress * 100).toStringAsFixed(0)}%',
          progress: progress,
          canMinimize: true,
        );
      };

      _logger.info("Starting Java download...");
      await downloader.initEnvironment();
      
      // Close loading dialog
      _popup.closeDialog();
      _popup.closeMinimized(); // Also close if minimized
      
      // Show success
      _popup.showSuccessDialog(
        title: '✓ Installation Complete', 
        message: 'Java has been downloaded and installed successfully.\n\nYou can now test the installation.',
      );
      
      setState(() {
        _statusText = 'Java installed successfully! Ready to test.';
      });
    } catch (e) {
      _logger.error("Download failed: $e");
      
      // Close loading dialog
      _popup.closeDialog();
      _popup.closeMinimized();
      
      // Show error
      _popup.showErrorDialog(
        title: 'Download Failed', 
        message: 'Error during download:\n\n$e\n\nCheck the debug console for details.',
      );
    } finally {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
    }
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
      
      // Run java -version
      final result = await Process.run(javaPath, ['-version']);

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
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 32),
              
              // --- DOWNLOAD BUTTON ---
              ElevatedButton.icon(
                onPressed: _isDownloading || _isTesting ? null : _downloadJava,
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