import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile', () {
    test('keeps subscription User-Agent in json round trip', () {
      final profile = Profile.normal(
        label: 'custom',
        url: 'https://example.com/sub',
        userAgent: defaultCustomSubscriptionUserAgent,
      );

      final json = profile.toJson();
      final restored = Profile.fromJson(json);

      expect(json['userAgent'], defaultCustomSubscriptionUserAgent);
      expect(restored.userAgent, defaultCustomSubscriptionUserAgent);
    });
  });
}
