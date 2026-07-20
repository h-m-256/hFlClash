import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_api/rust_api.dart';

void main() {
  final rustApi = _FakeRustLibApi();

  setUpAll(() {
    RustLib.initMock(api: rustApi);
  });

  tearDownAll(RustLib.dispose);

  setUp(rustApi.reset);

  test('resolves request URL and decrypts tagged response', () async {
    final adapter = _SubscriptionAdapter(encryptTag: 'response-tag');
    final dio = Dio()..httpClientAdapter = adapter;
    final request = Request(clashDio: dio);
    rustApi.resolvedUrl = 'https://example.com/sub?key=key01';
    rustApi.decryptedBody = Uint8List.fromList([4, 5, 6]);

    final response = await request.getFileResponseForUrl(
      'happ://crypt/payload',
      userAgent: 'Custom/1.0',
      headers: const {'X-HWID': 'device-id'},
    );

    expect(rustApi.resolvedInput, 'happ://crypt/payload');
    expect(adapter.options?.uri.toString(), rustApi.resolvedUrl);
    expect(adapter.options?.headers['User-Agent'], 'Custom/1.0');
    expect(adapter.options?.headers['X-HWID'], 'device-id');
    expect(rustApi.decryptUrl, rustApi.resolvedUrl);
    expect(rustApi.encryptedBody, [1, 2, 3]);
    expect(rustApi.encryptTag, 'response-tag');
    expect(response.data, [4, 5, 6]);
    expect(
      response.headers.value('content-disposition'),
      'attachment; filename=profile.yaml',
    );
    expect(response.headers.value('subscription-userinfo'), 'upload=1');
  });

  test('leaves an untagged response body in Dart', () async {
    final adapter = _SubscriptionAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final request = Request(clashDio: dio);
    rustApi.resolvedUrl = 'https://example.com/sub';

    final response = await request.getFileResponseForUrl(rustApi.resolvedUrl);

    expect(response.data, [1, 2, 3]);
    expect(rustApi.decryptUrl, isNull);
  });
}

class _SubscriptionAdapter implements HttpClientAdapter {
  final String? encryptTag;
  RequestOptions? options;

  _SubscriptionAdapter({this.encryptTag});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    return ResponseBody.fromBytes(
      [1, 2, 3],
      200,
      headers: {
        if (encryptTag != null) 'encrypt-tag': [encryptTag!],
        'content-disposition': ['attachment; filename=profile.yaml'],
        'subscription-userinfo': ['upload=1'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeRustLibApi extends RustLibApi {
  String resolvedUrl = '';
  Uint8List decryptedBody = Uint8List(0);
  String? resolvedInput;
  String? decryptUrl;
  List<int>? encryptedBody;
  String? encryptTag;

  void reset() {
    resolvedUrl = '';
    decryptedBody = Uint8List(0);
    resolvedInput = null;
    decryptUrl = null;
    encryptedBody = null;
    encryptTag = null;
  }

  @override
  Future<String> crateApiSubscriptionResolveSubscriptionInput({
    required String input,
  }) async {
    resolvedInput = input;
    return resolvedUrl;
  }

  @override
  Future<Uint8List> crateApiSubscriptionDecryptSubscriptionResponse({
    required String url,
    required List<int> body,
    String? encryptTag,
  }) async {
    decryptUrl = url;
    encryptedBody = body;
    this.encryptTag = encryptTag;
    return decryptedBody;
  }

  @override
  Future<void> crateApiInitInitApp() async {}

  @override
  Future<bool> crateApiIpcIpcServerStatus() async => false;

  @override
  Future<bool> crateApiIpcIsIpcConnected() async => false;

  @override
  Stream<Uint8List> crateApiIpcRestartIpcServer({required String name}) =>
      const Stream.empty();

  @override
  Future<void> crateApiIpcSendIpcMessage({required List<int> data}) async {}

  @override
  Future<void> crateApiIpcStopIpcServer() async {}
}
