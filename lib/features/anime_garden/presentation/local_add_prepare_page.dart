import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../anime/data/anime_list_store.dart';
import '../../../core/network/app_network_error.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../data/local_add_coordinator.dart';
import 'anime_garden_episode_match_page.dart';

Future<void> showLocalAddDialog(
  BuildContext context, {
  required BangumiSubject subject,
}) async {
  final coordinator = LocalAddCoordinator();

  String? folderId;
  try {
    folderId = await coordinator.createFolder(subject.id);
  } catch (error) {
    if (context.mounted) {
      await showErrorDialog(
        title: '创建文件夹失败',
        message: errorMessageOf(error),
        error: error,
      );
    }
    return;
  }

  if (!context.mounted) return;

  await showAppDialog<bool>(
    StatefulBuilder(
      builder: (context, setState) {
        var refreshing = false;
        final id = folderId!;

        Future<void> refreshFiles() async {
          setState(() => refreshing = true);
          try {
            final files = await coordinator.listFiles(id);
            if (!context.mounted) return;

            if (files.isEmpty) {
              await showErrorDialog(
                title: '未找到视频文件',
                message: '请将番剧视频文件放入 data/$id/ 目录后重试。',
              );
              return;
            }

            final bangumiEpisodes = await coordinator.getBangumiEpisodes(
              subject.id,
            );
            if (!context.mounted) return;

            AppDialog.dismiss(context, true);

            Get.to(
              () => AnimeGardenEpisodeMatchPage(
                subject: subject,
                files: files,
                bangumiEpisodes: bangumiEpisodes,
                animeListStore: Get.find<AnimeListStore>(),
                pageTitle: '匹配 Episode',
                onSave: (episodes) => coordinator.submitLocalAdd(
                  subject: subject,
                  folderId: id,
                  episodes: episodes,
                ),
              ),
            );
          } catch (error) {
            if (!context.mounted) return;
            await showErrorDialog(
              title: '读取文件失败',
              message: errorMessageOf(error),
              error: error,
            );
          } finally {
            if (context.mounted) {
              setState(() => refreshing = false);
            }
          }
        }

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
            FilledButton.icon(
              onPressed: refreshing ? null : refreshFiles,
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(refreshing ? '检测中...' : '已放入文件，开始匹配'),
            ),
          ],
        );
      },
    ),
  );
}
