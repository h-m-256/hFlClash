import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile', () {
    test('keeps subscription User-Agent in json round trip', () {
      final profile =
          Profile.normal(
            label: 'custom',
            url: 'https://example.com/sub',
            userAgent: defaultCustomSubscriptionUserAgent,
            requestHeaders: {'X-HWID': '123456'},
          ).copyWith(
            sourceType: SubscriptionSourceType.base64Links,
            proxyLinks: {'Proxy': 'vless://example'},
            favoriteProxyNames: {'Proxy'},
            protectedProxyLinks: {'Pinned': 'vless://pinned'},
          );

      final json = profile.toJson();
      final restored = Profile.fromJson(json);

      expect(json['userAgent'], defaultCustomSubscriptionUserAgent);
      expect(restored.userAgent, defaultCustomSubscriptionUserAgent);
      expect(restored.requestHeaders, {'X-HWID': '123456'});
      expect(restored.sourceType, SubscriptionSourceType.base64Links);
      expect(restored.proxyLinks, {'Proxy': 'vless://example'});
      expect(restored.favoriteProxyNames, {'Proxy'});
      expect(restored.protectedProxyLinks, {'Pinned': 'vless://pinned'});
    });
  });
}
