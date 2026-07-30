import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';
import '../../../core/extensions/build_context.dart';

import '../../../core/widgets/media_detail_overview.dart';
import '../../anime/data/anime_list_store.dart';
import '../../anime_garden/presentation/anime_garden_download_page.dart';
import '../../anime_garden/presentation/anime_garden_bindings.dart';
import '../../anime_garden/presentation/local_add_prepare_page.dart';
import '../data/bangumi_repository.dart';
import 'bangumi_detail_controller.dart';

class BangumiDetailPage extends StatefulWidget {
  const BangumiDetailPage({super.key, required this.subject});

  final BangumiSubject subject;

  @override
  State<BangumiDetailPage> createState() => _BangumiDetailPageState();
}

class _BangumiDetailPageState extends State<BangumiDetailPage> {
  final _controller = Get.find<BangumiDetailController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final detail = _controller.detail.value;
      final subject = detail ?? widget.subject;
      return GlassScaffold(
        topEdgeFade: true,
        bottomEdgeFade: false,
        background: MediaDetailBackground(
          imageUrl: subject.imageUrl,
          blurSigma: 16,
          showGradientWithoutImage: false,
        ),
        statusBarStyle: GlassStatusBarStyle.light,
        edgeToEdge: true,
        appBar: GlassAppBar(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          leading: GlassButton(
            width: 40,
            height: 40,
            iconSize: 20,
            icon: const Icon(Icons.arrow_back),
            label: '返回',
            onTap: Get.back,
          ),
        ),
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: context.pageContentPadding(bottom: 120),
              sliver: SliverToBoxAdapter(
                child: MediaDetailOverview(
                  data: _overviewData(subject, detail),
                  heroTag: 'cover-${subject.id}',
                ),
              ),
            ),
            if (_controller.loading.value)
              const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'local-add',
                onPressed: () => showLocalAddDialog(context, subject: subject),
                shape: LiquidRoundedRectangle(borderRadius: Constants.radius.x),
                label: const Text("添加"),
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(height: 16),
              FloatingActionButton.extended(
                heroTag: 'download',
                onPressed: () => Get.to(
                  () => AnimeGardenDownloadPage(
                    subject: subject,
                    backgroundImageUrl: subject.imageUrl,
                  ),
                  binding: AnimeGardenDownloadBinding(
                    subject: subject,
                    animeListStore: Get.find<AnimeListStore>(),
                  ),
                ),
                shape: LiquidRoundedRectangle(borderRadius: Constants.radius.x),
                label: const Text("下载"),
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
        ),
      );
    });
  }

  MediaDetailOverviewData _overviewData(
    BangumiSubject subject,
    BangumiSubjectDetail? detail,
  ) {
    return MediaDetailOverviewData(
      title: subject.displayName,
      originalTitle: subject.originalName,
      imageUrl: subject.imageUrl,
      metadata: [
        if (subject.score > 0)
          MediaDetailMetadata(
            icon: Icons.star_rounded,
            label: subject.score.toStringAsFixed(1),
          ),
        if (detail != null && detail.rank > 0)
          MediaDetailMetadata(
            icon: Icons.emoji_events_outlined,
            label: '#${detail.rank}',
          ),
        if (subject.episodeCount > 0)
          MediaDetailMetadata(
            icon: Icons.movie_filter_outlined,
            label: '${subject.episodeCount} 话',
          ),
        if (subject.airDate.isNotEmpty)
          MediaDetailMetadata(
            icon: Icons.calendar_month_outlined,
            label: subject.airDate,
          ),
        if (detail != null && detail.platform.isNotEmpty)
          MediaDetailMetadata(icon: Icons.tv_outlined, label: detail.platform),
      ],
      summary: subject.summary,
      tags: detail?.tags ?? const [],
      infoItems: (detail?.infobox ?? const [])
          .map(
            (item) => MediaDetailInfoItem(label: item.key, value: item.value),
          )
          .toList(),
    );
  }
}
