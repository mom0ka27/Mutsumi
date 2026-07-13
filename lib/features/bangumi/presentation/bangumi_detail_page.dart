import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/media_detail_overview.dart';
import '../../anime_garden/presentation/anime_garden_download_page.dart';
import '../data/bangumi_repository.dart';

class BangumiDetailPage extends StatefulWidget {
  const BangumiDetailPage({super.key, required this.subject});

  final BangumiSubject subject;

  @override
  State<BangumiDetailPage> createState() => _BangumiDetailPageState();
}

class _BangumiDetailPageState extends State<BangumiDetailPage> {
  late final Future<BangumiSubjectDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = BangumiRepository().getSubjectDetail(widget.subject.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BangumiSubjectDetail>(
      future: _detailFuture,
      initialData: widget.subject is BangumiSubjectDetail
          ? widget.subject as BangumiSubjectDetail
          : null,
      builder: (context, snapshot) {
        final subject = snapshot.data ?? widget.subject;
        final detail = snapshot.data;

        return GlassScaffold(
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
          body: snapshot.hasError
              ? _DetailError(
                  subject: widget.subject,
                  message: snapshot.error.toString(),
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        Constants.topPadding,
                        20,
                        120,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: MediaDetailOverview(
                          data: _overviewData(subject, detail),
                          heroTag: 'bangumi-cover-${subject.id}',
                        ),
                      ),
                    ),
                    if (snapshot.connectionState != ConnectionState.done)
                      const SliverToBoxAdapter(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
          floatingActionButton: GlassButton.custom(
            onTap: () => Get.to(
              () => AnimeGardenDownloadPage(
                subject: subject,
                backgroundImageUrl: subject.imageUrl,
              ),
            ),
            width: 100,
            shape: LiquidRoundedRectangle(borderRadius: Constants.radius.x),
            label: '下载',
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_rounded, size: 24),
                SizedBox(width: 12),
                Text('下载'),
              ],
            ),
          ),
        );
      },
    );
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

class _DetailError extends StatelessWidget {
  const _DetailError({required this.subject, required this.message});

  final BangumiSubject subject;
  final String message;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, Constants.topPadding, 20, 120),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                MediaDetailOverview(
                  data: MediaDetailOverviewData(
                    title: subject.displayName,
                    originalTitle: subject.originalName,
                    imageUrl: subject.imageUrl,
                    metadata: [
                      if (subject.score > 0)
                        MediaDetailMetadata(
                          icon: Icons.star_rounded,
                          label: subject.score.toStringAsFixed(1),
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
                    ],
                    summary: subject.summary,
                    tags: const [],
                    infoItems: const [],
                  ),
                  heroTag: 'bangumi-cover-${subject.id}',
                ),
                const SizedBox(height: 16),
                Text('详情加载失败\n$message', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
