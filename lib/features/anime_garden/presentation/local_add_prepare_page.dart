import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_dialog.dart';
import '../../bangumi/data/bangumi_repository.dart';
import 'anime_garden_bindings.dart';
import 'local_add_prepare_controller.dart';

Future<void> showLocalAddDialog(
  BuildContext context, {
  required BangumiSubject subject,
}) async {
  LocalAddPrepareBinding(subject: subject).dependencies();
  final controller = Get.find<LocalAddPrepareController>();
  try {
    final prepared = await controller.prepare();
    if (!prepared || !context.mounted) return;
    await showAppDialog<bool>(const LocalAddPreparePage());
  } finally {
    await Get.delete<LocalAddPrepareController>();
  }
}

class LocalAddPreparePage extends GetView<LocalAddPrepareController> {
  const LocalAddPreparePage({super.key});

  @override
  Widget build(BuildContext context) {
    final id = controller.folderId.value!;
    return AlertDialog(
      title: const Text('添加番剧'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('请将番剧视频文件放入以下目录：'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              'data/$id/',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => AppDialog.dismiss(context, false),
          child: const Text('取消'),
        ),
        Obx(
          () => FilledButton.icon(
            onPressed: controller.refreshing.value
                ? null
                : () => controller.refreshFiles(context),
            icon: controller.refreshing.value
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(controller.refreshing.value ? '检测中...' : '已放入文件，开始匹配'),
          ),
        ),
      ],
    );
  }
}
