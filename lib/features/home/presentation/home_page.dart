import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/extensions/build_context.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../anime/data/anime_list_store.dart';
import '../../subscriptions/data/subscription_store.dart';
import '../../anime/presentation/anime_home_view.dart';
import '../../downloads/presentation/download_progress_view.dart';
import '../../settings/presentation/settings_home_view.dart';
import '../../bangumi/presentation/bangumi_search_page.dart';
import 'home_controller.dart';

class HomePage extends GetView<HomeController> {
  const HomePage({super.key});

  static const _titles = ['主页', 'Bangumi', '下载', '设置'];
  static const _icons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.download_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final animeListStore = Get.find<AnimeListStore>();
    return Obx(() {
      final selectedIndex = controller.selectedIndex.value;
      final useSidebar = context.useSidebarNavigation;

      return GlassScaffold(
        topEdgeFade: true,
        edgeToEdge: true,
        bottomEdgeFade: false,
        extendBody: true,
        resizeToAvoidBottomInset: false,
        // 横屏时刘海占据的是左右安全区。在这里一次性消化掉，各标签页的
        // homeContentPadding 就只需要关心自己的基础留白。
        body: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              if (useSidebar)
                _HomeSidebar(
                  selectedIndex: selectedIndex,
                  onSelected: controller.selectTab,
                  expanded: context.useExpandedSidebar,
                ),
              Expanded(
                child: PageView(
                  controller: controller.pageController,
                  onPageChanged: controller.changePage,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    HeroMode(
                      enabled: selectedIndex == 0,
                      child: AnimeHomeView(
                        store: animeListStore,
                        subscriptionStore: Get.find<SubscriptionStore>(),
                      ),
                    ),
                    HeroMode(
                      enabled: selectedIndex == 1,
                      child: BangumiSearchView(store: animeListStore),
                    ),
                    HeroMode(
                      enabled: selectedIndex == 2,
                      child: DownloadProgressView(isActive: selectedIndex == 2),
                    ),
                    HeroMode(
                      enabled: selectedIndex == 3,
                      child: const SettingsHomeView(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        statusBarStyle: GlassStatusBarStyle.auto,
        background: const AppGlassBackground(),
        bottomBar: useSidebar
            ? null
            : GlassTabBar.bottom(
                selectedIndex: selectedIndex,
                onTabSelected: controller.selectTab,
                tabs: const [
                  GlassTab(icon: Icon(Icons.home_rounded), label: '主页'),
                  GlassTab(icon: Icon(Icons.search_rounded), label: 'Bangumi'),
                  GlassTab(icon: Icon(Icons.download_rounded), label: '下载'),
                  GlassTab(icon: Icon(Icons.settings_rounded), label: '设置'),
                ],
                settings: LiquidGlassSettings.figma(
                  glassColor: colorScheme.brightness == Brightness.dark
                      ? Colors.black.withAlpha(100)
                      : Colors.white.withAlpha(100),
                  refraction: 80,
                  depth: 24,
                  dispersion: 8,
                  frost: 1,
                ),
                selectedIconColor: colorScheme.primary,
                selectedLabelColor: colorScheme.primary,
              ),
      );
    });
  }
}

class _HomeSidebar extends StatelessWidget {
  const _HomeSidebar({
    required this.selectedIndex,
    required this.onSelected,
    required this.expanded,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final safeArea = MediaQuery.paddingOf(context);
    // 横屏时状态栏安全区为 0，标题图标也就没必要留出竖屏那么高的空隙。
    final compact = context.isCompactHeight;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        safeArea.top + 8,
        12,
        safeArea.bottom + 16,
      ),
      child: GlassCard(
        useOwnLayer: true,
        width: expanded ? 224 : 76,
        padding: EdgeInsets.symmetric(
          horizontal: expanded ? 12 : 8,
          vertical: compact ? 12 : 16,
        ),
        settings: AppGlassSettings.standard(context),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 28,
              color: colorScheme.primary,
            ),
            SizedBox(height: compact ? 12 : 24),
            Expanded(
              child: ListView.separated(
                itemCount: HomePage._titles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final selected = index == selectedIndex;
                  final item = NavigationRailDestination(
                    icon: Icon(HomePage._icons[index]),
                    selectedIcon: Icon(HomePage._icons[index]),
                    label: Text(HomePage._titles[index]),
                  );
                  return Tooltip(
                    message: expanded ? '' : HomePage._titles[index],
                    child: Material(
                      color: selected
                          ? colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => onSelected(index),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: expanded ? 14 : 10,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: expanded
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: [
                              IconTheme(
                                data: IconThemeData(
                                  color: selected
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                                child: selected ? item.selectedIcon : item.icon,
                              ),
                              if (expanded) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DefaultTextStyle(
                                    style: TextStyle(
                                      color: selected
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                    child: item.label,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
