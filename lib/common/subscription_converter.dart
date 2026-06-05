import 'dart:convert';
import 'dart:typed_data';

import 'yaml.dart';

class SubscriptionConverter {
  static final _linkRegExp = RegExp(
    r'(?:(?:vless|vmess|trojan|ss|hysteria2|hy2|hysteria|tuic)://)[^\s]+',
    caseSensitive: false,
  );
  static final _clashYamlRegExp = RegExp(
    r'^\s*(proxies|proxy-groups|proxy-providers|rules):\s*',
    multiLine: true,
  );

  Uint8List convertBytesIfNeeded(Uint8List bytes) {
    final content = utf8.decode(bytes, allowMalformed: true);
    final converted = convertTextIfNeeded(content);
    if (converted == null) return bytes;
    return Uint8List.fromList(utf8.encode(converted));
  }

  String? convertTextIfNeeded(String content) {
    final normalized = _normalizeText(content);
    final source = _getLinkSource(normalized);
    if (source == null) return null;

    final links = _extractLinks(source);
    if (links.isEmpty) return null;

    final proxies = <Map<String, dynamic>>[];
    for (final link in links) {
      final proxy = _parseLink(link);
      if (proxy != null) {
        proxies.add(proxy);
      }
    }
    if (proxies.isEmpty) {
      throw 'Unsupported subscription links';
    }

    _ensureUniqueNames(proxies);
    final proxyNames = proxies.map((proxy) => proxy['name'] as String).toList();
    final config = <String, dynamic>{
      'mixed-port': 7890,
      'allow-lan': false,
      'mode': 'rule',
      'log-level': 'info',
      'proxies': proxies,
      'proxy-groups': [
        {
          'name': 'PROXY',
          'type': 'select',
          'proxies': ['Auto', ...proxyNames, 'DIRECT'],
        },
        {
          'name': 'Auto',
          'type': 'url-test',
          'proxies': proxyNames,
          'url': 'http://www.gstatic.com/generate_204',
          'interval': 300,
        },
      ],
      'rules': ['MATCH,PROXY'],
    };
    return '${yaml.encode(config)}\n';
  }

  bool canConvert(String content) {
    return _getLinkSource(_normalizeText(content)) != null;
  }

  String? _getLinkSource(String normalized) {
    if (normalized.isEmpty || _clashYamlRegExp.hasMatch(normalized)) {
      return null;
    }
    return _extractLinks(normalized).isNotEmpty
        ? normalized
        : _decodeWholeBase64(normalized);
  }

  List<String> _extractLinks(String content) {
    return _linkRegExp
        .allMatches(content)
        .map((match) => match.group(0)!.trim().trimRightChar(','))
        .toList();
  }

  Map<String, dynamic>? _parseLink(String link) {
    final scheme = link.split('://').first.toLowerCase();
    try {
      return switch (scheme) {
        'vless' => _parseVless(link),
        'vmess' => _parseVmess(link),
        'trojan' => _parseTrojan(link),
        'ss' => _parseShadowsocks(link),
        'hysteria2' || 'hy2' => _parseHysteria2(link),
        'hysteria' => _parseHysteria(link),
        'tuic' => _parseTuic(link),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseVless(String link) {
    final uri = Uri.tryParse(link);
    if (!_hasServer(uri)) return null;
    final params = uri!.queryParameters;
    final port = _port(uri);
    final uuid = _decode(uri.userInfo);
    if (port == null || uuid.isEmpty) return null;

    final proxy = <String, dynamic>{
      'name': _name(uri, 'vless-${uri.host}:$port'),
      'type': 'vless',
      'server': uri.host,
      'port': port,
      'uuid': uuid,
      'udp': true,
    };
    _put(proxy, 'flow', params['flow']);
    _put(proxy, 'encryption', params['encryption']);

    final security = params['security']?.toLowerCase();
    if (security == 'tls' || security == 'reality' || _truthy(params['tls'])) {
      proxy['tls'] = true;
    }
    _put(
      proxy,
      'servername',
      _first(params, ['sni', 'servername', 'serverName']),
    );
    _put(proxy, 'client-fingerprint', params['fp']);
    _putList(proxy, 'alpn', params['alpn']);
    _putTruthy(
      proxy,
      'skip-cert-verify',
      _first(params, ['allowInsecure', 'insecure']),
    );

    if (security == 'reality') {
      final realityOpts = <String, dynamic>{};
      _put(realityOpts, 'public-key', _first(params, ['pbk', 'public-key']));
      _put(realityOpts, 'short-id', _first(params, ['sid', 'short-id']));
      _put(realityOpts, 'spider-x', _first(params, ['spx', 'spiderX']));
      if (realityOpts.isNotEmpty) proxy['reality-opts'] = realityOpts;
    }

    _applyTransport(proxy, params);
    return proxy;
  }

  Map<String, dynamic>? _parseVmess(String link) {
    final raw = link.substring('vmess://'.length).trim();
    final decoded = _decodeBase64(raw);
    if (decoded == null) return null;
    final data = json.decode(decoded) as Map<String, dynamic>;
    final server = data['add']?.toString();
    final port = int.tryParse(data['port']?.toString() ?? '');
    final uuid = data['id']?.toString();
    if (server == null || server.isEmpty || port == null || uuid == null) {
      return null;
    }

    final proxy = <String, dynamic>{
      'name': data['ps']?.toString().takeIfNotEmpty ?? 'vmess-$server:$port',
      'type': 'vmess',
      'server': server,
      'port': port,
      'uuid': uuid,
      'alterId': int.tryParse(data['aid']?.toString() ?? '') ?? 0,
      'cipher': data['scy']?.toString().takeIfNotEmpty ?? 'auto',
      'udp': true,
    };
    final tls = data['tls']?.toString().toLowerCase();
    if (tls == 'tls') proxy['tls'] = true;
    _put(proxy, 'servername', data['sni']?.toString());
    _put(proxy, 'client-fingerprint', data['fp']?.toString());
    _putList(proxy, 'alpn', data['alpn']?.toString());

    final network = data['net']?.toString();
    if (network != null && network.isNotEmpty && network != 'tcp') {
      proxy['network'] = network;
      if (network == 'ws') {
        _applyWs(proxy, data['path']?.toString(), data['host']?.toString());
      } else if (network == 'grpc') {
        _applyGrpc(proxy, data['path']?.toString());
      } else if (network == 'xhttp') {
        _applyXhttp(
          proxy,
          data.map((key, value) => MapEntry(key, value?.toString() ?? '')),
        );
      }
    }
    return proxy;
  }

  Map<String, dynamic>? _parseTrojan(String link) {
    final uri = Uri.tryParse(link);
    if (!_hasServer(uri)) return null;
    final params = uri!.queryParameters;
    final port = _port(uri);
    final password = _decode(uri.userInfo);
    if (port == null || password.isEmpty) return null;

    final proxy = <String, dynamic>{
      'name': _name(uri, 'trojan-${uri.host}:$port'),
      'type': 'trojan',
      'server': uri.host,
      'port': port,
      'password': password,
      'udp': true,
    };
    _put(proxy, 'sni', _first(params, ['sni', 'peer', 'servername']));
    _putList(proxy, 'alpn', params['alpn']);
    _putTruthy(
      proxy,
      'skip-cert-verify',
      _first(params, ['allowInsecure', 'insecure']),
    );
    _applyTransport(proxy, params);
    return proxy;
  }

  Map<String, dynamic>? _parseShadowsocks(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    final params = uri.queryParameters;
    var server = uri.host;
    var port = _port(uri);
    var credentials = _decode(uri.userInfo);

    if (credentials.isEmpty || !credentials.contains(':')) {
      credentials = _decodeBase64(credentials) ?? credentials;
    }

    if (server.isEmpty || port == null || !credentials.contains(':')) {
      final withoutScheme = link.substring('ss://'.length);
      final beforeMeta = withoutScheme.split(RegExp(r'[?#]')).first;
      final decoded = _decodeBase64(beforeMeta);
      final parsed = decoded == null ? null : _parseCredentialServer(decoded);
      if (parsed == null) return null;
      credentials = parsed.credentials;
      server = parsed.server;
      port = parsed.port;
    }

    final splitIndex = credentials.indexOf(':');
    final cipher = credentials.substring(0, splitIndex);
    final password = credentials.substring(splitIndex + 1);
    if (cipher.isEmpty || password.isEmpty || server.isEmpty) {
      return null;
    }

    final proxy = <String, dynamic>{
      'name': _name(uri, 'ss-$server:$port'),
      'type': 'ss',
      'server': server,
      'port': port,
      'cipher': cipher,
      'password': password,
      'udp': true,
    };
    _applyShadowsocksPlugin(proxy, params['plugin']);
    return proxy;
  }

  Map<String, dynamic>? _parseHysteria2(String link) {
    final uri = Uri.tryParse(link);
    if (!_hasServer(uri)) return null;
    final params = uri!.queryParameters;
    final port = _port(uri);
    final password = _decode(uri.userInfo).takeIfNotEmpty ?? params['auth'];
    if (port == null || password == null || password.isEmpty) return null;

    final proxy = <String, dynamic>{
      'name': _name(uri, 'hysteria2-${uri.host}:$port'),
      'type': 'hysteria2',
      'server': uri.host,
      'port': port,
      'password': password,
      'udp': true,
    };
    _put(proxy, 'sni', _first(params, ['sni', 'peer']));
    _put(proxy, 'obfs', params['obfs']);
    _put(
      proxy,
      'obfs-password',
      _first(params, ['obfs-password', 'obfs_password']),
    );
    _put(proxy, 'up', _first(params, ['up', 'upmbps']));
    _put(proxy, 'down', _first(params, ['down', 'downmbps']));
    _putList(proxy, 'alpn', params['alpn']);
    _putTruthy(
      proxy,
      'skip-cert-verify',
      _first(params, ['allowInsecure', 'insecure']),
    );
    return proxy;
  }

  Map<String, dynamic>? _parseHysteria(String link) {
    final uri = Uri.tryParse(link);
    if (!_hasServer(uri)) return null;
    final params = uri!.queryParameters;
    final port = _port(uri);
    if (port == null) return null;

    final auth =
        _first(params, ['auth', 'auth-str', 'auth_str']) ??
        _decode(uri.userInfo).takeIfNotEmpty;
    final proxy = <String, dynamic>{
      'name': _name(uri, 'hysteria-${uri.host}:$port'),
      'type': 'hysteria',
      'server': uri.host,
      'port': port,
      'udp': true,
    };
    _put(proxy, 'auth-str', auth);
    _put(proxy, 'protocol', params['protocol']);
    _put(proxy, 'obfs', params['obfs']);
    _put(proxy, 'sni', _first(params, ['sni', 'peer']));
    _put(proxy, 'up', _first(params, ['up', 'upmbps']));
    _put(proxy, 'down', _first(params, ['down', 'downmbps']));
    _putList(proxy, 'alpn', params['alpn']);
    _putTruthy(
      proxy,
      'skip-cert-verify',
      _first(params, ['allowInsecure', 'insecure']),
    );
    return proxy;
  }

  Map<String, dynamic>? _parseTuic(String link) {
    final uri = Uri.tryParse(link);
    if (!_hasServer(uri)) return null;
    final params = uri!.queryParameters;
    final port = _port(uri);
    final userInfo = _decode(uri.userInfo);
    final separator = userInfo.indexOf(':');
    if (port == null || separator == -1) return null;

    final proxy = <String, dynamic>{
      'name': _name(uri, 'tuic-${uri.host}:$port'),
      'type': 'tuic',
      'server': uri.host,
      'port': port,
      'uuid': userInfo.substring(0, separator),
      'password': userInfo.substring(separator + 1),
      'udp': true,
    };
    _put(proxy, 'sni', _first(params, ['sni', 'servername']));
    _put(
      proxy,
      'congestion-controller',
      _first(params, [
        'congestion_control',
        'congestion-controller',
        'congestion',
      ]),
    );
    _put(
      proxy,
      'udp-relay-mode',
      _first(params, ['udp_relay_mode', 'udp-relay-mode']),
    );
    _putList(proxy, 'alpn', params['alpn']);
    _putTruthy(
      proxy,
      'disable-sni',
      _first(params, ['disable_sni', 'disable-sni']),
    );
    _putTruthy(
      proxy,
      'reduce-rtt',
      _first(params, ['reduce_rtt', 'reduce-rtt']),
    );
    return proxy;
  }

  void _applyTransport(Map<String, dynamic> proxy, Map<String, String> params) {
    final network = _first(params, ['type', 'network']);
    if (network == null || network.isEmpty || network == 'tcp') return;
    proxy['network'] = network;
    if (network == 'ws') {
      _applyWs(proxy, params['path'], _first(params, ['host', 'Host']));
    } else if (network == 'grpc') {
      _applyGrpc(
        proxy,
        _first(params, ['serviceName', 'service-name', 'grpc-service-name']),
      );
    } else if (network == 'xhttp') {
      _applyXhttp(proxy, params);
    } else if (network == 'h2') {
      final h2Opts = <String, dynamic>{};
      _put(h2Opts, 'path', params['path']);
      _putList(h2Opts, 'host', _first(params, ['host', 'Host']));
      if (h2Opts.isNotEmpty) proxy['h2-opts'] = h2Opts;
    }
  }

  void _applyWs(Map<String, dynamic> proxy, String? path, String? host) {
    final wsOpts = <String, dynamic>{};
    _put(wsOpts, 'path', path);
    if (host != null && host.isNotEmpty) {
      wsOpts['headers'] = {'Host': host};
    }
    if (wsOpts.isNotEmpty) proxy['ws-opts'] = wsOpts;
  }

  void _applyGrpc(Map<String, dynamic> proxy, String? serviceName) {
    if (serviceName == null || serviceName.isEmpty) return;
    proxy['grpc-opts'] = {'grpc-service-name': serviceName};
  }

  void _applyXhttp(Map<String, dynamic> proxy, Map<String, String> params) {
    final opts = <String, dynamic>{};
    _put(opts, 'path', params['path']);
    _put(opts, 'host', _first(params, ['host', 'Host']));
    _put(opts, 'mode', params['mode']);

    final headers = _parseHeaders(params['headers']);
    if (headers != null) {
      opts['headers'] = headers;
    }

    _putTruthy(
      opts,
      'no-grpc-header',
      _first(params, ['noGRPCHeader', 'no-grpc-header', 'noGrpcHeader']),
    );
    _put(
      opts,
      'x-padding-bytes',
      _first(params, ['xPaddingBytes', 'x-padding-bytes']),
    );
    _putBoolIfPresent(
      opts,
      'x-padding-obfs-mode',
      _first(params, ['xPaddingObfsMode', 'x-padding-obfs-mode']),
    );
    _put(
      opts,
      'x-padding-key',
      _first(params, ['xPaddingKey', 'x-padding-key']),
    );
    _put(
      opts,
      'x-padding-header',
      _first(params, ['xPaddingHeader', 'x-padding-header']),
    );
    _put(
      opts,
      'x-padding-placement',
      _first(params, ['xPaddingPlacement', 'x-padding-placement']),
    );
    _put(
      opts,
      'x-padding-method',
      _first(params, ['xPaddingMethod', 'x-padding-method']),
    );
    _put(
      opts,
      'uplink-http-method',
      _first(params, ['uplinkHttpMethod', 'uplink-http-method']),
    );
    _put(
      opts,
      'session-placement',
      _first(params, ['sessionPlacement', 'session-placement']),
    );
    _put(opts, 'session-key', _first(params, ['sessionKey', 'session-key']));
    _put(
      opts,
      'seq-placement',
      _first(params, ['seqPlacement', 'seq-placement']),
    );
    _put(opts, 'seq-key', _first(params, ['seqKey', 'seq-key']));
    _put(
      opts,
      'uplink-data-placement',
      _first(params, ['uplinkDataPlacement', 'uplink-data-placement']),
    );
    _put(
      opts,
      'uplink-data-key',
      _first(params, ['uplinkDataKey', 'uplink-data-key']),
    );
    _putInt(
      opts,
      'uplink-chunk-size',
      _first(params, ['uplinkChunkSize', 'uplink-chunk-size']),
    );
    _putInt(
      opts,
      'sc-max-each-post-bytes',
      _first(params, ['scMaxEachPostBytes', 'sc-max-each-post-bytes']),
    );
    _putInt(
      opts,
      'sc-min-posts-interval-ms',
      _first(params, ['scMinPostsIntervalMs', 'sc-min-posts-interval-ms']),
    );

    final extra = _parseJsonMap(params['extra']);
    if (extra != null) {
      _applyXhttpExtra(extra, opts);
    }

    proxy['xhttp-opts'] = opts;
  }

  void _applyXhttpExtra(Map<String, dynamic> extra, Map<String, dynamic> opts) {
    if (extra['noGRPCHeader'] == true) {
      opts['no-grpc-header'] = true;
    }
    _putDynamic(opts, 'x-padding-bytes', extra['xPaddingBytes']);
    _putDynamic(opts, 'x-padding-obfs-mode', extra['xPaddingObfsMode']);
    _putDynamic(opts, 'x-padding-key', extra['xPaddingKey']);
    _putDynamic(opts, 'x-padding-header', extra['xPaddingHeader']);
    _putDynamic(opts, 'x-padding-placement', extra['xPaddingPlacement']);
    _putDynamic(opts, 'x-padding-method', extra['xPaddingMethod']);
    _putDynamic(opts, 'uplink-http-method', extra['uplinkHttpMethod']);
    _putDynamic(opts, 'session-placement', extra['sessionPlacement']);
    _putDynamic(opts, 'session-key', extra['sessionKey']);
    _putDynamic(opts, 'seq-placement', extra['seqPlacement']);
    _putDynamic(opts, 'seq-key', extra['seqKey']);
    _putDynamic(opts, 'uplink-data-placement', extra['uplinkDataPlacement']);
    _putDynamic(opts, 'uplink-data-key', extra['uplinkDataKey']);
    _putDynamic(opts, 'uplink-chunk-size', extra['uplinkChunkSize']);
    _putDynamic(opts, 'sc-max-each-post-bytes', extra['scMaxEachPostBytes']);
    _putDynamic(
      opts,
      'sc-min-posts-interval-ms',
      extra['scMinPostsIntervalMs'],
    );

    final xmux = _asMap(extra['xmux']);
    if (xmux != null) {
      final reuseSettings = _xhttpReuseSettings(xmux);
      if (reuseSettings.isNotEmpty) {
        opts['reuse-settings'] = reuseSettings;
      }
    }

    final downloadSettings = _xhttpDownloadSettings(
      _asMap(extra['downloadSettings']),
    );
    if (downloadSettings != null) {
      opts['download-settings'] = downloadSettings;
    }
  }

  Map<String, dynamic>? _xhttpDownloadSettings(Map<String, dynamic>? data) {
    if (data == null) return null;
    final result = <String, dynamic>{};
    _putDynamic(result, 'server', data['address']);
    _putDynamic(result, 'port', data['port']);

    final security = data['security']?.toString().toLowerCase();
    if (security == 'tls' || security == 'reality') {
      result['tls'] = true;
      final tls = _asMap(data['tlsSettings']);
      if (tls != null) {
        _putDynamic(result, 'servername', tls['serverName']);
        _putDynamic(result, 'client-fingerprint', tls['fingerprint']);
        final alpn = _stringList(tls['alpn']);
        if (alpn.isNotEmpty) result['alpn'] = alpn;
        if (tls['allowInsecure'] == true) {
          result['skip-cert-verify'] = true;
        }
      }
      if (security == 'reality') {
        final reality = _asMap(data['realitySettings']);
        if (reality != null) {
          final realityOpts = <String, dynamic>{};
          _putDynamic(realityOpts, 'public-key', reality['publicKey']);
          _putDynamic(realityOpts, 'short-id', reality['shortId']);
          if (realityOpts.isNotEmpty) {
            result['reality-opts'] = realityOpts;
          }
        }
      }
    }

    final xhttp = _asMap(data['xhttpSettings']);
    if (xhttp != null) {
      _putDynamic(result, 'path', xhttp['path']);
      _putDynamic(result, 'host', xhttp['host']);
      final headers = _asStringMap(xhttp['headers']);
      if (headers != null) result['headers'] = headers;

      final extra = _asMap(xhttp['extra']);
      final xmux = extra == null ? null : _asMap(extra['xmux']);
      if (xmux != null) {
        final reuseSettings = _xhttpReuseSettings(xmux);
        if (reuseSettings.isNotEmpty) {
          result['reuse-settings'] = reuseSettings;
        }
      }
    }

    return result.isEmpty ? null : result;
  }

  Map<String, dynamic> _xhttpReuseSettings(Map<String, dynamic> xmux) {
    final result = <String, dynamic>{};
    _putDynamic(result, 'max-connections', xmux['maxConnections']);
    _putDynamic(result, 'max-concurrency', xmux['maxConcurrency']);
    _putDynamic(result, 'c-max-reuse-times', xmux['cMaxReuseTimes']);
    _putDynamic(result, 'h-max-request-times', xmux['hMaxRequestTimes']);
    _putDynamic(result, 'h-max-reusable-secs', xmux['hMaxReusableSecs']);
    _putDynamic(result, 'h-keep-alive-period', xmux['hKeepAlivePeriod']);
    return result;
  }

  void _applyShadowsocksPlugin(Map<String, dynamic> proxy, String? plugin) {
    if (plugin == null || plugin.isEmpty) return;
    final parts = plugin.split(';');
    final name = parts.first;
    final options = <String, String>{};
    for (final part in parts.skip(1)) {
      final index = part.indexOf('=');
      if (index == -1) continue;
      options[part.substring(0, index)] = part.substring(index + 1);
    }
    if (name == 'obfs-local' || name == 'simple-obfs') {
      proxy['plugin'] = 'obfs';
      proxy['plugin-opts'] = {
        if (options['obfs'] != null) 'mode': options['obfs'],
        if (options['obfs-host'] != null) 'host': options['obfs-host'],
      };
    } else if (name == 'v2ray-plugin') {
      proxy['plugin'] = name;
      proxy['plugin-opts'] = {
        if (options['mode'] != null) 'mode': options['mode'],
        if (options['host'] != null) 'host': options['host'],
        if (options['path'] != null) 'path': options['path'],
        if (_truthy(options['tls'])) 'tls': true,
        if (_truthy(options['mux'])) 'mux': true,
      };
    }
  }

  void _ensureUniqueNames(List<Map<String, dynamic>> proxies) {
    final used = <String, int>{};
    for (final proxy in proxies) {
      final raw = (proxy['name'] as String?)?.trim();
      final name = raw == null || raw.isEmpty ? 'Proxy' : raw;
      final count = used[name] ?? 0;
      used[name] = count + 1;
      proxy['name'] = count == 0 ? name : '$name ${count + 1}';
    }
  }

  String _normalizeText(String content) {
    return content.replaceFirst('\uFEFF', '').trim();
  }

  String? _decodeWholeBase64(String content) {
    final normalized = content.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length < 16 ||
        !RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(normalized)) {
      return null;
    }
    final decoded = _decodeBase64(normalized);
    if (decoded == null || _extractLinks(decoded).isEmpty) return null;
    return decoded;
  }

  String? _decodeBase64(String value) {
    if (value.isEmpty) return null;
    try {
      var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
      final remainder = normalized.length % 4;
      if (remainder != 0) {
        normalized = normalized.padRight(
          normalized.length + 4 - remainder,
          '=',
        );
      }
      return utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  _ParsedShadowsocks? _parseCredentialServer(String value) {
    final atIndex = value.lastIndexOf('@');
    final colonIndex = value.lastIndexOf(':');
    if (atIndex == -1 || colonIndex <= atIndex) return null;
    final port = int.tryParse(value.substring(colonIndex + 1));
    if (port == null) return null;
    return _ParsedShadowsocks(
      credentials: value.substring(0, atIndex),
      server: value.substring(atIndex + 1, colonIndex),
      port: port,
    );
  }

  bool _hasServer(Uri? uri) {
    return uri != null && uri.host.isNotEmpty;
  }

  int? _port(Uri uri) {
    return uri.hasPort ? uri.port : null;
  }

  String _name(Uri uri, String fallback) {
    return _decode(uri.fragment).takeIfNotEmpty ?? fallback;
  }

  String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  String? _first(Map<String, String> params, List<String> keys) {
    for (final key in keys) {
      final value = params[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  void _put(Map<String, dynamic> target, String key, String? value) {
    if (value != null && value.isNotEmpty) target[key] = value;
  }

  void _putDynamic(Map<String, dynamic> target, String key, Object? value) {
    if (value == null) return;
    if (value is String && value.isEmpty) return;
    target[key] = value;
  }

  void _putInt(Map<String, dynamic> target, String key, String? value) {
    if (value == null || value.isEmpty) return;
    final intValue = int.tryParse(value);
    if (intValue != null) {
      target[key] = intValue;
    }
  }

  void _putBoolIfPresent(
    Map<String, dynamic> target,
    String key,
    String? value,
  ) {
    final boolValue = _boolValue(value);
    if (boolValue != null) {
      target[key] = boolValue;
    }
  }

  void _putList(Map<String, dynamic> target, String key, String? value) {
    if (value == null || value.isEmpty) return;
    target[key] = value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _putTruthy(Map<String, dynamic> target, String key, String? value) {
    if (_truthy(value)) target[key] = true;
  }

  Map<String, dynamic>? _parseJsonMap(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return _asMap(json.decode(value));
    } catch (_) {
      return null;
    }
  }

  Map<String, String>? _parseHeaders(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final headers = _asStringMap(json.decode(value));
      if (headers != null) return headers;
    } catch (_) {}

    final headers = <String, String>{};
    for (final item in value.split(RegExp(r'[,;|]'))) {
      final separator = item.contains(':') ? ':' : '=';
      final index = item.indexOf(separator);
      if (index == -1) continue;
      final key = item.substring(0, index).trim();
      final headerValue = item.substring(index + 1).trim();
      if (key.isNotEmpty && headerValue.isNotEmpty) {
        headers[key] = headerValue;
      }
    }
    return headers.isEmpty ? null : headers;
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, String>? _asStringMap(Object? value) {
    final map = _asMap(value);
    if (map == null || map.isEmpty) return null;
    return map.map((key, value) => MapEntry(key, value.toString()));
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return [];
  }

  bool _truthy(String? value) {
    return _boolValue(value) == true;
  }

  bool? _boolValue(String? value) {
    if (value == null) return null;
    return switch (value.toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => true,
      '0' || 'false' || 'no' || 'off' => false,
      _ => null,
    };
  }
}

class _ParsedShadowsocks {
  final String credentials;
  final String server;
  final int port;

  const _ParsedShadowsocks({
    required this.credentials,
    required this.server,
    required this.port,
  });
}

extension on String {
  String trimRightChar(String char) {
    var value = this;
    while (value.endsWith(char)) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  String? get takeIfNotEmpty {
    final value = trim();
    return value.isEmpty ? null : value;
  }
}

final subscriptionConverter = SubscriptionConverter();
