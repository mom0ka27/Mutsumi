import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../appearance/app_image_cache.dart';
import 'app_glass_settings.dart';

class MediaSummaryCard extends StatelessWidget {
  const MediaSummaryCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.chips,
    required this.onTap,
    this.subtitle = '',
    this.summary = '',
    this.heroTag,
  });

  final String imageUrl;
  final String title;
  final String subtitle;
  final String summary;
  final Object? heroTag;
  final List<Widget> chips;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GestureDetector(
          onTap: onTap,
          child: GlassCard(
            useOwnLayer: true,
            padding: const EdgeInsets.only(right: 14),
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: AppGlassSettings.standard(context),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 128,
                    child: _CoverImage(
                      imageUrl: imageUrl,
                      heroTag: heroTag,
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                          if (chips.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 8, children: chips),
                          ],
                          if (summary.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              summary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({
    required this.imageUrl,
    required this.heroTag,
    required this.colorScheme,
  });

  final String imageUrl;
  final Object? heroTag;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    final cacheWidth = AppImageCache.dimension(context, 128);
    final cacheHeight = AppImageCache.dimension(context, 192);
    final image = ClipRRect(
      borderRadius: BorderRadius.all(Constants.radius),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        useOldImageOnUrlChange: true,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        maxWidthDiskCache: cacheWidth,
        maxHeightDiskCache: cacheHeight,
      ),
    );
    return heroTag == null ? image : Hero(tag: heroTag!, child: image);
  }
}

class MediaInfoChip extends StatelessWidget {
  const MediaInfoChip({super.key, required this.icon, required this.label});

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
