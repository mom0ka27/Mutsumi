import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../anime/presentation/anime_home_view.dart';
import '../../auth/presentation/login_page.dart';
import '../../downloads/presentation/download_progress_view.dart';
import '../../settings/presentation/settings_home_view.dart';
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
  late final RxnString _currentServerUrl;
  final _selectedIndex = 0.obs;
  final _accountAnchorKey = GlobalKey();
  OverlayEntry? _accountOverlay;

  @override
  void initState() {
    super.initState();
    _currentServerUrl = RxnString(_settingsRepository.getCurrentServerUrl());
  }

  Future<void> _connectNewServer() async {
    await Get.to(() => const ConnectServerPage(prefillLastServer: false));
    _currentServerUrl.value = _settingsRepository.getCurrentServerUrl();
  }

  Future<void> _addAccount(String serverUrl) async {
    await Get.to(
      () => LoginPage(
        serverUrl: serverUrl,
        certificateSha256: _settingsRepository.getCertificateFingerprint(
          serverUrl,
        ),
        serverName: _settingsRepository.getServerName(serverUrl),
      ),
    );
    _currentServerUrl.value = _settingsRepository.getCurrentServerUrl();
  }

  Future<void> _switchAccount(ServerAccount account) async {
    await _settingsRepository.setCurrentAccount(
      account.serverUrl,
      account.username,
    );
    _currentServerUrl.value = account.serverUrl;
    Get.offAllNamed(HomePage.routeName);
  }

  Future<void> _showAccountSwitcher(
    BuildContext context,
    String currentServerUrl,
    String? username,
  ) async {
    _accountOverlay?.remove();
    final anchorContext = _accountAnchorKey.currentContext;
    if (anchorContext == null) {
      return;
    }
    final anchorBox = anchorContext.findRenderObject() as RenderBox;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchorOffset = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final accounts = _settingsRepository.getAccounts();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                entry.remove();
                _accountOverlay = null;
              },
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: anchorOffset.dx,
            top: anchorOffset.dy + anchorBox.size.height + 8,
            width: 320,
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.94, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  alignment: Alignment.topLeft,
                  child: Opacity(opacity: value, child: child),
                ),
                child: GlassCard(
                  useOwnLayer: true,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  shape: LiquidRoundedSuperellipse(borderRadius: 24),
                  settings: LiquidGlassSettings.figma(
                    refraction: 42,
                    depth: 24,
                    dispersion: 8,
                    frost: 7,
                    glassColor: colorScheme.surface.withValues(alpha: 0.48),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 8),
                          Text(
                            '切换账户',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '添加账户',
                            onPressed: () {
                              entry.remove();
                              _accountOverlay = null;
                              _addAccount(currentServerUrl);
                            },
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                          ),
                        ],
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: accounts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final account = accounts[index];
                            final selected =
                                account.serverUrl == currentServerUrl &&
                                account.username == username;
                            return Material(
                              color: selected
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: 0.72,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.all(Constants.radius),
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.all(
                                    Constants.radius,
                                  ),
                                ),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: selected
                                      ? colorScheme.primary
                                      : colorScheme.surfaceContainerHighest,
                                  foregroundColor: selected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurfaceVariant,
                                  child: Text(
                                    account.username.isEmpty
                                        ? '?'
                                        : account.username[0].toUpperCase(),
                                  ),
                                ),
                                title: Text(
                                  account.username,
                                  style: TextStyle(
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : null,
                                  ),
                                ),
                                subtitle: Text(
                                  _settingsRepository.getServerName(
                                    account.serverUrl,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: selected
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: colorScheme.primary,
                                      )
                                    : null,
                                onTap: () {
                                  entry.remove();
                                  _accountOverlay = null;
                                  if (!selected) {
                                    _switchAccount(account);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    _accountOverlay = entry;
    Overlay.of(context).insert(entry);
  }

  @override
  void dispose() {
    _accountOverlay?.remove();
    super.dispose();
  }

  void _onTabSelected(int index) {
    _selectedIndex.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final currentServerUrl = _currentServerUrl.value;
      final currentServerName = currentServerUrl == null
          ? '未连接服务器'
          : _settingsRepository.getServerName(currentServerUrl);
      final username = currentServerUrl == null
          ? null
          : _settingsRepository.getServerCredential(currentServerUrl)?.username;
      final selectedIndex = _selectedIndex.value;

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
                  child: InkWell(
                    key: _accountAnchorKey,
                    borderRadius: BorderRadius.all(Constants.radius),
                    onTap: currentServerUrl == null
                        ? null
                        : () => _showAccountSwitcher(
                            context,
                            currentServerUrl,
                            username,
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
                          const SizedBox(width: 8),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
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
            selectedIndex: selectedIndex,
            currentServerUrl: currentServerUrl,
            currentServerName: currentServerName,
          ),
          bottomNavigationBar: GlassTabBar.bottom(
            selectedIndex: selectedIndex,
            onTabSelected: _onTabSelected,
            tabs: const [
              GlassTab(icon: Icon(Icons.home_rounded), label: '主页'),
              GlassTab(icon: Icon(Icons.search_rounded), label: 'Bangumi'),
              GlassTab(icon: Icon(Icons.download_rounded), label: '下载'),
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
    });
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
      2 => const DownloadProgressView(bottomPadding: 120),
      3 => const SettingsHomeView(bottomPadding: 120),
      _ => const AnimeHomeView(bottomPadding: 120),
    };
  }
}
