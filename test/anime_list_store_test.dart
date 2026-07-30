import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:mutsumi/features/anime/data/anime_list_store.dart';
import 'package:mutsumi/features/anime/data/anime_service.dart';

void main() {
  test('并发刷新复用同一请求并更新列表索引', () async {
    final animes = Completer<List<AnimeRead>>();
    final series = Completer<List<SeriesRead>>();
    final service = _AnimeServiceStub(
      listAnimes: () {
        return animes.future;
      },
      listSeries: () {
        return series.future;
      },
    );
    final store = AnimeListStore(animeService: service);

    final first = store.refresh();
    final second = store.refresh();

    expect(service.listAnimeCalls, 1);
    expect(service.listSeriesCalls, 1);

    final anime = _anime(id: 3, bangumiId: 30);
    animes.complete([anime]);
    series.complete([]);
    await Future.wait([first, second]);

    expect(store.animes, [anime]);
    expect(store.animeMap, {30: anime});
    expect(store.isLoading.value, isFalse);
  });

  test('并发刷新失败只显示一次错误', () async {
    final errorDialog = Completer<void>();
    var errorDialogCalls = 0;
    final service = _AnimeServiceStub(
      listAnimes: () async => throw StateError('offline'),
      listSeries: () async => [],
    );
    final store = AnimeListStore(
      animeService: service,
      errorDialog: ({required title, required message, error}) {
        errorDialogCalls++;
        return errorDialog.future;
      },
    );

    await Future.wait([store.refresh(), store.refresh()]);

    expect(errorDialogCalls, 1);
    errorDialog.complete();
    await errorDialog.future;
  });

  test('创建 Series 后刷新并发送成功通知', () async {
    final anime = _anime(id: 5, bangumiId: 50, seriesId: 8);
    final createdSeries = SeriesRead(id: 8, name: '系列', animes: [anime]);
    final notifications = <(String, String)>[];
    final service = _AnimeServiceStub(
      listAnimes: () async => [anime],
      listSeries: () async => [createdSeries],
      createSeries: ({required name, required animeIds}) async {
        expect(name, '系列');
        expect(animeIds, [5, 6]);
        return createdSeries;
      },
    );
    final store = AnimeListStore(
      animeService: service,
      notification: (title, message) => notifications.add((title, message)),
    );

    await store.createSeries(name: '系列', animeIds: [5, 6]);

    expect(service.createSeriesCalls, 1);
    expect(service.listAnimeCalls, 1);
    expect(service.listSeriesCalls, 1);
    expect(store.series, [createdSeries]);
    expect(notifications, [('Series 已新建', '系列')]);
  });
}

class _AnimeServiceStub extends AnimeService {
  _AnimeServiceStub({
    required Future<List<AnimeRead>> Function() listAnimes,
    required Future<List<SeriesRead>> Function() listSeries,
    Future<SeriesRead> Function({
      required String name,
      required List<int> animeIds,
    })?
    createSeries,
  }) {
    _listAnimes = listAnimes;
    _listSeries = listSeries;
    _createSeries = createSeries;
  }

  late final Future<List<AnimeRead>> Function() _listAnimes;
  late final Future<List<SeriesRead>> Function() _listSeries;
  late final Future<SeriesRead> Function({
    required String name,
    required List<int> animeIds,
  })?
  _createSeries;
  var listAnimeCalls = 0;
  var listSeriesCalls = 0;
  var createSeriesCalls = 0;

  @override
  Future<List<AnimeRead>> listAnimes() {
    listAnimeCalls++;
    return _listAnimes();
  }

  @override
  Future<List<SeriesRead>> listSeries() {
    listSeriesCalls++;
    return _listSeries();
  }

  @override
  Future<SeriesRead> createSeries({
    required String name,
    required List<int> animeIds,
  }) {
    createSeriesCalls++;
    return _createSeries!(name: name, animeIds: animeIds);
  }
}

AnimeRead _anime({required int id, required int bangumiId, int? seriesId}) =>
    AnimeRead(
      id: id,
      bangumiId: bangumiId,
      name: 'Anime $id',
      nameCn: '',
      summary: '',
      imageUrl: '',
      score: 0,
      episodeCount: 0,
      airDate: '',
      rank: 0,
      platform: '',
      tags: const [],
      infobox: const [],
      downloadHash: null,
      episodes: const [],
      watchProgress: null,
      seriesId: seriesId,
    );
