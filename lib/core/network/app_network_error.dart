import 'dart:io';

import 'package:dio/dio.dart';

class ApiBusinessException implements Exception {
  const ApiBusinessException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => message;
}

String errorMessageOf(Object error) {
  if (error is ApiBusinessException) return error.message;
  if (error is DioException) {
    final businessError = error.error;
    if (businessError is ApiBusinessException) return businessError.message;
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '请求超时，请检查服务器状态或网络连接';
    }
    if (error.error is SocketException ||
        error.type == DioExceptionType.connectionError) {
      return '无法连接服务器，请检查地址、网络或证书指纹';
    }
    if ((error.response?.statusCode ?? 0) >= 500) {
      return '服务器暂时异常，请稍后重试';
    }
    return error.message ?? '请求失败';
  }
  return error.toString();
}
