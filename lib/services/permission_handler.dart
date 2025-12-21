// lib/services/permission_handler.dart
import 'package:permission_handler/permission_handler.dart';

class AppPermissionHandler {
  static Future<bool> checkAndRequest() async {
    // 1. Request ignore battery optimizations (Crucial for background servers)
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // 2. Standard Storage (for picking plugins/mods)
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }

    // Return true if critical ones are handled
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }
}