import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<T?> showAppDialog<T>(Widget child) =>
    Get.dialog<T>(_AppDialog(child: child), barrierDismissible: false);

class AppDialog extends InheritedWidget {
  const AppDialog({super.key, required this.onDismiss, required super.child});

  final ValueChanged<Object?> onDismiss;

  static void dismiss<T>(BuildContext context, [T? result]) {
    context.dependOnInheritedWidgetOfExactType<AppDialog>()?.onDismiss(result);
  }

  @override
  bool updateShouldNotify(AppDialog oldWidget) =>
      onDismiss != oldWidget.onDismiss;
}

class _AppDialog extends StatefulWidget {
  const _AppDialog({required this.child});

  final Widget child;

  @override
  State<_AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<_AppDialog> {
  var _isClosing = false;

  void _close(Object? result) {
    if (_isClosing) return;
    _isClosing = true;
    Get.back(result: result);
  }

  @override
  Widget build(BuildContext context) =>
      AppDialog(onDismiss: _close, child: widget.child);
}
