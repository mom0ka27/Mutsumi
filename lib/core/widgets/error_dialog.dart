import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> showErrorDialog({
  required String title,
  required String message,
}) => Get.dialog<void>(
  AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [FilledButton(onPressed: Get.back, child: const Text('知道了'))],
  ),
);
