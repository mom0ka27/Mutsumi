import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mutsumi/constants.dart';

import '../../anime/data/anime_service.dart';

class AnimeGardenFileField extends StatelessWidget {
  const AnimeGardenFileField({
    super.key,
    required this.files,
    required this.value,
    required this.onChanged,
  });

  final List<QBittorrentFile> files;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: const BorderRadius.all(Constants.radius),
      onTap: () async {
        final filename = await showAnimeGardenFilePicker(
          context: context,
          files: files,
          selected: value,
        );
        if (filename != null) {
          onChanged(filename);
        }
      },
      child: InputDecorator(
        isEmpty: value.isEmpty,
        decoration: InputDecoration(
          suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Constants.radius),
          ),
        ),
        child: Text(
          value.isEmpty ? '未选择文件' : value,
          style: value.isEmpty
              ? textTheme.bodyMedium?.copyWith(color: colorScheme.outline)
              : textTheme.bodyMedium,
        ),
      ),
    );
  }
}

Future<String?> showAnimeGardenFilePicker({
  required BuildContext context,
  required List<QBittorrentFile> files,
  String selected = '',
}) {
  final colorScheme = Theme.of(context).colorScheme;

  return Get.bottomSheet<String>(
    DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Material(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选择文件',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: Get.back,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final isSelected = file.name == selected;
                    final paths = file.name.split("/");
                    final filename = paths.length > 1 ? paths.skip(1).join("/") : file.name;
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: colorScheme.primaryContainer
                          .withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Constants.radius),
                      ),
                      leading: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.movie_outlined,
                        color: isSelected ? colorScheme.primary : null,
                      ),
                      title: Text(filename),
                      subtitle: Text(_formatFileSize(file.size)),
                      onTap: () => Get.back(result: file.name),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemCount: files.length,
                ),
              ),
            ],
          ),
        );
      },
    ),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
  );
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) {
    return '未知大小';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
}
