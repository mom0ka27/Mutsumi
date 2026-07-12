import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_background.dart';
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
          enableBackgroundSampling: true,
          extendBody: true,
          background: _DetailBackground(subject: subject),
          appBar: GlassAppBar(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(
              subject.displayName,
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
                        child: _DetailCard(subject: subject, detail: detail),
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
}

class _DetailBackground extends StatelessWidget {
  const _DetailBackground({required this.subject});

  final BangumiSubject subject;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        const AppGlassBackground(showCustomImage: false),
        if (subject.imageUrl.isNotEmpty)
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                child: CachedNetworkImage(
                  useOldImageOnUrlChange: true,
                  imageUrl: subject.imageUrl,
                  fit: BoxFit.fitHeight,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
        if (subject.imageUrl.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.46, 0.82, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  colorScheme.surface.withValues(alpha: 0.18),
                  colorScheme.surface.withValues(alpha: 0.78),
                  colorScheme.surface,
                ],
              ),
            ),
          ),
      ],
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
                _DetailCard(subject: subject),
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

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.subject, this.detail});

  final BangumiSubject subject;
  final BangumiSubjectDetail? detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final cover = _CoverImage(subject: subject);
                final content = _TitleAndMeta(subject: subject, detail: detail);

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [cover, const SizedBox(height: 16), content],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover,
                    const SizedBox(width: 20),
                    Expanded(child: content),
                  ],
                );
              },
            ),
            if (subject.summary.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('简介', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                subject.summary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            if (detail != null && detail!.tags.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('标签', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: detail!.tags.take(16).map((tag) {
                  return _DetailInfoChip(icon: Icons.sell_outlined, label: tag);
                }).toList(),
              ),
            ],
            if (detail != null && detail!.infobox.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('信息', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...detail!.infobox.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          item.key,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.value,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.subject});

  final BangumiSubject subject;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 180,
      height: 252,
      child: subject.imageUrl.isEmpty
          ? ColoredBox(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.image_not_supported_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : Hero(
              tag: 'bangumi-cover-${subject.id}',
              child: ClipRRect(
                borderRadius: BorderRadius.all(Constants.radius),
                child: CachedNetworkImage(
                  useOldImageOnUrlChange: true,
                  imageUrl: subject.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
    );
  }
}

class _DetailInfoChip extends StatelessWidget {
  const _DetailInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.all(Constants.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _TitleAndMeta extends StatelessWidget {
  const _TitleAndMeta({required this.subject, this.detail});

  final BangumiSubject subject;
  final BangumiSubjectDetail? detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subject.displayName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (subject.originalName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subject.originalName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (subject.score > 0)
              _DetailInfoChip(
                icon: Icons.star_rounded,
                label: subject.score.toStringAsFixed(1),
              ),
            if (detail != null && detail!.rank > 0)
              _DetailInfoChip(
                icon: Icons.emoji_events_outlined,
                label: '#${detail!.rank}',
              ),
            if (subject.episodeCount > 0)
              _DetailInfoChip(
                icon: Icons.movie_filter_outlined,
                label: '${subject.episodeCount} 话',
              ),
            if (subject.airDate.isNotEmpty)
              _DetailInfoChip(
                icon: Icons.calendar_month_outlined,
                label: subject.airDate,
              ),
            if (detail != null && detail!.platform.isNotEmpty)
              _DetailInfoChip(icon: Icons.tv_outlined, label: detail!.platform),
          ],
        ),
      ],
    );
  }
}
