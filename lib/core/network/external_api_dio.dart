import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mutsumi/main.dart';

Dio createExternalApiDio(String baseUrl) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
        'user-agent':
            "mom0ka27/Mutsumi/${packageInfo.version}+${packageInfo.buildNumber}(${Platform.operatingSystem})",
      },
    ),
  );
}
