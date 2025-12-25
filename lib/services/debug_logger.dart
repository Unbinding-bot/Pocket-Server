// lib/services/debug_logger.dart
import 'package:flutter/material.dart';

/// Centralized logging system for PocketHost
/// Replaces print() statements and provides UI feedback
class DebugLogger {
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  // Store all log messages
  final List<LogEntry> _logs = [];
  
  // Callbacks to notify UI when logs change
  final List<VoidCallback> _listeners = [];

  // Optional: Global context for showing snackbars
  BuildContext? _globalContext;

  void setContext(BuildContext context) {
    _globalContext = context;
  }

  /// Add a log entry
  void log(String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(
      message: message,
      level: level,
      timestamp: DateTime.now(),
    );
    
    _logs.add(entry);
    
    // Keep only last 500 logs to prevent memory issues
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    
    // Print to console for debugging
    print('[${level.name.toUpperCase()}] $message');
    
    // Show snackbar for errors and warnings
    if (_globalContext != null && 
        (level == LogLevel.error || level == LogLevel.warning)) {
      _showSnackbar(message, level);
    }
    
    // Notify listeners
    for (var listener in _listeners) {
      listener();
    }
  }

  void info(String message) => log(message, level: LogLevel.info);
  void success(String message) => log(message, level: LogLevel.success);
  void warning(String message) => log(message, level: LogLevel.warning);
  void error(String message) => log(message, level: LogLevel.error);

  void _showSnackbar(String message, LogLevel level) {
    if (_globalContext == null) return;
    
    ScaffoldMessenger.of(_globalContext!).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: level == LogLevel.error 
            ? Colors.red 
            : Colors.orange,
        duration: Duration(seconds: 3),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            showDebugConsole(_globalContext!);
          },
        ),
      ),
    );
  }

  /// Get all logs
  List<LogEntry> get logs => List.unmodifiable(_logs);

  /// Add listener for log updates
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Clear all logs
  void clear() {
    _logs.clear();
    for (var listener in _listeners) {
      listener();
    }
  }

  /// Show debug console dialog
  static void showDebugConsole(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DebugConsoleScreen(),
      ),
    );
  }
}

enum LogLevel {
  info,
  success,
  warning,
  error,
}

class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.level,
    required this.timestamp,
  });

  String get timeString {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }

  Color get color {
    switch (level) {
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.success:
        return Colors.green;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  IconData get icon {
    switch (level) {
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.success:
        return Icons.check_circle_outline;
      case LogLevel.warning:
        return Icons.warning_amber;
      case LogLevel.error:
        return Icons.error_outline;
    }
  }
}

/// Full-screen debug console
class DebugConsoleScreen extends StatefulWidget {
  const DebugConsoleScreen({super.key});

  @override
  State<DebugConsoleScreen> createState() => _DebugConsoleScreenState();
}

class _DebugConsoleScreenState extends State<DebugConsoleScreen> {
  final _logger = DebugLogger();
  final _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _logger.addListener(_onLogsUpdated);
    
    // Auto-scroll to bottom when new logs arrive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _logger.removeListener(_onLogsUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogsUpdated() {
    setState(() {});
    
    // Auto-scroll to bottom
    if (_autoScroll && _scrollController.hasClients) {
      Future.delayed(Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = _logger.logs;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Debug Console'),
        backgroundColor: Colors.grey[900],
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.arrow_downward : Icons.arrow_downward_outlined),
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
            },
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
          ),
          IconButton(
            icon: Icon(Icons.delete_outline),
            onPressed: () {
              _logger.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Console cleared')),
              );
            },
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.terminal, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No logs yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.all(8),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return _LogTile(log: log);
              },
            ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry log;

  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            log.timeString,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(width: 8),
          
          // Icon
          Icon(log.icon, size: 16, color: log.color),
          SizedBox(width: 8),
          
          // Message
          Expanded(
            child: SelectableText(
              log.message,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}