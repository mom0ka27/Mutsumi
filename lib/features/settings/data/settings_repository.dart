import 'package:hive_ce/hive.dart';

import '../../../core/storage/local_storage.dart';

class SettingsRepository {
  SettingsRepository() : _box = Hive.box(LocalStorage.settingsBoxName);

  static const _serverUrlKey = 'server_url';
  static const _serverUrlsKey = 'server_urls';
  static const _currentServerUrlKey = 'current_server_url';
  static const _certificateFingerprintsKey = 'certificate_fingerprints';
  static const _serverNamesKey = 'server_names';
  static const _serverCredentialsKey = 'server_credentials';
  static const _serverTokensKey = 'server_tokens';

  final Box _box;

  String getServerUrl() {
    return getCurrentServerUrl() ?? '';
  }

  Future<void> setServerUrl(String value) {
    return addServerUrl(value);
  }

  List<String> getServerUrls() {
    final values = _box.get(_serverUrlsKey);
    final servers = values is List
        ? values.whereType<String>().where((value) => value.isNotEmpty).toList()
        : <String>[];

    final legacyServer = _box.get(_serverUrlKey);
    if (legacyServer is String && legacyServer.isNotEmpty) {
      servers.add(legacyServer);
    }

    return servers.toSet().toList();
  }

  bool hasServerUrl(String value) {
    final normalized = _normalizeUrl(value);
    if (normalized.isEmpty) {
      return false;
    }
    return getServerUrls().contains(normalized);
  }

  String? getCurrentServerUrl() {
    final current = _box.get(_currentServerUrlKey);
    if (current is String && current.isNotEmpty) {
      return current;
    }

    final legacyServer = _box.get(_serverUrlKey);
    if (legacyServer is String && legacyServer.isNotEmpty) {
      return legacyServer;
    }

    final servers = getServerUrls();
    return servers.isEmpty ? null : servers.first;
  }

  String getServerName(String serverUrl) {
    final normalized = _normalizeUrl(serverUrl);
    final names = _getServerNames();
    final name = names[normalized];
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return normalized;
  }

  ServerCredential? getServerCredential(String serverUrl) {
    final credentials = _getServerCredentials();
    final value = credentials[_normalizeUrl(serverUrl)];
    if (value == null) {
      return null;
    }

    final username = value['username'];
    final password = value['password'];
    if (username == null || password == null) {
      return null;
    }

    return ServerCredential(username: username, password: password);
  }

  String? getAccessToken(String serverUrl) {
    final tokens = _getServerTokens();
    return tokens[_normalizeUrl(serverUrl)];
  }

  String? getCertificateFingerprint(String serverUrl) {
    final fingerprints = _getCertificateFingerprints();
    return fingerprints[_normalizeUrl(serverUrl)];
  }

  Future<void> addServerUrl(
    String value, {
    String? certificateFingerprint,
    String? serverName,
  }) async {
    final normalized = _normalizeUrl(value);
    if (normalized.isEmpty) {
      return;
    }

    final servers = getServerUrls();
    if (!servers.contains(normalized)) {
      servers.add(normalized);
    }

    await _box.put(_serverUrlsKey, servers);
    await setCurrentServerUrl(normalized);
    await setCertificateFingerprint(normalized, certificateFingerprint);
    if (serverName != null && serverName.trim().isNotEmpty) {
      await setServerName(normalized, serverName);
    }
  }

  Future<void> setCurrentServerUrl(String value) async {
    final normalized = _normalizeUrl(value);
    if (normalized.isEmpty) {
      return;
    }

    await _box.put(_currentServerUrlKey, normalized);
    await _box.put(_serverUrlKey, normalized);
  }

  Future<void> setServerName(String serverUrl, String serverName) async {
    final normalized = _normalizeUrl(serverUrl);
    final normalizedName = serverName.trim();
    if (normalized.isEmpty || normalizedName.isEmpty) {
      return;
    }

    final names = _getServerNames();
    names[normalized] = normalizedName;
    await _box.put(_serverNamesKey, names);
  }

  Future<void> setServerCredential(
    String serverUrl, {
    required String username,
    required String password,
  }) async {
    final normalized = _normalizeUrl(serverUrl);
    if (normalized.isEmpty) {
      return;
    }

    final credentials = _getServerCredentials();
    credentials[normalized] = {'username': username, 'password': password};
    await _box.put(_serverCredentialsKey, credentials);
  }

  Future<void> setAccessToken(String serverUrl, String accessToken) async {
    final normalized = _normalizeUrl(serverUrl);
    if (normalized.isEmpty || accessToken.isEmpty) {
      return;
    }

    final tokens = _getServerTokens();
    tokens[normalized] = accessToken;
    await _box.put(_serverTokensKey, tokens);
  }

  Future<void> setCertificateFingerprint(
    String serverUrl,
    String? certificateFingerprint,
  ) async {
    final normalized = _normalizeUrl(serverUrl);
    if (normalized.isEmpty) {
      return;
    }

    final fingerprints = _getCertificateFingerprints();
    final normalizedFingerprint = _normalizeFingerprint(
      certificateFingerprint ?? '',
    );
    if (normalizedFingerprint.isEmpty) {
      fingerprints.remove(normalized);
    } else {
      fingerprints[normalized] = normalizedFingerprint;
    }
    await _box.put(_certificateFingerprintsKey, fingerprints);
  }

  Map<String, String> _getServerNames() {
    final values = _box.get(_serverNamesKey);
    if (values is! Map) {
      return {};
    }

    return values.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  Map<String, String> _getCertificateFingerprints() {
    final values = _box.get(_certificateFingerprintsKey);
    if (values is! Map) {
      return {};
    }

    return values.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  Map<String, Map<String, String>> _getServerCredentials() {
    final values = _box.get(_serverCredentialsKey);
    if (values is! Map) {
      return {};
    }

    return values.map((key, value) {
      final credential = value is Map
          ? value.map((entryKey, entryValue) {
              return MapEntry(entryKey.toString(), entryValue.toString());
            })
          : <String, String>{};
      return MapEntry(key.toString(), credential);
    });
  }

  Map<String, String> _getServerTokens() {
    final values = _box.get(_serverTokensKey);
    if (values is! Map) {
      return {};
    }

    return values.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String _normalizeFingerprint(String value) {
    return value.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
  }
}

class ServerCredential {
  const ServerCredential({required this.username, required this.password});

  final String username;
  final String password;
}
