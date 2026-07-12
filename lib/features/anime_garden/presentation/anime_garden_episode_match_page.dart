import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../anime/data/anime_service.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../data/anime_garden_repository.dart';
import 'anime_garden_episode_match_controller.dart';
import 'anime_garden_file_picker.dart';

class AnimeGardenEpisodeMatchPage extends StatelessWidget {
  const AnimeGardenEpisodeMatchPage({
    super.key,
    required this.subject,
    required this.resource,
    required this.files,
    required this.bangumiEpisodes,
  });

  final BangumiSubject subject;
  final AnimeGardenResource resource;
  final List<QBittorrentFile> files;
  final List<BangumiEpisode> bangumiEpisodes;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      AnimeGardenEpisodeMatchController(
        subject: subject,
        resource: resource,
        files: files,
        bangumiEpisodes: bangumiEpisodes,
      ),
    );
    final colorScheme = Theme.of(context).colorScheme;

    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          '匹配 Episode',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        centerTitle: false,
        actions: [
          GlassButton.custom(
            height: 40,
            label: '添加剧集',
            onTap: controller.addEpisode,
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('添加剧集'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Obx(() {
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          itemBuilder: (context, index) {
            return _EpisodeMatchCard(controller: controller, index: index);
          },
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemCount: controller.matches.length,
        );
      }),
      bottomBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: GlassCard(
              useOwnLayer: true,
              padding: const EdgeInsets.all(12),
              shape: LiquidRoundedSuperellipse(
                borderRadius: Constants.radius.x,
              ),
              settings: LiquidGlassSettings.figma(
                refraction: 36,
                depth: 20,
                dispersion: 6,
                frost: 4,
                glassColor: colorScheme.surface.withValues(alpha: 0.34),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Obx(
                      () => Text(
                        '已匹配 ${controller.matches.where((m) => m.filename.isNotEmpty).length} 集',
                      ),
                    ),
                  ),
                  Obx(() {
                    return FilledButton.icon(
                      onPressed: controller.saving.value
                          ? null
                          : controller.save,
                      icon: controller.saving.value
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(controller.saving.value ? '保存中' : '确认添加'),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeMatchCard extends StatelessWidget {
  const _EpisodeMatchCard({required this.controller, required this.index});

  final AnimeGardenEpisodeMatchController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final match = controller.matches[index];
    final files = controller.videoFiles;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GlassCard(
          useOwnLayer: true,
          padding: const EdgeInsets.all(16),
          shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
          settings: LiquidGlassSettings.figma(
            refraction: 36,
            depth: 20,
            dispersion: 6,
            frost: 4,
            glassColor: colorScheme.surface.withValues(alpha: 0.28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => controller.editEpisodeName(index),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '修改名称',
                  ),
                  IconButton(
                    onPressed: () => controller.removeEpisode(index),
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: '移除',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimeGardenFileField(
                files: files,
                value: match.filename.split("/").last,
                onChanged: (value) => controller.setFilename(index, value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
