import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/storage/local_storage.dart';

class SettingsRepository {
  SettingsRepository() : _box = Hive.box(LocalStorage.settingsBoxName);

  static const _secureStorage = FlutterSecureStorage();

  static const _storageKey = 'settings_v2';
  static const _serverUrlKey = 'server_url';
  static const _serverUrlsKey = 'server_urls';
  static const _currentServerUrlKey = 'current_server_url';
  static const _certificateFingerprintsKey = 'certificate_fingerprints';
  static const _serverNamesKey = 'server_names';
  static const _serverCredentialsKey = 'server_credentials';
  static const _serverTokensKey = 'server_tokens';
  final Box _box;

  static Future<void> migrate() async {
    final repository = SettingsRepository();
    if (repository._box.get(_storageKey) is Map) {
      return;
    }
    final servers = repository._legacyServerUrls();
    final currentUrl = repository._legacyCurrentServerUrl(servers);
    final names = repository._stringMap(_serverNamesKey);
    final fingerprints = repository._stringMap(_certificateFingerprintsKey);
    final credentials = repository._nestedStringMap(_serverCredentialsKey);
    final tokens = repository._stringMap(_serverTokensKey);
    final accounts = <String, dynamic>{};
    for (final entry in credentials.entries) {
      final username = entry.value['username'];
      final password = entry.value['password'];
      if (username == null || password == null) {
        continue;
      }
      final normalized = SettingsRepository._normalizeUrl(entry.key);
      await _secureStorage.write(
        key: _secureKey(normalized, username),
        value: password,
      );
      accounts[repository._accountKey(entry.key, username)] = {
        'server_url': SettingsRepository._normalizeUrl(entry.key),
        'username': username,
        'access_token': tokens[entry.key] ?? '',
      };
    }
    final currentCredential = currentUrl == null
        ? null
        : credentials[currentUrl];
    await repository._box.put(_storageKey, {
      'servers': servers
          .map(
            (url) => {
              'url': url,
              'name': names[url] ?? '',
              'certificate_fingerprint': fingerprints[url] ?? '',
            },
          )
          .toList(),
      'accounts': accounts,
      'current_account': currentUrl == null || currentCredential == null
          ? null
          : repository._accountKey(
              currentUrl,
              currentCredential['username'] ?? '',
            ),
    });
  }

  String getServerUrl() => getCurrentServerUrl() ?? '';

  Future<void> setServerUrl(String value) async {
    final account = getAccounts(value).firstOrNull;
    if (account != null) {
      await setCurrentAccount(value, account.username);
    }
  }

  List<String> getServerUrls() =>
      _servers().map((server) => server.url).toList();

  bool hasServerUrl(String value) =>
      getServerUrls().contains(_normalizeUrl(value));

  String? getCurrentServerUrl() => getCurrentAccount()?.serverUrl;

  ServerAccount? getCurrentAccount() {
    final data = _data();
    final key = data['current_account'];
    return key is String ? _accountFromValue(data['accounts']?[key]) : null;
  }

  List<ServerAccount> getAccounts([String? serverUrl]) {
    final normalized = serverUrl == null ? null : _normalizeUrl(serverUrl);
    final values = _data()['accounts'];
    if (values is! Map) {
      return [];
    }
    return values.values
        .map(_accountFromValue)
        .whereType<ServerAccount>()
        .where(
          (account) => normalized == null || account.serverUrl == normalized,
        )
        .toList();
  }

  String getServerName(String serverUrl) {
    final normalized = _normalizeUrl(serverUrl);
    return _servers()
            .where((server) => server.url == normalized)
            .firstOrNull
            ?.name ??
        normalized;
  }

  Future<ServerCredential?> getServerCredential(String serverUrl) async {
    final current = getCurrentAccount();
    if (current != null && current.serverUrl == _normalizeUrl(serverUrl)) {
      final password =
          await _secureStorage.read(
            key: _secureKey(current.serverUrl, current.username),
          ) ??
          '';
      return ServerCredential(username: current.username, password: password);
    }
    return null;
  }

  String? getAccessToken(String serverUrl) {
    final current = getCurrentAccount();
    return current?.serverUrl == _normalizeUrl(serverUrl)
        ? current?.accessToken
        : null;
  }

  String? getCertificateFingerprint(String serverUrl) => _servers()
      .where((server) => server.url == _normalizeUrl(serverUrl))
      .firstOrNull
      ?.certificateFingerprint;

  Future<void> saveLogin({
    required String serverUrl,
    required String username,
    required String password,
    required String accessToken,
    required String permissionGroup,
    String? certificateFingerprint,
    String? serverName,
  }) async {
    final normalized = _normalizeUrl(serverUrl);
    final data = _data();
    final servers = _mutableList(data['servers']);
    final index = servers.indexWhere(
      (value) => value is Map && value['url'] == normalized,
    );
    final server = {
      'url': normalized,
      'name': serverName?.trim().isNotEmpty == true
          ? serverName!.trim()
          : getServerName(normalized),
      'certificate_fingerprint': _normalizeFingerprint(
        certificateFingerprint ?? '',
      ),
    };
    if (index < 0) {
      servers.add(server);
    } else {
      final previous = Map<String, dynamic>.from(servers[index] as Map);
      server['name'] = serverName?.trim().isNotEmpty == true
          ? serverName!.trim()
          : previous['name']?.toString() ?? '';
      server['certificate_fingerprint'] = certificateFingerprint == null
          ? previous['certificate_fingerprint']?.toString() ?? ''
          : _normalizeFingerprint(certificateFingerprint);
      servers[index] = server;
    }
    final accounts = _mutableMap(data['accounts']);
    final key = _accountKey(normalized, username);
    await _secureStorage.write(
      key: _secureKey(normalized, username),
      value: password,
    );
    accounts[key] = {
      'server_url': normalized,
      'username': username,
      'access_token': accessToken,
      'permission_group': permissionGroup,
    };
    await _box.put(_storageKey, {
      'servers': servers,
      'accounts': accounts,
      'current_account': key,
    });
  }

  Future<void> setCurrentAccount(String serverUrl, String username) async {
    final data = _data();
    final key = _accountKey(serverUrl, username);
    if (_mutableMap(data['accounts']).containsKey(key)) {
      data['current_account'] = key;
      await _box.put(_storageKey, data);
    }
  }

  Future<void> renameServer(String serverUrl, String name) async {
    final normalized = _normalizeUrl(serverUrl);
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return;
    final data = _data();
    final servers = _mutableList(data['servers']);
    final index = servers.indexWhere(
      (value) => value is Map && value['url'] == normalized,
    );
    if (index < 0) return;
    final server = Map<String, dynamic>.from(servers[index] as Map);
    server['name'] = normalizedName;
    servers[index] = server;
    data['servers'] = servers;
    await _box.put(_storageKey, data);
  }

  Future<void> removeServer(String serverUrl) async {
    final normalized = _normalizeUrl(serverUrl);
    final data = _data();
    final servers = _mutableList(data['servers'])
      ..removeWhere((value) => value is Map && value['url'] == normalized);
    final accounts = _mutableMap(data['accounts']);
    accounts.removeWhere(
      (_, value) => value is Map && value['server_url'] == normalized,
    );
    data['servers'] = servers;
    data['accounts'] = accounts;
    _repairCurrentAccount(data, accounts);
    await _box.put(_storageKey, data);
  }

  Future<void> removeAccount(String serverUrl, String username) async {
    final data = _data();
    final accounts = _mutableMap(data['accounts']);
    accounts.remove(_accountKey(serverUrl, username));
    data['accounts'] = accounts;
    await _secureStorage.delete(key: _secureKey(serverUrl, username));
    final normalized = _normalizeUrl(serverUrl);
    final hasAccounts = accounts.values.any(
      (value) => value is Map && value['server_url'] == normalized,
    );
    if (!hasAccounts) {
      final servers = _mutableList(data['servers'])
        ..removeWhere((value) => value is Map && value['url'] == normalized);
      data['servers'] = servers;
    }
    _repairCurrentAccount(data, accounts);
    await _box.put(_storageKey, data);
  }

  void _repairCurrentAccount(
    Map<String, dynamic> data,
    Map<String, dynamic> accounts,
  ) {
    final current = data['current_account'];
    if (current is String && accounts.containsKey(current)) return;
    data['current_account'] = accounts.keys.firstOrNull;
  }

  Future<void> setAccessToken(String serverUrl, String accessToken) async {
    final current = getCurrentAccount();
    if (current == null || current.serverUrl != _normalizeUrl(serverUrl)) {
      return;
    }
    final password =
        await _secureStorage.read(
          key: _secureKey(current.serverUrl, current.username),
        ) ??
        '';
    await saveLogin(
      serverUrl: current.serverUrl,
      username: current.username,
      password: password,
      accessToken: accessToken,
      permissionGroup: current.permissionGroup ?? '',
      certificateFingerprint: getCertificateFingerprint(current.serverUrl),
      serverName: getServerName(current.serverUrl),
    );
  }

  Map<String, dynamic> _data() {
    final value = _box.get(_storageKey);
    return value is Map
        ? Map<String, dynamic>.from(value)
        : {'servers': [], 'accounts': {}, 'current_account': null};
  }

  List<_Server> _servers() => _mutableList(_data()['servers'])
      .whereType<Map>()
      .map(
        (value) => _Server(
          url: value['url']?.toString() ?? '',
          name: value['name']?.toString() ?? '',
          certificateFingerprint:
              value['certificate_fingerprint']?.toString() ?? '',
        ),
      )
      .toList();

  ServerAccount? _accountFromValue(dynamic value) {
    if (value is! Map) return null;
    final serverUrl = value['server_url']?.toString() ?? '';
    final username = value['username']?.toString() ?? '';
    if (serverUrl.isEmpty || username.isEmpty) return null;
    return ServerAccount(
      serverUrl: serverUrl,
      username: username,
      password: '',
      accessToken: value['access_token']?.toString() ?? '',
      permissionGroup: value['permission_group']?.toString(),
    );
  }

  List<dynamic> _mutableList(dynamic value) =>
      value is List ? List<dynamic>.from(value) : [];
  Map<String, dynamic> _mutableMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  List<String> _legacyServerUrls() {
    final values = _box.get(_serverUrlsKey);
    final result = values is List
        ? values
              .whereType<String>()
              .map(_normalizeUrl)
              .where((value) => value.isNotEmpty)
              .toList()
        : <String>[];
    final legacy = _box.get(_serverUrlKey);
    if (legacy is String && legacy.isNotEmpty) {
      result.add(_normalizeUrl(legacy));
    }
    return result.toSet().toList();
  }

  String? _legacyCurrentServerUrl(List<String> servers) {
    final value = _box.get(_currentServerUrlKey) ?? _box.get(_serverUrlKey);
    return value is String && value.isNotEmpty
        ? _normalizeUrl(value)
        : servers.firstOrNull;
  }

  Map<String, String> _stringMap(String key) {
    final value = _box.get(key);
    return value is Map
        ? value.map(
            (key, value) =>
                MapEntry(_normalizeUrl(key.toString()), value.toString()),
          )
        : {};
  }

  Map<String, Map<String, String>> _nestedStringMap(String key) {
    final value = _box.get(key);
    if (value is! Map) return {};
    return value.map(
      (key, value) => MapEntry(
        _normalizeUrl(key.toString()),
        value is Map
            ? value.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
            : {},
      ),
    );
  }

  String _accountKey(String serverUrl, String username) =>
      '${_normalizeUrl(serverUrl)}\n${username.trim()}';
  static String _secureKey(String serverUrl, String username) =>
      'password:${_normalizeUrl(serverUrl)}:${username.trim()}';
  static String _normalizeUrl(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');
  String _normalizeFingerprint(String value) =>
      value.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
}

class ServerCredential {
  const ServerCredential({required this.username, required this.password});
  final String username;
  final String password;
}

class ServerAccount extends ServerCredential {
  const ServerAccount({
    required this.serverUrl,
    required super.username,
    required super.password,
    required this.accessToken,
    required this.permissionGroup,
  });
  final String serverUrl;
  final String accessToken;
  final String? permissionGroup;
}

class _Server {
  const _Server({
    required this.url,
    required this.name,
    required this.certificateFingerprint,
  });
  final String url;
  final String name;
  final String certificateFingerprint;
}
