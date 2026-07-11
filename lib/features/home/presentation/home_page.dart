import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../anime/presentation/anime_home_view.dart';
import '../../bangumi/presentation/bangumi_search_page.dart';
import '../../settings/data/settings_repository.dart';
import '../../setup/presentation/connect_server_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const routeName = '/home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _settingsRepository = SettingsRepository();
  late String? _currentServerUrl;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentServerUrl = _settingsRepository.getCurrentServerUrl();
  }

  Future<void> _connectNewServer() async {
    await Get.to(() => const ConnectServerPage(prefillLastServer: false));
    setState(() {
      _currentServerUrl = _settingsRepository.getCurrentServerUrl();
    });
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentServerUrl = _currentServerUrl;
    final currentServerName = currentServerUrl == null
        ? '未连接服务器'
        : _settingsRepository.getServerName(currentServerUrl);
    final username = currentServerUrl == null
        ? null
        : _settingsRepository.getServerCredential(currentServerUrl)?.username;
    final colorScheme = Theme.of(context).colorScheme;

    return GlassPage(
      enableBackgroundSampling: false,
      background: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.72),
              colorScheme.surface,
              colorScheme.secondaryContainer.withValues(alpha: 0.72),
            ],
          ),
        ),
      ),
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leadingWidth: 320,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.72,
                  ),
                  borderRadius: BorderRadius.all(Constants.radius),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.dns_rounded,
                          size: 18,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username ?? "未登录",
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              "@$currentServerName",
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _connectNewServer,
                icon: const Icon(Icons.add_link),
                label: const Text('连接新的服务器'),
              ),
            ),
          ],
        ),
        body: _HomeContent(
          selectedIndex: _selectedIndex,
          currentServerUrl: currentServerUrl,
          currentServerName: currentServerName,
        ),
        bottomNavigationBar: GlassTabBar.bottom(
          selectedIndex: _selectedIndex,
          onTabSelected: _onTabSelected,
          tabs: const [
            GlassTab(icon: Icon(Icons.home_rounded), label: '主页'),
            GlassTab(icon: Icon(Icons.search_rounded), label: 'Bangumi'),
            GlassTab(icon: Icon(Icons.people_rounded), label: '用户'),
            GlassTab(icon: Icon(Icons.settings_rounded), label: '设置'),
          ],
          settings: LiquidGlassSettings.figma(
            refraction: 42,
            depth: 24,
            dispersion: 8,
            frost: 5,
            glassColor: colorScheme.surface.withValues(alpha: 0.34),
          ),
          selectedIconColor: colorScheme.primary,
          selectedLabelColor: colorScheme.primary,
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.selectedIndex,
    required this.currentServerUrl,
    required this.currentServerName,
  });

  final int selectedIndex;
  final String? currentServerUrl;
  final String currentServerName;

  @override
  Widget build(BuildContext context) {
    return switch (selectedIndex) {
      1 => const BangumiSearchView(bottomPadding: 120),
      2 => const _PaddedPlaceholderSection(
        icon: Icons.people_rounded,
        title: '用户与权限',
        subtitle: '管理 Admin、User、Guest 权限组用户。',
      ),
      3 => const _PaddedPlaceholderSection(
        icon: Icons.settings_rounded,
        title: '设置',
        subtitle: '服务端连接与应用设置。',
      ),
      _ => const AnimeHomeView(bottomPadding: 120),
    };
  }
}

class _PaddedPlaceholderSection extends StatelessWidget {
  const _PaddedPlaceholderSection({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: GlassCard(
              useOwnLayer: true,
              padding: const EdgeInsets.all(28),
              shape: LiquidRoundedSuperellipse(
                borderRadius: Constants.radius.x,
              ),
              settings: LiquidGlassSettings.figma(
                refraction: 36,
                depth: 22,
                dispersion: 6,
                frost: 5,
                glassColor: colorScheme.surface.withValues(alpha: 0.3),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(icon, color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
