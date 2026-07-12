import 'package:flutter/material.dart';
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
  Future<DanmakuList> getDanmakuList();
}

class DandanPlayDanmakuProvider extends DanmakuProvider {
  DandanPlayDanmakuProvider({required this.fileHash, required this.fileName});

  final String? fileHash;
  final String fileName;

  @override
  Future<DanmakuList> getDanmakuList() async {
    final hash = fileHash;
    if (hash == null || hash.isEmpty) {
      return DanmakuList();
    }
    try {
      final comments = await DandanPlayRepository.instance.commentsForFile(
        fileHash: hash,
        fileName: fileName,
      );
      final result = DanmakuList();
      for (final comment in comments) {
        final danmaku = fromJson(comment);
        result.addDanmaku(danmaku.time, danmaku);
      }
      return result;
    } catch (_) {
      return DanmakuList();
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
