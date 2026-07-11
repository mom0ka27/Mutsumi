import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../features/bangumi/presentation/bangumi_search_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/setup/presentation/connect_server_page.dart';
import 'startup_page.dart';

class MutsumiApp extends StatelessWidget {
  const MutsumiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Mutsumi',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: StartupPage.routeName,
      getPages: [
        GetPage(name: StartupPage.routeName, page: () => const StartupPage()),
        GetPage(
          name: ConnectServerPage.routeName,
          page: () => const ConnectServerPage(),
        ),
        GetPage(name: HomePage.routeName, page: () => const HomePage()),
        GetPage(
          name: BangumiSearchPage.routeName,
          page: () => const BangumiSearchPage(),
        ),
      ],
    );
  }
}
