import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/common/subscription_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionConverter', () {
    final converter = SubscriptionConverter();

    test('converts vless share links to mihomo yaml', () {
      final yaml = converter.convertTextIfNeeded(
        'vless://00000000-0000-0000-0000-000000000000@example.com:443'
        '?encryption=none&security=tls&sni=sni.example&type=ws'
        '&host=cdn.example&path=%2Fws&fp=chrome#VLESS%20WS',
      );

      expect(yaml, isNotNull);
      expect(yaml, contains('type: "vless"'));
      expect(yaml, contains('name: "VLESS WS"'));
      expect(yaml, contains('uuid: "00000000-0000-0000-0000-000000000000"'));
      expect(yaml, contains('servername: "sni.example"'));
      expect(yaml, contains('network: "ws"'));
      expect(yaml, contains('Host: "cdn.example"'));
      expect(yaml, contains('rules:'));
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

      final yaml = converter.convertTextIfNeeded(encoded);

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
        'hysteria2://secret@example.com:443#Valid',
      );

      expect(yaml, contains('name: "Valid"'));
      expect(yaml, isNot(contains('not-valid-base64')));
    });
  });
}
