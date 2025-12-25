// lib/services/popup_service.dart
import 'package:flutter/material.dart';

/// Centralized popup/dialog system for PocketHost
/// Handles all popups, dialogs, snackbars, and overlays
class PopupService {
  static final PopupService _instance = PopupService._internal();
  factory PopupService() => _instance;
  PopupService._internal();

  BuildContext? _globalContext;
  OverlayEntry? _minimizedOverlay;
  Widget? _minimizedContent;
  String? _minimizedTitle;

  void setContext(BuildContext context) {
    _globalContext = context;
  }

  // ============================================================
  // MINIMIZATION SYSTEM
  // ============================================================

  void _minimize(String title, Widget content) {
    if (_globalContext == null) return;

    _minimizedTitle = title;
    _minimizedContent = content;

    // Remove existing minimized overlay if any
    _minimizedOverlay?.remove();

    // Create floating button overlay
    _minimizedOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        right: 16,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(30),
          child: InkWell(
            onTap: () {
              _restore();
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
                  Icon(Icons.open_in_full, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 150),
                    child: Text(
                      title,
                      style: TextStyle(color: Colors.white, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      _minimizedOverlay?.remove();
                      _minimizedOverlay = null;
                      _minimizedContent = null;
                      _minimizedTitle = null;
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

    Overlay.of(_globalContext!).insert(_minimizedOverlay!);
  }

  void _restore() {
    if (_minimizedContent == null || _globalContext == null) return;

    final content = _minimizedContent!;
    final title = _minimizedTitle ?? "Dialog";

    // Remove minimized button
    _minimizedOverlay?.remove();
    _minimizedOverlay = null;

    // Show the dialog again
    showDialog(
      context: _globalContext!,
      barrierDismissible: false,
      builder: (context) => _MinimizableDialog(
        title: title,
        content: content,
        onMinimize: () {
          Navigator.pop(context);
          _minimize(title, content);
        },
      ),
    );
  }

  // ============================================================
  // SNACKBARS - Quick notifications at bottom of screen
  // ============================================================

  /// Show a basic snackbar
  void showSnackbar(
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Color? backgroundColor,
    Color? textColor,
  }) {
    if (_globalContext == null) return;

    ScaffoldMessenger.of(_globalContext!).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: textColor)),
        duration: duration,
        backgroundColor: backgroundColor,
        action: action,
      ),
    );
  }

  /// Success snackbar (green)
  void showSuccess(String message, {Duration? duration}) {
    showSnackbar(
      message,
      duration: duration ?? Duration(seconds: 2),
      backgroundColor: Colors.green[700],
      textColor: Colors.white,
    );
  }

  /// Error snackbar (red)
  void showError(String message, {Duration? duration}) {
    showSnackbar(
      message,
      duration: duration ?? Duration(seconds: 4),
      backgroundColor: Colors.red[700],
      textColor: Colors.white,
    );
  }

  /// Warning snackbar (orange)
  void showWarning(String message, {Duration? duration}) {
    showSnackbar(
      message,
      duration: duration ?? Duration(seconds: 3),
      backgroundColor: Colors.orange[700],
      textColor: Colors.white,
    );
  }

  /// Info snackbar (blue)
  void showInfo(String message, {Duration? duration}) {
    showSnackbar(
      message,
      duration: duration ?? Duration(seconds: 3),
      backgroundColor: Colors.blue[700],
      textColor: Colors.white,
    );
  }

  // ============================================================
  // DIALOGS - Modal popups in center of screen
  // ============================================================

  /// Show a custom dialog with full control and minimize option
  Future<T?> showCustomDialog<T>({
    required Widget content,
    String? title,
    List<Widget>? actions,
    bool barrierDismissible = true,
    bool canMinimize = false,
    Color? backgroundColor,
    double? width,
    double? height,
    ShapeBorder? shape,
    EdgeInsets? contentPadding,
    EdgeInsets? titlePadding,
    TextStyle? titleStyle,
  }) {
    if (_globalContext == null) throw Exception("Context not set");

    if (!canMinimize) {
      // Standard dialog without minimize
      return showDialog<T>(
        context: _globalContext!,
        barrierDismissible: barrierDismissible,
        builder: (context) => Dialog(
          backgroundColor: backgroundColor,
          shape: shape ?? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: width,
            height: height,
            child: Column(
              mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (title != null)
                  Padding(
                    padding: titlePadding ?? EdgeInsets.all(20),
                    child: Text(
                      title,
                      style: titleStyle ?? TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Flexible(
                  child: Padding(
                    padding: contentPadding ?? EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: content,
                  ),
                ),
                if (actions != null && actions.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Minimizable dialog
      final dialogContent = Container(
        width: width,
        height: height,
        child: Column(
          mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Flexible(
              child: Padding(
                padding: contentPadding ?? EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: content,
              ),
            ),
            if (actions != null && actions.isNotEmpty)
              Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ),
          ],
        ),
      );

      return showDialog<T>(
        context: _globalContext!,
        barrierDismissible: barrierDismissible,
        builder: (context) => _MinimizableDialog(
          title: title ?? "Dialog",
          content: dialogContent,
          backgroundColor: backgroundColor,
          shape: shape,
          onMinimize: () {
            Navigator.pop(context);
            _minimize(title ?? "Dialog", dialogContent);
          },
        ),
      );
    }
  }

  /// Standard alert dialog (title, message, buttons)
  Future<bool?> showAlert({
    required String title,
    required String message,
    String confirmText = "OK",
    String? cancelText,
    Color? confirmColor,
    Color? cancelColor,
    IconData? icon,
    Color? iconColor,
    bool canMinimize = false,
  }) {
    if (_globalContext == null) throw Exception("Context not set");

    final dialogContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: iconColor, size: 48),
          SizedBox(height: 16),
        ],
        Text(message),
        SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (cancelText != null)
              TextButton(
                onPressed: () => Navigator.pop(_globalContext!, false),
                child: Text(cancelText, style: TextStyle(color: cancelColor)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(_globalContext!, true),
              child: Text(confirmText, style: TextStyle(color: confirmColor)),
            ),
          ],
        ),
      ],
    );

    if (!canMinimize) {
      return showDialog<bool>(
        context: _globalContext!,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: dialogContent,
        ),
      );
    } else {
      return showDialog<bool>(
        context: _globalContext!,
        builder: (context) => _MinimizableDialog(
          title: title,
          content: dialogContent,
          onMinimize: () {
            Navigator.pop(context);
            _minimize(title, dialogContent);
          },
        ),
      );
    }
  }

  /// Confirmation dialog (Yes/No)
  Future<bool> showConfirmation({
    required String title,
    required String message,
    String confirmText = "Yes",
    String cancelText = "No",
    bool isDangerous = false,
  }) async {
    final result = await showAlert(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      confirmColor: isDangerous ? Colors.red : null,
      icon: isDangerous ? Icons.warning : Icons.help_outline,
      iconColor: isDangerous ? Colors.red : Colors.blue,
    );
    return result ?? false;
  }

  /// Success dialog
  Future<void> showSuccessDialog({
    required String title,
    required String message,
  }) {
    return showAlert(
      title: title,
      message: message,
      icon: Icons.check_circle,
      iconColor: Colors.green,
      confirmColor: Colors.green,
    );
  }

  /// Error dialog
  Future<void> showErrorDialog({
    required String title,
    required String message,
  }) {
    return showAlert(
      title: title,
      message: message,
      icon: Icons.error,
      iconColor: Colors.red,
      confirmColor: Colors.red,
    );
  }

  // ============================================================
  // LOADING DIALOGS - Non-dismissible progress indicators
  // ============================================================

  /// Show a minimizable loading dialog
  void showLoading({
    String message = "Loading...",
    bool barrierDismissible = false,
    bool canMinimize = true,
  }) {
    if (_globalContext == null) return;

    final loadingContent = Padding(
      padding: EdgeInsets.all(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text(message)),
        ],
      ),
    );

    if (!canMinimize) {
      showDialog(
        context: _globalContext!,
        barrierDismissible: barrierDismissible,
        builder: (context) => PopScope(
          canPop: barrierDismissible,
          child: Dialog(child: loadingContent),
        ),
      );
    } else {
      showDialog(
        context: _globalContext!,
        barrierDismissible: barrierDismissible,
        builder: (context) => _MinimizableDialog(
          title: "Loading",
          content: loadingContent,
          onMinimize: () {
            Navigator.pop(context);
            _minimize(message, loadingContent);
          },
        ),
      );
    }
  }

  /// Show a minimizable loading dialog with progress percentage
  void showLoadingWithProgress({
    required String message,
    required double progress,
    bool barrierDismissible = false,
    bool canMinimize = true,
  }) {
    if (_globalContext == null) return;

    final progressContent = Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: TextStyle(fontSize: 16)),
          SizedBox(height: 16),
          LinearProgressIndicator(value: progress),
          SizedBox(height: 8),
          Text('${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );

    if (!canMinimize) {
      showDialog(
        context: _globalContext!,
        barrierDismissible: barrierDismissible,
        builder: (context) => PopScope(
          canPop: barrierDismissible,
          child: Dialog(child: progressContent),
        ),
      );
    } else {
      showDialog(
        context: _globalContext!,
        barrierDismissible: barrierDismissible,
        builder: (context) => _MinimizableDialog(
          title: message,
          content: progressContent,
          onMinimize: () {
            Navigator.pop(context);
            _minimize(message, progressContent);
          },
        ),
      );
    }
  }

  /// Close the topmost dialog (useful for closing loading dialogs)
  void closeDialog() {
    if (_globalContext != null) {
      Navigator.of(_globalContext!).pop();
    }
  }

  /// Close minimized overlay
  void closeMinimized() {
    _minimizedOverlay?.remove();
    _minimizedOverlay = null;
    _minimizedContent = null;
    _minimizedTitle = null;
  }

  // ============================================================
  // BOTTOM SHEETS - Slide up from bottom
  // ============================================================

  /// Show a bottom sheet
  Future<T?> showBottomSheet<T>({
    required Widget content,
    String? title,
    double? height,
    bool isDismissible = true,
    bool enableDrag = true,
    Color? backgroundColor,
    ShapeBorder? shape,
  }) {
    if (_globalContext == null) throw Exception("Context not set");

    return showModalBottomSheet<T>(
      context: _globalContext!,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor ?? Colors.white,
      shape: shape ?? RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: height,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (enableDrag)
              Container(
                margin: EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            if (title != null)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  title,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            Flexible(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: content,
              ),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INPUT DIALOGS - Get user input
  // ============================================================

  /// Show a text input dialog
  Future<String?> showInputDialog({
    required String title,
    String? message,
    String? hintText,
    String? initialValue,
    String confirmText = "OK",
    String cancelText = "Cancel",
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    if (_globalContext == null) throw Exception("Context not set");

    final controller = TextEditingController(text: initialValue);
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: _globalContext!,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[
                Text(message),
                SizedBox(height: 16),
              ],
              TextFormField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: OutlineInputBorder(),
                ),
                keyboardType: keyboardType,
                maxLines: maxLines,
                autofocus: true,
                validator: validator,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? true) {
                Navigator.pop(context, controller.text);
              }
            },
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOAST - Very brief notification overlay
  // ============================================================

  /// Show a toast message (using OverlayEntry for custom positioning)
  void showToast(
    String message, {
    Duration duration = const Duration(seconds: 2),
    ToastPosition position = ToastPosition.bottom,
    Color backgroundColor = Colors.black87,
    Color textColor = Colors.white,
  }) {
    if (_globalContext == null) return;

    final overlay = Overlay.of(_globalContext!);
    final overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        position: position,
        backgroundColor: backgroundColor,
        textColor: textColor,
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(duration, () => overlayEntry.remove());
  }
}

// ============================================================
// MINIMIZABLE DIALOG WIDGET
// ============================================================

class _MinimizableDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback onMinimize;
  final Color? backgroundColor;
  final ShapeBorder? shape;

  const _MinimizableDialog({
    required this.title,
    required this.content,
    required this.onMinimize,
    this.backgroundColor,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: backgroundColor,
      shape: shape ?? RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.minimize, size: 20),
                  onPressed: onMinimize,
                  tooltip: "Minimize",
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
          ),
          // Content
          content,
        ],
      ),
    );
  }
}

// ============================================================
// TOAST WIDGET
// ============================================================

enum ToastPosition {
  top,
  center,
  bottom,
}

class _ToastWidget extends StatelessWidget {
  final String message;
  final ToastPosition position;
  final Color backgroundColor;
  final Color textColor;

  const _ToastWidget({
    required this.message,
    required this.position,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: position == ToastPosition.top ? 50 : null,
      bottom: position == ToastPosition.bottom ? 50 : null,
      left: 20,
      right: 20,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}