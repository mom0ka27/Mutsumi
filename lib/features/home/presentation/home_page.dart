import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/widgets/app_glass_background.dart';
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

  @override
  void initState() {
    super.initState();
    _animeListStore = AnimeListStore();
    Get.put<AnimeListStore>(_animeListStore, permanent: true);
    _pageController = PageController(initialPage: _selectedIndex.value);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    _selectedIndex.value = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    _selectedIndex.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final selectedIndex = _selectedIndex.value;

      return GlassScaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        appBar: GlassAppBar(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(
            _titles[selectedIndex],
            style: Theme.of(context).textTheme.titleLarge,
          ),
          centerTitle: false,
        ),
        body: PageView(
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
        statusBarStyle: GlassStatusBarStyle.auto,
        background: const AppGlassBackground(),
        bottomBar: GlassTabBar.bottom(
          selectedIndex: selectedIndex,
          onTabSelected: _onTabSelected,
          tabs: const [
            GlassTab(icon: Icon(Icons.home_rounded), label: '主页'),
            GlassTab(icon: Icon(Icons.search_rounded), label: 'Bangumi'),
            GlassTab(icon: Icon(Icons.download_rounded), label: '下载'),
            GlassTab(icon: Icon(Icons.settings_rounded), label: '设置'),
          ],
          settings: LiquidGlassSettings.figma(
            glassColor: Colors.white.withAlpha(20),
            refraction: 50,
            depth: 24,
            dispersion: 8,
            frost: 0.2,
          ),
          selectedIconColor: colorScheme.primary,
          selectedLabelColor: colorScheme.primary,
        ),
      );
    });
  }
}
