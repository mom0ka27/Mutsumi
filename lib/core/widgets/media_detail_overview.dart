import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mutsumi/constants.dart';

import '../appearance/app_image_cache.dart';
import 'media_summary_card.dart';

class MediaDetailMetadata {
  const MediaDetailMetadata({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class MediaDetailInfoItem {
  const MediaDetailInfoItem({required this.label, required this.value});

  final String label;
  final String value;
}

class MediaDetailOverviewData {
  const MediaDetailOverviewData({
    required this.title,
    required this.originalTitle,
    required this.imageUrl,
    required this.metadata,
    required this.summary,
    required this.tags,
    required this.infoItems,
  });

  final String title;
  final String originalTitle;
  final String imageUrl;
  final List<MediaDetailMetadata> metadata;
  final String summary;
  final List<String> tags;
  final List<MediaDetailInfoItem> infoItems;
}

class MediaDetailBackground extends StatelessWidget {
  const MediaDetailBackground({
    super.key,
    required this.imageUrl,
    required this.blurSigma,
    required this.showGradientWithoutImage,
  });

  final String imageUrl;
  final double blurSigma;
  final bool showGradientWithoutImage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheWidth = AppImageCache.dimension(context, 180);
    final cacheHeight = AppImageCache.dimension(context, 252);
    final hasImage = imageUrl.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (hasImage)
          Positioned.fill(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.2,
                alignment: Alignment.topCenter,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: CachedNetworkImage(
                    useOldImageOnUrlChange: true,
                    imageUrl: imageUrl,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    memCacheWidth: cacheWidth,
                    memCacheHeight: cacheHeight,
                    maxWidthDiskCache: cacheWidth,
                    maxHeightDiskCache: cacheHeight,
                  ),
                ),
              ),
            ),
          ),
        if (hasImage || showGradientWithoutImage)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.46, 0.82, 1],
                colors: [
                  Colors.black.withValues(alpha: hasImage ? 0.12 : 0.2),
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

class MediaDetailOverview extends StatelessWidget {
  const MediaDetailOverview({
    super.key,
    required this.data,
    required this.heroTag,
    this.beforeSummary,
  });

  final MediaDetailOverviewData data;
  final Object heroTag;
  final Widget? beforeSummary;

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
                final cover = _MediaDetailCover(
                  imageUrl: data.imageUrl,
                  heroTag: heroTag,
                );
                final content = _MediaDetailTitle(data: data);
                return constraints.maxWidth < 560
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [cover, const SizedBox(height: 16), content],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cover,
                          const SizedBox(width: 20),
                          Expanded(child: content),
                        ],
                      );
              },
            ),
            if (beforeSummary != null) ...[
              const SizedBox(height: 22),
              beforeSummary!,
            ],
            if (data.summary.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('简介', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                data.summary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            if (data.tags.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('标签', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: data.tags
                    .take(16)
                    .map(
                      (tag) =>
                          MediaInfoChip(icon: Icons.sell_outlined, label: tag),
                    )
                    .toList(),
              ),
            ],
            if (data.infoItems.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('信息', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...data.infoItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          item.label,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(child: Text(item.value)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaDetailCover extends StatelessWidget {
  const _MediaDetailCover({required this.imageUrl, required this.heroTag});

  final String imageUrl;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheWidth = AppImageCache.dimension(context, 180);
    final cacheHeight = AppImageCache.dimension(context, 252);
    return SizedBox(
      width: 180,
      height: 252,
      child: imageUrl.isEmpty
          ? ColoredBox(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.image_not_supported_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.all(Constants.radius),
                child: CachedNetworkImage(
                  useOldImageOnUrlChange: true,
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: cacheWidth,
                  memCacheHeight: cacheHeight,
                  maxWidthDiskCache: cacheWidth,
                  maxHeightDiskCache: cacheHeight,
                ),
              ),
            ),
    );
  }
}

class _MediaDetailTitle extends StatelessWidget {
  const _MediaDetailTitle({required this.data});

  final MediaDetailOverviewData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.title, style: Theme.of(context).textTheme.headlineSmall),
        if (data.originalTitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            data.originalTitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (data.metadata.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: data.metadata
                .map(
                  (item) => MediaInfoChip(icon: item.icon, label: item.label),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}
