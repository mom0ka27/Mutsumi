import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../anime/data/anime_list_store.dart';
import '../../anime/data/anime_models.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../data/local_add_coordinator.dart';
import 'anime_garden_bindings.dart';
import 'anime_garden_episode_match_page.dart';

class LocalAddPrepareController extends GetxController {
  LocalAddPrepareController({
    required this.subject,
    required this.coordinator,
    required this.animeListStore,
  });

  final BangumiSubject subject;
  final LocalAddCoordinator coordinator;
  final AnimeListStore animeListStore;
  final folderId = RxnString();
  final refreshing = false.obs;

  Future<bool> prepare() async {
    try {
      folderId.value = await coordinator.createFolder(subject.id);
      return true;
    } catch (error) {
      if (!isClosed) {
        await showErrorDialog(
          title: '创建文件夹失败',
          message: errorMessageOf(error),
          error: error,
        );
      }
      return false;
    }
  }

  Future<void> refreshFiles(BuildContext context) async {
    final id = folderId.value;
    if (id == null || refreshing.value) return;

    List<QBittorrentFile>? files;
    List<BangumiEpisode>? bangumiEpisodes;
    refreshing.value = true;
    try {
      files = await coordinator.listFiles(id);
      if (isClosed) return;

      if (files.isEmpty) {
        await showErrorDialog(
          title: '未找到视频文件',
          message: '请将番剧视频文件放入 data/$id/ 目录后重试。',
        );
        return;
      }

      bangumiEpisodes = await coordinator.getBangumiEpisodes(subject.id);
    } catch (error) {
      if (!isClosed) {
        await showErrorDialog(
          title: '读取文件失败',
          message: errorMessageOf(error),
          error: error,
        );
      }
      return;
    } finally {
      if (!isClosed) {
        refreshing.value = false;
      }
    }

    if (isClosed || !context.mounted) return;
    AppDialog.dismiss(context, true);
    Future<void> onSave(List<AnimeEpisodeCreate> episodes) => coordinator
        .submitLocalAdd(subject: subject, folderId: id, episodes: episodes);
    unawaited(
      Get.to(
        () => AnimeGardenEpisodeMatchPage(
          subject: subject,
          files: files!,
          bangumiEpisodes: bangumiEpisodes!,
          animeListStore: animeListStore,
          pageTitle: '匹配 Episode',
          onSave: onSave,
        ),
        binding: AnimeGardenEpisodeMatchBinding(
          subject: subject,
          files: files,
          bangumiEpisodes: bangumiEpisodes,
          animeListStore: animeListStore,
          onSave: onSave,
        ),
      ),
    );
  }
}
