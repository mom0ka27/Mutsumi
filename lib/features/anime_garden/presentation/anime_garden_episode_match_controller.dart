import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../anime/data/anime_list_store.dart';
import '../../../core/network/app_network_error.dart';
import '../../anime/data/anime_service.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/app_dialog.dart';
import '../data/anime_garden_download_coordinator.dart';
import '../data/anime_garden_repository.dart';
import 'anime_garden_file_picker.dart';

class EpisodeFileMatch {
  EpisodeFileMatch({
    required this.index,
    required this.name,
    required this.filename,
    this.bangumiEpisode,
  });

  final int index;
  String name;
  String filename;
  final BangumiEpisode? bangumiEpisode;

  String get title {
    if (name.isEmpty) {
      return 'Episode $index';
    }
    return 'Episode $index · $name';
  }

  AnimeEpisodeCreate toCreate() {
    return AnimeEpisodeCreate(index: index, name: name, filename: filename);
  }
}

class AnimeGardenEpisodeMatchController extends GetxController {
  AnimeGardenEpisodeMatchController({
    required this.subject,
    this.resource,
    required List<QBittorrentFile> files,
    required List<BangumiEpisode> bangumiEpisodes,
    AnimeGardenDownloadCoordinator? downloadCoordinator,
    this._animeListStore,
    this.onSave,
  }) : _downloadCoordinator =
           downloadCoordinator ?? AnimeGardenDownloadCoordinator() {
    _files.addAll(files);
    _bangumiEpisodes.addAll(bangumiEpisodes);
  }

  final BangumiSubject subject;
  final AnimeGardenResource? resource;
  final AnimeGardenDownloadCoordinator _downloadCoordinator;
  final AnimeListStore? _animeListStore;
  final Future<void> Function(List<AnimeEpisodeCreate> episodes)? onSave;
  final _files = <QBittorrentFile>[];
  final _bangumiEpisodes = <BangumiEpisode>[];
  final matches = <EpisodeFileMatch>[].obs;
  final saving = false.obs;

  List<QBittorrentFile> get videoFiles {
    final result = _files.where(_isVideoFile).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  @override
  void onInit() {
    super.onInit();
    _buildDefaultMatches();
  }

  void setFilename(int index, String filename) {
    matches[index].filename = filename;
    matches.refresh();
  }

  Future<void> editEpisodeName(int index) async {
    final match = matches[index];
    final result = await showAppDialog<String>(
      _EpisodeNameDialog(episodeIndex: match.index, initialName: match.name),
    );
    if (result == null) {
      return;
    }

    match.name = result;
    matches.refresh();
  }

  Future<void> addEpisode() async {
    final result = await showAppDialog<_ManualEpisodeResult>(
      _ManualEpisodeDialog(
        initialIndex: _nextEpisodeIndex(),
        files: videoFiles,
      ),
    );
    if (result == null) {
      return;
    }

    matches.add(
      EpisodeFileMatch(
        index: result.index,
        name: result.name,
        filename: result.filename,
      ),
    );
    matches.sort((a, b) => a.index.compareTo(b.index));
  }

  void removeEpisode(int index) {
    matches.removeAt(index);
  }

  Future<void> save() async {
    final emptyMatches = matches
        .where((match) => match.filename.isEmpty)
        .toList();
    if (emptyMatches.isNotEmpty) {
      await showErrorDialog(
        title: '无法保存',
        message: '还有 ${emptyMatches.length} 个 Episode 未选择文件，请先完成匹配或移除。',
      );
      return;
    }

    if (matches.isEmpty) {
      await showErrorDialog(title: '无法保存', message: '请至少保留一个 Episode');
      return;
    }

    final duplicateFilenames = _duplicateValues(
      matches.map((match) => match.filename),
    );
    final duplicateIndexes = _duplicateValues(
      matches.map((match) => match.index.toString()),
    );
    if (duplicateFilenames.isNotEmpty || duplicateIndexes.isNotEmpty) {
      final confirmed = await _confirmDuplicateMatches(
        duplicateFilenames: duplicateFilenames,
        duplicateIndexes: duplicateIndexes,
      );
      if (!confirmed) {
        return;
      }
    }

    final episodes = matches.map((match) => match.toCreate()).toList();

    saving.value = true;
    try {
      if (onSave != null) {
        await onSave!(episodes);
        _refreshAnimeList();
        Get
          ..back()
          ..snackbar('已添加', 'Anime 和 Episode 已保存到服务器');
      } else {
        await _downloadCoordinator.submitEpisodeSelection(
          subject: subject,
          resource: resource!,
          episodes: episodes,
        );
        _refreshAnimeList();
        Get
          ..back()
          ..back()
          ..snackbar('已添加', 'Anime、BT 任务和 Episode 已保存到服务器');
      }
    } catch (error) {
      await showErrorDialog(title: '添加失败', message: errorMessageOf(error));
    } finally {
      saving.value = false;
    }
  }

  void _refreshAnimeList() {
    _animeListStore?.refresh();
  }

  List<String> _duplicateValues(Iterable<String> values) {
    final counts = <String, int>{};
    for (final value in values) {
      if (value.isEmpty) {
        continue;
      }
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return counts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toList();
  }

  Future<bool> _confirmDuplicateMatches({
    required List<String> duplicateFilenames,
    required List<String> duplicateIndexes,
  }) async {
    final messages = <String>[];
    if (duplicateIndexes.isNotEmpty) {
      messages.add('重复集数：${duplicateIndexes.join('、')}');
    }
    if (duplicateFilenames.isNotEmpty) {
      messages.add(
        '重复文件：${duplicateFilenames.map((name) => name.split('/').last).join('、')}',
      );
    }

    final result = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('发现重复匹配'),
        content: Text('${messages.join('\n')}\n\n仍然要继续添加吗？'),
        actions: [
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AppDialog.dismiss(context, false),
              child: const Text('取消'),
            ),
          ),
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppDialog.dismiss(context, true),
              child: const Text('继续添加'),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _buildDefaultMatches() {
    final sortedFiles = videoFiles
        .where((file) => file.size > 1024 * 1024 * 10)
        .toList();
    final defaultMatches = <EpisodeFileMatch>[];
    for (final episode in _bangumiEpisodes) {
      final targetFiles = episode.index == 0
          ? const <QBittorrentFile>[]
          : sortedFiles
                .where(
                  (file) => _matchesEpisodeIndex(
                    file.name.split('/').last,
                    episode.index,
                  ),
                )
                .toList();

      defaultMatches.add(
        EpisodeFileMatch(
          index: episode.index,
          name: episode.displayName,
          filename: targetFiles.length == 1 ? targetFiles.single.name : '',
          bangumiEpisode: episode,
        ),
      );
    }

    if (defaultMatches.isEmpty) {
      for (var i = 0; i < sortedFiles.length; i++) {
        defaultMatches.add(
          EpisodeFileMatch(
            index: i + 1,
            name: '',
            filename: sortedFiles[i].name,
          ),
        );
      }
    }

    matches.assignAll(defaultMatches);
  }

  bool _matchesEpisodeIndex(String filename, int index) {
    if (RegExp(
      r'\b(?:tokuten|pv|ncop|nced)\b',
      caseSensitive: false,
    ).hasMatch(filename)) {
      return false;
    }
    final number = index.toString();
    final paddedNumber = number.padLeft(2, '0');
    final numbers = number == paddedNumber ? number : '$number|$paddedNumber';
    return RegExp(
      '\\[(?:$numbers)\\]|E(?:$numbers)(?![A-Za-z0-9])|\\s(?:$numbers)\\s',
      caseSensitive: false,
    ).hasMatch(filename);
  }

  int _nextEpisodeIndex() {
    if (matches.isEmpty) {
      return 1;
    }
    return matches.map((match) => match.index).reduce((a, b) => a > b ? a : b) +
        1;
  }

  bool _isVideoFile(QBittorrentFile file) {
    final name = file.name.toLowerCase();
    return name.endsWith('.mkv') ||
        name.endsWith('.mp4') ||
        name.endsWith('.avi') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm');
  }
}

class _EpisodeNameDialog extends StatefulWidget {
  const _EpisodeNameDialog({
    required this.episodeIndex,
    required this.initialName,
  });

  final int episodeIndex;
  final String initialName;

  @override
  State<_EpisodeNameDialog> createState() => _EpisodeNameDialogState();
}

class _EpisodeNameDialogState extends State<_EpisodeNameDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Episode ${widget.episodeIndex}'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Episode 名称'),
        onSubmitted: (value) => AppDialog.dismiss(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => AppDialog.dismiss(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              AppDialog.dismiss(context, _nameController.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ManualEpisodeResult {
  const _ManualEpisodeResult({
    required this.index,
    required this.name,
    required this.filename,
  });

  final int index;
  final String name;
  final String filename;
}

class _ManualEpisodeDialog extends StatefulWidget {
  const _ManualEpisodeDialog({required this.initialIndex, required this.files});

  final int initialIndex;
  final List<QBittorrentFile> files;

  @override
  State<_ManualEpisodeDialog> createState() => _ManualEpisodeDialogState();
}

class _ManualEpisodeDialogState extends State<_ManualEpisodeDialog> {
  late final TextEditingController _indexController;
  final _nameController = TextEditingController();
  final _filename = ''.obs;

  @override
  void initState() {
    super.initState();
    _indexController = TextEditingController(
      text: widget.initialIndex.toString(),
    );
  }

  @override
  void dispose() {
    _indexController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加 Episode'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _indexController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '集数'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '标题（可选）'),
            ),
            const SizedBox(height: 12),
            Obx(
              () => AnimeGardenFileField(
                files: widget.files,
                value: _filename.value,
                onChanged: (value) => _filename.value = value,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => AppDialog.dismiss(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final index = int.tryParse(_indexController.text.trim());
            if (index == null || index <= 0) {
              await showErrorDialog(title: '无法添加', message: '请输入有效集数');
              return;
            }
            AppDialog.dismiss(
              context,
              _ManualEpisodeResult(
                index: index,
                name: _nameController.text.trim(),
                filename: _filename.value,
              ),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}
