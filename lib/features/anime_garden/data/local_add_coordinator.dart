import '../../anime/data/anime_service.dart';
import '../../bangumi/data/bangumi_repository.dart';

class LocalAddCoordinator {
  LocalAddCoordinator({
    AnimeService? animeService,
    BangumiRepository? bangumiRepository,
  }) : _animeService = animeService ?? AnimeService(),
       _bangumiRepository = bangumiRepository ?? BangumiRepository();

  final AnimeService _animeService;
  final BangumiRepository _bangumiRepository;

  Future<String> createFolder(int bangumiId) async {
    return _animeService.createLocalFolder(bangumiId);
  }

  Future<List<QBittorrentFile>> listFiles(String folderId) async {
    return _animeService.listLocalFiles(folderId);
  }

  Future<List<BangumiEpisode>> getBangumiEpisodes(int subjectId) async {
    return _bangumiRepository.getEpisodes(subjectId);
  }

  Future<void> submitLocalAdd({
    required BangumiSubject subject,
    required String folderId,
    required List<AnimeEpisodeCreate> episodes,
  }) async {
    await _animeService.createAnime(
      subject: subject,
      downloadHash: folderId,
      episodes: episodes,
    );
  }
}
