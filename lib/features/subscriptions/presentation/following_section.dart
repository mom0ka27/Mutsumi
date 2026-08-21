import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/page_bindings.dart';
import '../../../constants.dart';
import '../../../core/appearance/app_image_cache.dart';
import '../../anime/presentation/anime_detail_page.dart';
import '../data/subscription_models.dart';

/// The "追番中" strip above the library.
///
/// Shows what is expected to arrive, which the library cannot: a followed show
/// with nothing downloaded yet has no library card at all.
class FollowingSection extends StatelessWidget {
  const FollowingSection({
    super.key,
    required this.subscriptions,
    required this.onChanged,
  });

  final List<SubscriptionRead> subscriptions;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text('追番中', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 6),
                  Text(
                    '${subscriptions.length}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 232,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: subscriptions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _FollowingCard(
                  subscription: subscriptions[index],
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowingCard extends StatelessWidget {
  const _FollowingCard({required this.subscription, required this.onChanged});

  final SubscriptionRead subscription;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status(subscription);
    return SizedBox(
      width: 118,
      child: InkWell(
        borderRadius: BorderRadius.all(Constants.radius),
        onTap: () async {
          await Get.to(
            () => AnimeDetailPage(animeId: subscription.animeId),
            binding: AnimeDetailBinding(animeId: subscription.animeId),
          );
          await onChanged();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 5 / 7,
              child: _Cover(imageUrl: subscription.imageUrl),
            ),
            const SizedBox(height: 8),
            Text(
              subscription.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: status.emphasized
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (imageUrl.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.all(Constants.radius),
        child: ColoredBox(
          color: colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final cacheWidth = AppImageCache.dimension(context, 120);
    final cacheHeight = AppImageCache.dimension(context, 168);
    return ClipRRect(
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
  }
}

class _FollowingStatus {
  const _FollowingStatus(this.label, {this.emphasized = false});

  final String label;
  final bool emphasized;
}

/// What the card says, most actionable first.
///
/// Something needing a human outranks a schedule: a stalled episode is the one
/// thing the user has to do something about.
_FollowingStatus _status(SubscriptionRead subscription) {
  if (!subscription.enabled) return const _FollowingStatus('已暂停');
  if (subscription.needsReviewCount > 0) {
    return _FollowingStatus(
      '${subscription.needsReviewCount} 集待确认',
      emphasized: true,
    );
  }
  if (subscription.lastError != null && subscription.lastError!.isNotEmpty) {
    return const _FollowingStatus('上次检查失败', emphasized: true);
  }
  final index = subscription.nextEpisodeIndex;
  final airDate = subscription.nextEpisodeAirDate;
  if (index == null) {
    final owned = subscription.ownedEpisodeCount;
    return _FollowingStatus(owned > 0 ? '已补齐 $owned 集' : '暂无集数信息');
  }
  if (airDate == null) return _FollowingStatus('第 $index 集 · 待定');
  if (airDate.isAfter(DateTime.now())) {
    return _FollowingStatus('第 $index 集 · ${_shortDate(airDate)}');
  }
  // Already broadcast but still missing: the sweep has not found a release
  // that passes the rules yet.
  return _FollowingStatus('第 $index 集 · 等待资源');
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.month}/${local.day}';
}
