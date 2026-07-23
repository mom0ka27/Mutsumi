import 'dart:io';

import 'package:dio/dio.dart';

class ApiBusinessException implements Exception {
  const ApiBusinessException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => message;
}

class AppErrorInfo {
  const AppErrorInfo({required this.message, this.details});

  final String message;
  final String? details;
}

AppErrorInfo errorInfoOf(Object error) {
  final message = errorMessageOf(error);
  String? details;

  if (error is ApiBusinessException) {
    details = '业务错误码：${error.code}\n${error.message}';
  } else if (error is DioException) {
    final request = error.requestOptions;
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;
    details = [
      '错误类型：${error.type.name}',
      if (statusCode != null) 'HTTP 状态码：$statusCode',
      '请求：${request.method} ${request.uri}',
      if (responseData != null) '响应：$responseData',
      if (error.error != null) '底层原因：${error.error}',
    ].join('\n');
  } else {
    details = error.toString();
  }

  if (details == message || details.isEmpty) {
    details = null;
  }
  return AppErrorInfo(message: message, details: details);
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
    return '请求失败，请稍后重试';
  }
  return '操作未完成，请稍后重试';
}
