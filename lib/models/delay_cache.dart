import 'models.dart';

const delayCacheKeySeparator = '\u001f';

String buildDelayCacheKey({
  required int profileId,
  required String testUrl,
  required String proxyName,
}) {
  return [profileId, testUrl, proxyName].join(delayCacheKeySeparator);
}

({int profileId, String testUrl, String proxyName})? parseDelayCacheKey(
  String key,
) {
  final parts = key.split(delayCacheKeySeparator);
  if (parts.length != 3) return null;
  final profileId = int.tryParse(parts[0]);
  if (profileId == null) return null;
  return (profileId: profileId, testUrl: parts[1], proxyName: parts[2]);
}

DelayMap delayMapForProfile(Map<String, int> cache, int? profileId) {
  if (profileId == null || cache.isEmpty) return {};
  final result = <String, Map<String, int?>>{};
  for (final entry in cache.entries) {
    final parsed = parseDelayCacheKey(entry.key);
    if (parsed == null || parsed.profileId != profileId) continue;
    result.putIfAbsent(
      parsed.testUrl,
      () => <String, int?>{},
    )[parsed.proxyName] = entry.value;
  }
  return result;
}
