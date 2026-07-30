import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as image;

import '../../../core/logging/app_logger.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../player/controller.dart';
import '../../../player/model/danmaku.dart';
import '../../../player/model/playlist.dart';
import '../../../player/model/option.dart';
import '../../../player/model/player_settings.dart';
import '../../../player/model/player_settings_repository.dart';
import '../../../player/model/video.dart';
import '../data/anime_service.dart';
import 'anime_player_font.dart';

class AnimePlayController extends GetxController {
  AnimePlayController({
    required this.anime,
    required this.episodes,
    required this.initialEpisode,
    AnimeService? animeService,
  }) : _animeService = animeService ?? AnimeService() {
    _coverArtwork = _loadCoverArtwork();
    _progressSyncer = _WatchProgressSyncer(
      onSync: (snapshot) => _animeService.updateWatchProgress(
        animeId: anime.id,
        episodeId: snapshot.episodeId,
        position: snapshot.position,
      ),
    );
    playerController = IndexPlayerController(
      options: _playerOptions(
        Get.find<PlayerSettingsRepository>().settings.value,
      ),
      playlist: PlayerPlaylist(
        title: anime.displayName,
        items: episodes
            .map(
              (episode) => PlayerPlaylistItem(
                id: episode.id,
                number: episode.index,
                title: episode.displayName,
                initialPosition: anime.watchProgress?.episodeId == episode.id
                    ? anime.watchProgress?.position
                    : null,
                load: () => _loadEpisodeMedia(episode),
              ),
            )
            .toList(growable: false),
      ),
      onItemLeaving: _syncProgress,
    );
    _playerFontReady = configureAnimePlayerFont(playerController.player);
  }

  static IndexPlayerOptions _playerOptions(PlayerSettings settings) =>
      IndexPlayerOptions(
        backgroundPlayback: settings.backgroundPlayback,
        availableSpeeds: settings.availableSpeeds,
        longPressSpeed: settings.longPressSpeed,
      );

  final AnimeRead anime;
  final List<AnimeEpisodeRead> episodes;
  final int initialEpisode;
  final AnimeService _animeService;
  late final IndexPlayerController playerController;
  late final _WatchProgressSyncer _progressSyncer;
  late final Future<void> _playerFontReady;
  late final Future<Uint8List?> _coverArtwork;
  Timer? _progressTimer;
  StreamSubscription<String>? _errorSubscription;
  Future<void>? _closing;
  bool _closed = false;
  bool _showingError = false;

  int get currentIndex =>
      playerController.selectedIndex.value ??
      playerController.loadingIndex.value ??
      initialEpisode.clamp(0, episodes.length - 1);

  AnimeEpisodeRead get episode => episodes[currentIndex];

  @override
  void onInit() {
    super.onInit();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    _errorSubscription = playerController.errorStream.listen(_showPlayerError);
    if (AppPlatform.isDesktop) {
      unawaited(playerController.enterFullscreen());
    }
    if (episodes.isEmpty) {
      return;
    }
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(saveProgress()),
    );
    unawaited(
      playerController.selectIndex(
        initialEpisode.clamp(0, episodes.length - 1),
      ),
    );
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (_closed) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(saveProgress());
    }
    if (state == AppLifecycleState.resumed &&
        playerController.isFullScreen.value &&
        !playerController.disposed) {
      playerController.restoreFullscreenOrientation();
    }
  }

  Future<void> enterFullscreenForLandscape() async {
    if (_closed || playerController.isFullScreen.value) {
      return;
    }
    await playerController.enterFullscreen();
  }

  Future<void> saveProgress() async {
    final snapshot = playerController.currentSnapshot;
    if (playerController.disposed || snapshot == null) {
      return;
    }
    await _syncProgress(snapshot);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _progressTimer?.cancel();
    await _errorSubscription?.cancel();
    await saveProgress();
    if (playerController.isFullScreen.value) {
      await playerController.exitFullscreen();
    }
    await playerController.pause();
    await playerController.close();
  }

  Future<PlayerMedia> _loadEpisodeMedia(AnimeEpisodeRead episode) async {
    await _playerFontReady.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    final artwork = await _coverArtwork;
    final fileHash = await _animeService.fetchEpisodeFileHash(
      anime.id,
      episode.id,
    );
    final subtitlePaths = <String>[];
    try {
      final subtitles = await _animeService.listEpisodeSubtitles(
        anime.id,
        episode.id,
      );
      for (final subtitle in subtitles) {
        final subtitlePath = await _animeService.downloadEpisodeSubtitle(
          animeId: anime.id,
          episodeId: episode.id,
          filename: subtitle.filename,
        );
        if (subtitlePath != null) {
          subtitlePaths.add(subtitlePath);
        }
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        '搜索字幕失败，将继续播放视频',
        tag: 'AnimePlayer',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return PlayerMedia(
      video: NetworkVideo(
        index: episode.index,
        uri: _animeService.episodeVideoUrl(
          animeId: anime.id,
          episodeId: episode.id,
        ),
        title: episode.displayName,
        artwork: artwork,
        httpHeaders: _animeService.authHeaders(),
        danmakuProvider: DandanPlayDanmakuProvider(
          fileHash: fileHash,
          fileName: episode.filename,
          airDate: anime.airDate,
        ),
      ),
      externalSubtitlePaths: subtitlePaths,
    );
  }

  Future<Uint8List?> _loadCoverArtwork() async {
    final url = anime.imageUrl.trim();
    if (url.isEmpty) {
      return null;
    }
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      final cover = image.decodeImage(bytes);
      if (cover == null) {
        return null;
      }
      final resized = image.copyResize(cover, width: 384);
      return Uint8List.fromList(image.encodeJpg(resized, quality: 85));
    } catch (error, stackTrace) {
      AppLogger.error(
        '加载播放封面失败，将继续播放视频',
        tag: 'AnimePlayer',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _showPlayerError(Object error) async {
    final message = errorMessageOf(error);
    if (_closed || _showingError || message.trim().isEmpty) {
      return;
    }
    _showingError = true;
    await showErrorDialog(title: '播放出错', message: message, error: error);
    _showingError = false;
  }

  Future<void> _syncProgress(PlayerPlaybackSnapshot snapshot) async {
    if (snapshot.position == Duration.zero) {
      return;
    }
    final episodeId = snapshot.itemId as int;
    await _progressSyncer.enqueue(
      _WatchProgressSnapshot(episodeId: episodeId, position: snapshot.position),
    );
    anime.watchProgress = WatchProgressRead(
      episodeId: episodeId,
      position: snapshot.position,
    );
  }

  @override
  void onClose() {
    unawaited(close());
    super.onClose();
  }
}

class _WatchProgressSnapshot {
  const _WatchProgressSnapshot({
    required this.episodeId,
    required this.position,
  });

  final int episodeId;
  final Duration position;

  @override
  bool operator ==(Object other) {
    return other is _WatchProgressSnapshot &&
        episodeId == other.episodeId &&
        position.inSeconds == other.position.inSeconds;
  }

  @override
  int get hashCode => Object.hash(episodeId, position.inSeconds);
}

class _WatchProgressSyncer {
  _WatchProgressSyncer({required this.onSync});

  final Future<void> Function(_WatchProgressSnapshot snapshot) onSync;
  _WatchProgressSnapshot? _pending;
  _WatchProgressSnapshot? _lastSynced;
  Future<void>? _draining;

  Future<void> enqueue(_WatchProgressSnapshot snapshot) {
    if (snapshot.position == Duration.zero ||
        snapshot == _pending ||
        snapshot == _lastSynced) {
      return _draining ?? Future.value();
    }
    _pending = snapshot;
    return _draining ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final snapshot = _pending!;
        _pending = null;
        try {
          await onSync(snapshot);
          _lastSynced = snapshot;
        } catch (error, stackTrace) {
          AppLogger.error(
            '播放进度同步失败',
            tag: 'Anime',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      _draining = null;
    }
  }
}
