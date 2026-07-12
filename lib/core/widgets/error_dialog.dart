import 'package:flutter/material.dart';

import 'app_dialog.dart';

Future<void> showErrorDialog({
  required String title,
  required String message,
}) => showAppDialog<void>(
  AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      Builder(
        builder: (context) => FilledButton(
          onPressed: () => AppDialog.dismiss(context),
          child: const Text('知道了'),
        ),
      ),
    ],
  ),
);
