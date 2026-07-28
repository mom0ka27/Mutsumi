import 'dart:io';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/services.dart';

const _fontAsset = 'assets/fonts/FangZhengZhunYuanJianTi-1.ttf';
const _fontFamily = '方正准圆简体';
late final String _fontPath;

Future<void> initializeAnimePlayerFont(String applicationSupportPath) async {
  final fontDirectory = Directory('$applicationSupportPath/fonts');
  await fontDirectory.create(recursive: true);
  final fontFile = File('${fontDirectory.path}/subtitle-fallback.ttf');
  final data = await rootBundle.load(_fontAsset);
  await fontFile.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  _fontPath = fontFile.path;
}

Future<void> configureAnimePlayerFont(ErikaPlayer player) async {
  await player.setSubtitleStyle(
    fontFamily: _fontFamily,
    fontFilePath: _fontPath,
    outlineWidth: 1.0,
  );
}
