// lib/main.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:pocket_server/services/java_downloader.dart';

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

  /// Method to download and install Java environment
  Future<void> _downloadJava() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Preparing download...';
    });

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Row(
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(width: 16),
              Text('Downloading Java'),
            ],
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              // Update the dialog when progress changes
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_downloadStatus),
                  SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _downloadProgress,
                    minHeight: 8,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      final downloader = JavaDownloader();
      
      // Set up progress callback
      downloader.onProgress = (progress) {
        setState(() {
          _downloadProgress = progress;
          _downloadStatus = 'Downloading JDK... ${(progress * 100).toStringAsFixed(0)}%';
        });
      };

      await downloader.initEnvironment();
      
      // Close progress dialog
      Navigator.pop(context);
      
      _showResult(
        '✓ Success!', 
        'Java has been downloaded and installed successfully.\n\nYou can now test the installation.',
        isError: false,
      );
      
      setState(() {
        _statusText = 'Java installed successfully! Ready to test.';
      });
    } catch (e) {
      // Close progress dialog
      Navigator.pop(context);
      
      _showResult(
        'Download Failed', 
        'Error during download:\n\n$e\n\nPlease check your internet connection and try again.',
        isError: true,
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

      final javaFile = File(javaPath);
      if (!await javaFile.exists()) {
        _showResult(
          'Java Not Found',
          'Java binary does not exist at:\n$javaPath\n\nPlease run "Step 1: Download Java" first.',
          isError: true,
        );
        return;
      }

      // Run java -version
      final result = await Process.run(javaPath, ['-version']);

      final output = result.stderr.toString().trim();
      final stdoutput = result.stdout.toString().trim();

      if (result.exitCode == 0) {
        final version = output.split('\n').first;
        _showResult(
          '✓ Java Works!',
          'Java is working correctly!\n\nVersion: $version\n\nFull output:\n$output${stdoutput.isNotEmpty ? '\n\nStdout:\n$stdoutput' : ''}',
          isError: false,
        );
        
        setState(() {
          _statusText = 'Java is working! ✓';
        });
      } else {
        _showResult(
          'Java Error',
          'Java returned an error.\n\nExit code: ${result.exitCode}\n\nStderr: $output\nStdout: $stdoutput',
          isError: true,
        );
      }
    } catch (e) {
      _showResult(
        'Test Failed',
        'Failed to run Java test:\n\n$e',
        isError: true,
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
            ],
          ),
        ),
      ),
    );
  }
}