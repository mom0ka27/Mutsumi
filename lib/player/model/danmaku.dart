import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mutsumi/core/logging/app_logger.dart';
import 'package:ns_danmaku/ns_danmaku.dart';

import '../exception/illegal_data.dart';
import 'dandanplay_repository.dart';

class DanmakuList {
  Map<int, List<DanmakuItem>> danmakuList = {};

  void addDanmaku(int second, DanmakuItem danmaku) {
    final list = danmakuList[second] ?? [];
    list.add(danmaku);
    danmakuList[second] = list;
  }

  List<DanmakuItem> getDanmakus(int second) {
    return danmakuList[second] ?? [];
  }
}

abstract class DanmakuProvider {
  Future<DanmakuLoadResult> getDanmakuList();
}

class DanmakuLoadResult {
  const DanmakuLoadResult({
    required this.list,
    required this.count,
    this.episodeId,
  });

  final DanmakuList list;
  final int count;
  final int? episodeId;
}

class DandanPlayDanmakuProvider extends DanmakuProvider {
  DandanPlayDanmakuProvider({
    required this.fileHash,
    required this.fileName,
    this.airDate,
  });

  final String? fileHash;
  final String fileName;
  final String? airDate;

  @override
  Future<DanmakuLoadResult> getDanmakuList() async {
    final hash = fileHash ?? "";
    if (hash.isEmpty) {
      return DanmakuLoadResult(list: DanmakuList(), count: 0);
    }
    AppLogger.info('Loading danmaku for $fileName($hash)');
    try {
      final result = await Get.find<DandanPlayRepository>().commentsForFile(
        fileHash: hash,
        fileName: fileName,
        airDate: airDate,
      );
      final list = DanmakuList();
      var count = 0;
      for (final comment in result.comments) {
        try {
          final danmaku = fromJson(comment);
          list.addDanmaku(danmaku.time, danmaku);
          count++;
        } catch (_) {}
      }
      return DanmakuLoadResult(
        list: list,
        count: count,
        episodeId: result.episodeId,
      );
    } catch (_) {
      return DanmakuLoadResult(list: DanmakuList(), count: 0);
    }
  }

  static DanmakuItem fromJson(Map<String, dynamic> d) {
    final text = d["m"] as String? ?? '';
    final p = (d["p"] as String).split(",");
    final modeValue = int.parse(p[1]);
    DanmakuItemType type;
    if (modeValue >= 1 && modeValue <= 3) {
      type = DanmakuItemType.scroll;
    } else if (modeValue == 4) {
      type = DanmakuItemType.bottom;
    } else if (modeValue == 5) {
      type = DanmakuItemType.top;
    } else {
      throw IllegalDataException(
        source: "DandanPlay",
        key: "danmalu.p[1](mode)",
        illegalValue: modeValue,
        expection: "[1, 5]",
      );
    }
    final color = Color(int.parse(p[2]) + (255 << 24));
    return DanmakuItem(
      text,
      color: color,
      time: (double.parse(p[0])).toInt(),
      type: type,
    );
  }
}
