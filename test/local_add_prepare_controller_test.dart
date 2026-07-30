import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';

import 'package:mutsumi/features/anime/data/anime_list_store.dart';
import 'package:mutsumi/features/anime/data/anime_service.dart';
import 'package:mutsumi/features/anime_garden/data/local_add_coordinator.dart';
import 'package:mutsumi/features/anime_garden/presentation/local_add_prepare_controller.dart';
import 'package:mutsumi/features/bangumi/data/bangumi_repository.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('未找到文件后重置 refreshing', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final controller = LocalAddPrepareController(
      subject: _subject,
      coordinator: _EmptyLocalAddCoordinator(),
      animeListStore: AnimeListStore(),
    );
    controller.folderId.value = 'folder';

    final refreshing = controller.refreshFiles(context);
    expect(controller.refreshing.value, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('未找到视频文件'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await refreshing;

    expect(controller.refreshing.value, isFalse);
  });
}

const _subject = BangumiSubject(
  id: 1,
  name: 'Anime',
  nameCn: '',
  summary: '',
  imageUrl: '',
  score: 0,
  episodeCount: 1,
  airDate: '',
);

class _EmptyLocalAddCoordinator extends LocalAddCoordinator {
  _EmptyLocalAddCoordinator()
    : super(
        animeService: AnimeService(),
        bangumiRepository: BangumiRepository(dio: Dio()),
      );

  @override
  Future<List<QBittorrentFile>> listFiles(String folderId) async => [];
}
