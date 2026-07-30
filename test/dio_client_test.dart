import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutsumi/core/network/app_network_error.dart';
import 'package:mutsumi/core/network/dio_client.dart';

/// Serves canned responses in order and records what was sent.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._responses);

  final List<ResponseBody> _responses;
  final requests = <RequestOptions>[];

  /// Snapshotted because a retry reuses (and mutates) the same RequestOptions.
  final sentAuthorization = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    sentAuthorization.add(options.headers['Authorization'] as String?);
    return _responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group('access token', () {
    test('is read per request so a refreshed token is picked up', () async {
      var token = 'first-token';
      final adapter = _ScriptedAdapter([
        _json({'ok': true}, 200),
        _json({'ok': true}, 200),
      ]);
      final client = DioClient(
        'https://example.test',
        accessTokenProvider: () => token,
      )..dio.httpClientAdapter = adapter;

      await client.dio.get<dynamic>('/one');
      token = 'second-token';
      await client.dio.get<dynamic>('/two');

      expect(adapter.sentAuthorization, [
        'Bearer first-token',
        'Bearer second-token',
      ]);
    });

    test('is omitted when there is no token', () async {
      final adapter = _ScriptedAdapter([
        _json({'ok': true}, 200),
      ]);
      final client = DioClient('https://example.test')
        ..dio.httpClientAdapter = adapter;

      await client.dio.get<dynamic>('/one');

      expect(adapter.sentAuthorization, [null]);
    });
  });

  group('401 handling', () {
    test('refreshes the token once and replays the request', () async {
      var refreshCalls = 0;
      var token = 'expired';
      final adapter = _ScriptedAdapter([
        _json({'detail': 'Invalid authentication credentials'}, 401),
        _json({'value': 42}, 200),
      ]);
      final client = DioClient(
        'https://example.test',
        accessTokenProvider: () => token,
        refreshAccessToken: () async {
          refreshCalls++;
          token = 'refreshed';
          return token;
        },
      )..dio.httpClientAdapter = adapter;

      final response = await client.dio.get<Map<String, dynamic>>('/anime');

      expect(response.statusCode, 200);
      expect(response.data, {'value': 42});
      expect(refreshCalls, 1);
      expect(adapter.sentAuthorization, ['Bearer expired', 'Bearer refreshed']);
    });

    test(
      'surfaces the original error when the refresh yields no token',
      () async {
        final adapter = _ScriptedAdapter([
          _json({'detail': 'Invalid authentication credentials'}, 401),
        ]);
        final client = DioClient(
          'https://example.test',
          accessToken: 'expired',
          refreshAccessToken: () async => null,
        )..dio.httpClientAdapter = adapter;

        await expectLater(
          client.dio.get<dynamic>('/anime'),
          throwsA(
            isA<DioException>().having(
              (error) => error.response?.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      },
    );

    test('does not retry when the replay also fails with 401', () async {
      final adapter = _ScriptedAdapter([
        _json({'detail': 'nope'}, 401),
        _json({'detail': 'nope'}, 401),
      ]);
      final client = DioClient(
        'https://example.test',
        accessToken: 'expired',
        refreshAccessToken: () async => 'refreshed',
      )..dio.httpClientAdapter = adapter;

      await expectLater(
        client.dio.get<dynamic>('/anime'),
        throwsA(isA<Object>()),
      );
      expect(adapter.requests, hasLength(2));
    });

    test('a failing refresh does not escape as its own error', () async {
      final adapter = _ScriptedAdapter([
        _json({'detail': 'nope'}, 401),
      ]);
      final client = DioClient(
        'https://example.test',
        accessToken: 'expired',
        refreshAccessToken: () async => throw StateError('network down'),
      )..dio.httpClientAdapter = adapter;

      await expectLater(
        client.dio.get<dynamic>('/anime'),
        throwsA(isA<DioException>()),
      );
    });

    test('other status codes are not retried', () async {
      var refreshCalls = 0;
      final adapter = _ScriptedAdapter([
        _json({'detail': 'boom'}, 500),
      ]);
      final client = DioClient(
        'https://example.test',
        accessToken: 'valid',
        refreshAccessToken: () async {
          refreshCalls++;
          return 'refreshed';
        },
      )..dio.httpClientAdapter = adapter;

      await expectLater(
        client.dio.get<dynamic>('/anime'),
        throwsA(isA<DioException>()),
      );
      expect(refreshCalls, 0);
    });
  });

  group('business errors', () {
    test('lifts detail and code out of an error response', () async {
      final adapter = _ScriptedAdapter([
        _json({'detail': 'qBittorrent 尚未配置', 'code': 21001}, 503),
      ]);
      final client = DioClient('https://example.test')
        ..dio.httpClientAdapter = adapter;

      try {
        await client.dio.get<dynamic>('/qbittorrent/torrents');
        fail('expected a DioException');
      } on DioException catch (error) {
        final business = error.error;
        expect(business, isA<ApiBusinessException>());
        expect((business! as ApiBusinessException).code, 21001);
        expect(errorMessageOf(error), 'qBittorrent 尚未配置');
      }
    });

    test('a plain error response is left alone', () async {
      final adapter = _ScriptedAdapter([
        _json({'detail': 'Anime not found'}, 404),
      ]);
      final client = DioClient('https://example.test')
        ..dio.httpClientAdapter = adapter;

      try {
        await client.dio.get<dynamic>('/anime/1');
        fail('expected a DioException');
      } on DioException catch (error) {
        expect(error.error, isNot(isA<ApiBusinessException>()));
        expect(errorMessageOf(error), 'Anime not found');
      }
    });

    test(
      'a success response carrying a code field is not treated as an error',
      () async {
        final adapter = _ScriptedAdapter([
          _json({'code': 3, 'value': 'fine'}, 200),
        ]);
        final client = DioClient('https://example.test')
          ..dio.httpClientAdapter = adapter;

        final response = await client.dio.get<Map<String, dynamic>>(
          '/anything',
        );
        expect(response.data, {'code': 3, 'value': 'fine'});
      },
    );
  });
}
