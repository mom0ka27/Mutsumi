import 'package:flutter/material.dart';

import '../network/app_network_error.dart';
import 'app_dialog.dart';

Future<void> showErrorDialog({
  required String title,
  required String message,
  Object? error,
}) => showAppDialog<void>(
  AlertDialog(
    title: Text(title),
    content: _ErrorDialogContent(
      message: message,
      details: error == null ? null : errorInfoOf(error).details,
    ),
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

class _ErrorDialogContent extends StatelessWidget {
  const _ErrorDialogContent({required this.message, this.details});

  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (details != null) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('详细原因'),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: SelectableText(
                    details!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

Future<void> showInfoDialog({required String title, required String message}) =>
    showAppDialog<void>(
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
