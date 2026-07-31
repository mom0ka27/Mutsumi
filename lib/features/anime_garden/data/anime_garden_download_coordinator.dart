import '../../anime/data/anime_service.dart';
import '../../bangumi/data/bangumi_repository.dart';
import 'anime_garden_repository.dart';

class AnimeGardenEpisodeMatchingContext {
  const AnimeGardenEpisodeMatchingContext({
    required this.files,
    required this.bangumiEpisodes,
  });

  final List<QBittorrentFile> files;
  final List<BangumiEpisode> bangumiEpisodes;
}

class AnimeGardenDownloadCoordinator {
  AnimeGardenDownloadCoordinator({
    AnimeService? animeService,
    BangumiRepository? bangumiRepository,
  }) : _animeService = animeService ?? AnimeService(),
       _bangumiRepository = bangumiRepository ?? BangumiRepository();

  final AnimeService _animeService;
  final BangumiRepository _bangumiRepository;

  Future<AnimeGardenEpisodeMatchingContext> prepareEpisodeMatching({
    required BangumiSubject subject,
    required AnimeGardenResource resource,
  }) async {
    final files = await _animeService.pollTorrentFiles(resource.downloadLink);
    if (files.isEmpty) {
      throw StateError('qBittorrent 暂未返回文件列表');
    }
    final bangumiEpisodes = await _bangumiRepository.getEpisodes(subject.id);
    return AnimeGardenEpisodeMatchingContext(
      files: files,
      bangumiEpisodes: bangumiEpisodes,
    );
  }

  Future<void> submitEpisodeSelection({
    required BangumiSubject subject,
    required AnimeGardenResource resource,
    required List<AnimeEpisodeCreate> episodes,
  }) async {
    final hash = await _animeService.downloadTorrentFiles(
      source: resource.downloadLink,
      filenames: episodes.map((episode) => episode.filename).toSet().toList(),
    );
    await _animeService.createAnime(
      subject: subject,
      downloadHash: hash,
      episodes: episodes,
    );
  }

  Future<void> submitEpisodesForAnime({
    required int animeId,
    required String source,
    required List<AnimeEpisodeCreate> episodes,
  }) async {
    final hash = await _animeService.downloadTorrentFiles(
      source: source,
      filenames: episodes.map((episode) => episode.filename).toSet().toList(),
    );
    await _animeService.addDownloadedEpisodes(
      animeId: animeId,
      downloadHash: hash,
      episodes: episodes,
    );
  }

  Future<AnimeGardenEpisodeMatchingContext> prepareEpisodeRematch({
    required BangumiSubject subject,
    required String downloadHash,
  }) async {
    final files = await _animeService.getTorrentFilesByHash(downloadHash);
    if (files.isEmpty) {
      throw StateError('qBittorrent 暂未返回文件列表');
    }
    final bangumiEpisodes = await _bangumiRepository.getEpisodes(subject.id);
    return AnimeGardenEpisodeMatchingContext(
      files: files,
      bangumiEpisodes: bangumiEpisodes,
    );
  }

  Future<void> submitRematchedEpisodes({
    required int animeId,
    required String downloadHash,
    required List<AnimeEpisodeCreate> episodes,
  }) async {
    await _animeService.addDownloadedEpisodes(
      animeId: animeId,
      downloadHash: downloadHash,
      episodes: episodes,
    );
  }
}
