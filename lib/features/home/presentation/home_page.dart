import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../anime/data/anime_list_store.dart';
import '../../anime/presentation/anime_home_view.dart';
import '../../downloads/presentation/download_progress_view.dart';
import '../../settings/presentation/settings_home_view.dart';
import '../../bangumi/presentation/bangumi_search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const routeName = '/home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _selectedIndex = 0.obs;
  late final PageController _pageController;
  late final AnimeListStore _animeListStore;

  static const _titles = ['主页', 'Bangumi', '下载', '设置'];
  static const _icons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.download_rounded,
    Icons.settings_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _animeListStore = Get.put<AnimeListStore>(AnimeListStore());
    _pageController = PageController(initialPage: _selectedIndex.value);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    _selectedIndex.value = index;
    _pageController.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    _selectedIndex.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final selectedIndex = _selectedIndex.value;
      final useSidebar = MediaQuery.sizeOf(context).width >= 600;

      return GlassScaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        body: Row(
          children: [
            if (useSidebar)
              _HomeSidebar(
                selectedIndex: selectedIndex,
                onSelected: _onTabSelected,
                expanded: MediaQuery.sizeOf(context).width >= 900,
              ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: [
                  HeroMode(
                    enabled: selectedIndex == 0,
                    child: AnimeHomeView(store: _animeListStore),
                  ),
                  HeroMode(
                    enabled: selectedIndex == 1,
                    child: BangumiSearchView(store: _animeListStore),
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
        statusBarStyle: GlassStatusBarStyle.auto,
        background: const AppGlassBackground(),
        bottomBar: useSidebar
            ? null
            : GlassTabBar.bottom(
                selectedIndex: selectedIndex,
                onTabSelected: _onTabSelected,
                tabs: const [
                  GlassTab(icon: Icon(Icons.home_rounded), label: '主页'),
                  GlassTab(icon: Icon(Icons.search_rounded), label: 'Bangumi'),
                  GlassTab(icon: Icon(Icons.download_rounded), label: '下载'),
                  GlassTab(icon: Icon(Icons.settings_rounded), label: '设置'),
                ],
                settings: LiquidGlassSettings.figma(
                  glassColor: Colors.white.withAlpha(100),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
      child: GlassCard(
        width: expanded ? 224 : 76,
        padding: EdgeInsets.symmetric(
          horizontal: expanded ? 12 : 8,
          vertical: 16,
        ),
        settings: AppGlassSettings.standard(context),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 28,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                itemCount: _HomePageState._titles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final selected = index == selectedIndex;
                  final item = NavigationRailDestination(
                    icon: Icon(_HomePageState._icons[index]),
                    selectedIcon: Icon(_HomePageState._icons[index]),
                    label: Text(_HomePageState._titles[index]),
                  );
                  return Tooltip(
                    message: expanded ? '' : _HomePageState._titles[index],
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
