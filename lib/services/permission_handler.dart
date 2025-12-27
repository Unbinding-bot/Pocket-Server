// lib/services/permission_handler.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:PocketServer/services/debug_logger.dart';
import 'package:PocketServer/services/popup_service.dart';

class AppPermissionHandler {
  static final _logger = DebugLogger();
  static final _popup = PopupService();

  /// Main permission check with automatic popups
  /// Returns true if all critical permissions granted
  static Future<bool> checkAndRequestWithUI(BuildContext context) async {
    _popup.setContext(context);
    
    // First check if already granted
    if (await arePermissionsGranted()) {
      _logger.success("All permissions already granted");
      return true;
    }

    // Show explanation dialog
    final shouldRequest = await _popup.showConfirmation(
      title: "Permissions Required",
      message: "PocketHost needs the following permissions:\n\n"
          "🔋 Ignore Battery Optimization (Critical)\n"
          "• Keep server running in background\n"
          "• Prevent Android from killing the app\n"
          "• Essential for 24/7 server hosting\n\n"
          "📁 Storage Access (Optional)\n"
          "• For importing plugins/mods from Downloads\n"
          "• Server files are stored in app's private storage\n"
          "• Not required for basic functionality\n\n"
          "Note: Battery optimization is the critical permission.\n"
          "Storage can be skipped if not importing files.",
      confirmText: "Grant Permissions",
      cancelText: "Not Now",
    );

    if (!shouldRequest) {
      _logger.warning("User declined to grant permissions");
      _popup.showWarning("Permissions are required for the app to work properly");
      return false;
    }

    // Request permissions with progress
    _popup.showLoading(message: "Requesting permissions...", canMinimize: false);
    
    final result = await _requestAllPermissions();
    
    _popup.closeDialog();

    // Show result
    if (result.allGranted) {
      await _popup.showSuccessDialog(
        title: "✓ Permissions Granted",
        message: "All permissions have been granted successfully!\n\nYou can now use all features of PocketHost.",
      );
      return true;
    } else if (result.someGranted) {
      await _popup.showAlert(
        title: "Partial Permissions",
        message: "Some permissions were granted:\n\n"
            "${result.granted.map((p) => '✓ $p').join('\n')}\n\n"
            "Missing permissions:\n"
            "${result.denied.map((p) => '✗ $p').join('\n')}\n\n"
            "The app may not work correctly without all permissions.",
        icon: Icons.warning,
        iconColor: Colors.orange,
      );
      return result.criticalGranted;
    } else if (result.permanentlyDenied.isNotEmpty) {
      final shouldOpenSettings = await _popup.showConfirmation(
        title: "Permissions Denied",
        message: "Some permissions were permanently denied:\n\n"
            "${result.permanentlyDenied.map((p) => '✗ $p').join('\n')}\n\n"
            "Please grant them manually in app settings.",
        confirmText: "Open Settings",
        cancelText: "Cancel",
        isDangerous: false,
      );
      
      if (shouldOpenSettings) {
        await openAppSettings();
      }
      return false;
    } else {
      await _popup.showErrorDialog(
        title: "Permissions Required",
        message: "Permissions were denied. The app requires these permissions to function.\n\n"
            "Please try again or grant them manually in Settings → Apps → PocketHost → Permissions.",
      );
      return false;
    }
  }

  /// Silent permission check and request (no UI)
  static Future<bool> checkAndRequest() async {
    return (await _requestAllPermissions()).allGranted;
  }

  /// Request all permissions and return detailed results
  static Future<PermissionResult> _requestAllPermissions() async {
    _logger.info("Starting permission request process...");
    
    final List<String> granted = [];
    final List<String> denied = [];
    final List<String> permanentlyDenied = [];

    // 1. Battery Optimization (Critical)
    _logger.info("Checking battery optimization...");
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    
    if (batteryStatus.isDenied) {
      _logger.info("Requesting battery optimization permission...");
      final result = await Permission.ignoreBatteryOptimizations.request();
      
      if (result.isGranted) {
        _logger.success("✓ Battery optimization granted");
        granted.add("Battery Optimization");
      } else if (result.isPermanentlyDenied) {
        _logger.error("✗ Battery optimization permanently denied");
        permanentlyDenied.add("Battery Optimization");
      } else {
        _logger.warning("✗ Battery optimization denied");
        denied.add("Battery Optimization");
      }
    } else if (batteryStatus.isGranted) {
      _logger.success("✓ Battery optimization already granted");
      granted.add("Battery Optimization");
    }

    // 2. Storage - Try multiple approaches for different Android versions
    _logger.info("Checking storage permission...");
    
    // For Android 11+ (API 30+), try manageExternalStorage first
    final manageStorageStatus = await Permission.manageExternalStorage.status;
    
    if (manageStorageStatus.isDenied) {
      _logger.info("Requesting manage external storage (Android 11+)...");
      final result = await Permission.manageExternalStorage.request();
      
      if (result.isGranted) {
        _logger.success("✓ Manage external storage granted");
        granted.add("Storage Access");
        granted.add("Manage External Storage");
      } else {
        _logger.warning("✗ Manage external storage denied, trying standard storage...");
        
        // Fall back to standard storage permission
        final storageStatus = await Permission.storage.status;
        
        if (storageStatus.isDenied) {
          _logger.info("Requesting standard storage permission...");
          final storageResult = await Permission.storage.request();
          
          if (storageResult.isGranted) {
            _logger.success("✓ Storage granted");
            granted.add("Storage Access");
          } else if (storageResult.isPermanentlyDenied) {
            _logger.error("✗ Storage permanently denied");
            permanentlyDenied.add("Storage Access");
          } else {
            _logger.warning("✗ Storage denied");
            denied.add("Storage Access");
          }
        } else if (storageStatus.isGranted) {
          _logger.success("✓ Storage already granted");
          granted.add("Storage Access");
        } else {
          _logger.warning("✗ Storage access not available");
          denied.add("Storage Access");
        }
      }
    } else if (manageStorageStatus.isGranted) {
      _logger.success("✓ Manage external storage already granted");
      granted.add("Storage Access");
      granted.add("Manage External Storage");
    } else {
      // Android 10 or below - use standard storage permission
      final storageStatus = await Permission.storage.status;
      
      if (storageStatus.isDenied) {
        _logger.info("Requesting storage permission...");
        final result = await Permission.storage.request();
        
        if (result.isGranted) {
          _logger.success("✓ Storage granted");
          granted.add("Storage Access");
        } else if (result.isPermanentlyDenied) {
          _logger.error("✗ Storage permanently denied");
          permanentlyDenied.add("Storage Access");
        } else {
          _logger.warning("✗ Storage denied");
          denied.add("Storage Access");
        }
      } else if (storageStatus.isGranted) {
        _logger.success("✓ Storage already granted");
        granted.add("Storage Access");
      }
    }

    final result = PermissionResult(
      granted: granted,
      denied: denied,
      permanentlyDenied: permanentlyDenied,
    );

    _logger.info("Permission result: ${result.summary}");
    return result;
  }

  /// Check if all critical permissions are already granted (no popup)
  static Future<bool> arePermissionsGranted() async {
    final batteryOpt = await Permission.ignoreBatteryOptimizations.isGranted;
    
    // Check either manage external storage OR standard storage
    final manageStorage = await Permission.manageExternalStorage.isGranted;
    final storage = await Permission.storage.isGranted;
    
    return batteryOpt && (manageStorage || storage);
  }

  /// Get detailed permission status
  static Future<Map<String, bool>> getPermissionStatus() async {
    return {
      'batteryOptimization': await Permission.ignoreBatteryOptimizations.isGranted,
      'storage': await Permission.storage.isGranted,
      'manageExternalStorage': await Permission.manageExternalStorage.isGranted,
    };
  }

  /// Show current permission status in a dialog
  static Future<void> showPermissionStatus(BuildContext context) async {
    _popup.setContext(context);
    final status = await getPermissionStatus();
    
    final message = status.entries.map((e) {
      final icon = e.value ? '✓' : '✗';
      final name = e.key
          .replaceAll(RegExp(r'([A-Z])'), ' \$1')
          .trim()
          .split(' ')
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .join(' ');
      return '$icon $name';
    }).join('\n');

    await _popup.showAlert(
      title: "Permission Status",
      message: message,
      icon: status.values.every((v) => v) ? Icons.check_circle : Icons.warning,
      iconColor: status.values.every((v) => v) ? Colors.green : Colors.orange,
    );
  }
}

/// Result of permission request
class PermissionResult {
  final List<String> granted;
  final List<String> denied;
  final List<String> permanentlyDenied;

  PermissionResult({
    required this.granted,
    required this.denied,
    required this.permanentlyDenied,
  });

  bool get allGranted => denied.isEmpty && permanentlyDenied.isEmpty && granted.isNotEmpty;
  bool get someGranted => granted.isNotEmpty;
  bool get criticalGranted => granted.contains("Battery Optimization");

  String get summary => 
      "Granted: ${granted.length}, Denied: ${denied.length}, Permanently Denied: ${permanentlyDenied.length}";
}