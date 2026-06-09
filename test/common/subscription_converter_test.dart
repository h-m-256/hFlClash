import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/common/subscription_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionConverter', () {
    final converter = SubscriptionConverter();

    test('converts vless share links to mihomo yaml', () {
      final converted = converter.convertText(
        'vless://00000000-0000-0000-0000-000000000000@example.com:443'
        '?encryption=none&security=tls&sni=sni.example&type=ws'
        '&host=cdn.example&path=%2Fws&fp=chrome#VLESS%20WS',
      );
      final yaml = converted?.content;

      expect(yaml, isNotNull);
      expect(yaml, contains('type: "vless"'));
      expect(yaml, contains('name: "VLESS WS"'));
      expect(yaml, contains('uuid: "00000000-0000-0000-0000-000000000000"'));
      expect(yaml, contains('servername: "sni.example"'));
      expect(yaml, contains('network: "ws"'));
      expect(yaml, contains('Host: "cdn.example"'));
      expect(yaml, contains('rules:'));
      expect(
        converted?.proxyLinks['VLESS WS'],
        startsWith('vless://00000000-0000-0000-0000-000000000000@'),
      );
    });

    test('normalizes whitespace after share link scheme', () {
      final yaml = converter.convertTextIfNeeded(
        'vless:// 00000000-0000-0000-0000-000000000000@example.com:443'
        '?encryption=none&type=tcp#Spaced',
      );

      expect(yaml, isNotNull);
      expect(yaml, contains('name: "Spaced"'));
      expect(yaml, contains('server: "example.com"'));
    });

    test('converts hysteria2 share links to mihomo yaml', () {
      final yaml = converter.convertTextIfNeeded(
        'hysteria2://secret@example.com:443?obfs=salamander'
        '&obfs-password=obfs-secret&sni=sni.example&insecure=1#HY2',
      );

      expect(yaml, isNotNull);
      expect(yaml, contains('type: "hysteria2"'));
      expect(yaml, contains('name: "HY2"'));
      expect(yaml, contains('password: "secret"'));
      expect(yaml, contains('obfs: "salamander"'));
      expect(yaml, contains('obfs-password: "obfs-secret"'));
      expect(yaml, contains('skip-cert-verify: true'));
    });

    test('decodes whole base64 subscriptions before converting', () {
      const link =
          'trojan://password@example.com:443?sni=sni.example#TrojanNode';
      final encoded = base64.encode(utf8.encode(link));

      final converted = converter.convertText(encoded);
      final yaml = converted?.content;

      expect(converted?.sourceType, SubscriptionSourceType.base64Links);
      expect(yaml, isNotNull);
      expect(yaml, contains('type: "trojan"'));
      expect(yaml, contains('name: "TrojanNode"'));
      expect(yaml, contains('password: "password"'));
    });

    test('keeps existing clash yaml unchanged', () {
      const clashYaml = 'proxies:\n  - name: Existing\n    type: direct\n';

      expect(converter.canConvert(clashYaml), isFalse);
      expect(converter.convertTextIfNeeded(clashYaml), isNull);
      final bytes = Uint8List.fromList(utf8.encode(clashYaml));

      expect(converter.convertBytesIfNeeded(bytes), bytes);
      expect(converter.convertBytes(bytes).sourceType, isNull);
    });

    test('deduplicates proxy names', () {
      final yaml = converter.convertTextIfNeeded(
        'hysteria2://secret@example.com:443#Node\n'
        'hysteria2://secret@example.org:443#Node',
      );

      expect(yaml, contains('name: "Node"'));
      expect(yaml, contains('name: "Node 2"'));
    });

    test('detects direct share links as convertible profile sources', () {
      expect(
        converter.canConvert('hysteria2://secret@example.com:443#Node'),
        isTrue,
      );
      expect(converter.canConvert('https://example.com/sub'), isFalse);
    });

    test('skips malformed links when valid links exist', () {
      final yaml = converter.convertTextIfNeeded(
        'vmess://not-valid-base64\n'
        'ss://d_91Ohw=#Broken\n'
        'vless://not-a-uuid@example.com:443#BrokenVless\n'
        'hysteria2://secret@example.com:443#Valid',
      );

      expect(yaml, contains('name: "Valid"'));
      expect(yaml, isNot(contains('not-valid-base64')));
      expect(yaml, isNot(contains('Broken')));
      expect(yaml, isNot(contains('BrokenVless')));
    });

    test('limits very large share link subscriptions', () {
      final links = List.generate(maxConvertedSubscriptionProxies + 10, (
        index,
      ) {
        final suffix = index.toString().padLeft(12, '0');
        return 'vless://00000000-0000-0000-0000-$suffix@example$index.com:443'
            '?encryption=none&type=tcp#Node$index';
      }).join('\n');

      final converted = converter.convertText(links);

      expect(converted?.proxyLinks.length, maxConvertedSubscriptionProxies);
      expect(converted?.content, contains('name: "Node0"'));
      expect(
        converted?.content,
        isNot(contains('name: "Node$maxConvertedSubscriptionProxies"')),
      );
    });

    test('re-injects protected favorite links and orders favorites first', () {
      const currentLink =
          'vless://00000000-0000-0000-0000-000000000001@current.example:443'
          '?encryption=none&type=tcp#Current';
      const protectedLink =
          'vless://00000000-0000-0000-0000-000000000002@old.example:443'
          '?encryption=none&type=tcp#Old';

      final converted = converter.convertText(
        currentLink,
        favoriteProxyNames: {'Current'},
        protectedProxyLinks: {'Old': protectedLink},
      );
      final yaml = converted?.content;

      expect(converted?.proxyLinks['Old'], protectedLink);
      expect(yaml, contains('server: "old.example"'));
      expect(
        yaml!.indexOf('name: "Old"'),
        lessThan(yaml.indexOf('name: "Current"')),
      );
    });

    test('normalizes html escaped query separators', () {
      final yaml = converter.convertTextIfNeeded(
        'vless://00000000-0000-0000-0000-000000000000@example.com:443'
        '?encryption=none&amp;security=reality&amp;type=tcp&amp;sni=sni.example'
        '&amp;fp=chrome&amp;pbk=public-key&amp;sid=short-id#Escaped',
      );

      expect(yaml, contains('reality-opts:'));
      expect(yaml, contains('public-key: "public-key"'));
      expect(yaml, contains('short-id: "short-id"'));
      expect(yaml, contains('client-fingerprint: "chrome"'));
    });

    test('converts vless grpc reality links', () {
      final yaml = converter.convertTextIfNeeded(
        'vless://00000000-0000-0000-0000-000000000000@example.com:443'
        '?encryption=none&type=grpc&serviceName=gun&security=reality'
        '&sni=example.org&fp=chrome&pbk=public-key&sid=short-id#GRPC',
      );

      expect(yaml, contains('network: "grpc"'));
      expect(yaml, contains('grpc-opts:'));
      expect(yaml, contains('grpc-service-name: "gun"'));
      expect(yaml, contains('reality-opts:'));
      expect(yaml, contains('public-key: "public-key"'));
      expect(yaml, contains('short-id: "short-id"'));
      expect(yaml, contains('client-fingerprint: "chrome"'));
    });

    test('converts vless xhttp transport options', () {
      final extra = Uri.encodeComponent(
        jsonEncode({
          'noGRPCHeader': true,
          'xPaddingBytes': '100-1000',
          'sessionPlacement': 'path',
          'xmux': {'maxConcurrency': '16-32'},
          'downloadSettings': {
            'address': 'download.example.com',
            'port': 443,
            'security': 'tls',
            'tlsSettings': {
              'serverName': 'download-sni.example',
              'fingerprint': 'chrome',
            },
            'xhttpSettings': {
              'path': '/download',
              'host': 'download-host.example',
            },
          },
        }),
      );
      final headers = Uri.encodeComponent(jsonEncode({'X-Test': '1'}));
      final yaml = converter.convertTextIfNeeded(
        'vless://00000000-0000-0000-0000-000000000000@example.com:443'
        '?encryption=none&type=xhttp&security=tls&sni=sni.example'
        '&path=%2Fxhttp&host=host.example&mode=stream-up'
        '&headers=$headers&extra=$extra#XHTTP',
      );

      expect(yaml, contains('network: "xhttp"'));
      expect(yaml, contains('xhttp-opts:'));
      expect(yaml, contains('path: "/xhttp"'));
      expect(yaml, contains('host: "host.example"'));
      expect(yaml, contains('mode: "stream-up"'));
      expect(yaml, contains('X-Test: "1"'));
      expect(yaml, contains('no-grpc-header: true'));
      expect(yaml, contains('x-padding-bytes: "100-1000"'));
      expect(yaml, contains('session-placement: "path"'));
      expect(yaml, contains('reuse-settings:'));
      expect(yaml, contains('max-concurrency: "16-32"'));
      expect(yaml, contains('download-settings:'));
      expect(yaml, contains('server: "download.example.com"'));
      expect(yaml, contains('servername: "download-sni.example"'));
      expect(yaml, contains('path: "/download"'));
    });

    test('converts HAPP JSON vless outbounds', () {
      final happJson = jsonEncode([
        {
          'remarks': 'HAPP Profile',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'example.com',
                    'port': 443,
                    'users': [
                      {
                        'id': '00000000-0000-0000-0000-000000000000',
                        'encryption': 'none',
                        'flow': 'xtls-rprx-vision',
                      },
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'grpc',
                'security': 'reality',
                'realitySettings': {
                  'serverName': 'sni.example',
                  'fingerprint': 'chrome',
                  'publicKey': 'public-key',
                  'shortId': 'short-id',
                },
                'grpcSettings': {'serviceName': 'gun'},
              },
            },
            {'tag': 'direct', 'protocol': 'freedom'},
          ],
        },
      ]);

      final converted = converter.convertText(happJson);
      final yaml = converted?.content;

      expect(converted?.sourceType, SubscriptionSourceType.happJson);
      expect(yaml, contains('name: "HAPP Profile"'));
      expect(yaml, contains('type: "vless"'));
      expect(yaml, contains('flow: "xtls-rprx-vision"'));
      expect(yaml, contains('network: "grpc"'));
      expect(yaml, contains('grpc-service-name: "gun"'));
      expect(yaml, contains('reality-opts:'));
      expect(yaml, contains('public-key: "public-key"'));
    });
  });
}
