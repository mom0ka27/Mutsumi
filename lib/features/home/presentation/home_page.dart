import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_background.dart';
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

  static const _titles = ['主页', 'Bangumi', '下载', '设置'];

  void _onTabSelected(int index) {
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
        body: IndexedStack(
          index: selectedIndex,
          children: [
            const AnimeHomeView(),
            const BangumiSearchView(),
            DownloadProgressView(isActive: selectedIndex == 2),
            const SettingsHomeView(),
          ],
        ),
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
