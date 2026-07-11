import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:ns_danmaku/ns_danmaku.dart';

import '../exception/illegal_data.dart';

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
  int epID;

  DandanPlayDanmakuProvider({required this.epID});

  static final _dio = Dio(
    BaseOptions(
      baseUrl: "https://api.dandanplay.net",
      headers: {"User-Agent": "IndexPlayer/${Platform.operatingSystem} 1.0.0"},
      connectTimeout: Duration(seconds: 5),
      sendTimeout: Duration(seconds: 5),
      receiveTimeout: Duration(seconds: 5),
    ),
  );

  @override
  Future<DanmakuList> getDanmakuList() async {
    int times = 0;
    while (times++ < 5) {
      try {
        final resp = await _dio.get(
          "/api/v2/comment/$epID",
          queryParameters: {"withRelated": "true", "chConvert": "1"},
        );
        final list = (resp.data["comments"] as List)
            .map((c) => fromJson(c))
            .toList();

        DanmakuList result = DanmakuList();
        for (final d in list) {
          result.addDanmaku(d.time, d);
        }
        return result;
      } catch (e, st) {
        debugPrint("ERROR: $e");
        debugPrintStack(stackTrace: st);
        await Future.delayed(Duration(seconds: 1));
      }
    }
    return DanmakuList();
  }

  static DanmakuItem fromJson(Map<String, dynamic> d) {
    // text
    var text = d["m"];

    // 0.00,1,16777215,[Gamer]a729864919
    var p = (d["p"] as String).split(",");

    // type
    int modeValue = int.parse(p[1]);
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
    // color
    var color = Color(int.parse(p[2]) + (255 << 24)); // 不透明度
    return DanmakuItem(
      text,
      color: color,
      time: (double.parse(p[0])).toInt(),
      type: type,
    );
  }
}
