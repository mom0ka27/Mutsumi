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
import '../../subscriptions/presentation/subscription_editor_page.dart';
import '../data/airing_status.dart';
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
              ..._acquisitionActions(context, subject),
            ],
          ),
        ),
      );
    });
  }

  /// The two ways of getting a show, ordered by which one fits its status.
  ///
  /// The last entry sits closest to the thumb, so the primary action goes last.
  List<Widget> _acquisitionActions(
    BuildContext context,
    BangumiSubject subject,
  ) {
    final status = _controller.status.value;
    final download = _downloadAction(context, subject, primary: !status.prefersSubscription);
    if (!_controller.canSubscribe) return [download];
    final subscribe = _subscribeAction(context, subject, primary: status.prefersSubscription);
    final ordered = status.prefersSubscription
        ? [download, subscribe]
        : [subscribe, download];
    return [ordered.first, const SizedBox(height: 16), ordered.last];
  }

  Widget _downloadAction(
    BuildContext context,
    BangumiSubject subject, {
    required bool primary,
  }) {
    // Nothing has been released yet, so there is genuinely nothing to search
    // for. Saying so beats an empty result page the user cannot explain.
    final unaired = _controller.status.value == AiringStatus.unaired;
    return FloatingActionButton.extended(
      heroTag: 'download',
      onPressed: unaired
          ? null
          : () => Get.to(
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
      backgroundColor: primary ? null : _secondaryColor(context),
      label: Text(unaired ? '尚未开播' : '下载'),
      icon: const Icon(Icons.download_rounded),
    );
  }

  Widget _subscribeAction(
    BuildContext context,
    BangumiSubject subject, {
    required bool primary,
  }) {
    final existing = _controller.subscription.value;
    return FloatingActionButton.extended(
      heroTag: 'subscribe',
      onPressed: () async {
        final saved = await Get.to<bool>(
          () => SubscriptionEditorPage(
            bangumiId: subject.id,
            title: subject.displayName,
            subtitle: subject.originalName,
            status: _controller.status.value,
            existing: existing,
          ),
        );
        if (saved == true) await _controller.loadSubscription();
      },
      shape: LiquidRoundedRectangle(borderRadius: Constants.radius.x),
      backgroundColor: primary ? null : _secondaryColor(context),
      label: Text(existing == null ? '追番' : '追番设置'),
      icon: Icon(
        existing == null
            ? Icons.notifications_none_rounded
            : Icons.notifications_active_rounded,
      ),
    );
  }

  Color _secondaryColor(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

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
