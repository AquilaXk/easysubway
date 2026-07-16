import 'package:easysubway_mobile/route_v2_ingress.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'MethodChannel attestor는 requestHash와 cloud project number만 전달한다',
    () async {
      const channel = MethodChannel('route-v2-integrity-test');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return 'decoded-integrity-token';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final attestor = MethodChannelPlayIntegrityAttestor(
        channel: channel,
        cloudProjectNumber: '123456789',
      );

      final token = await attestor.requestToken('request-hash');

      expect(token, 'decoded-integrity-token');
      expect(calls, hasLength(1));
      expect(calls.single.method, 'requestToken');
      expect(calls.single.arguments, {
        'requestHash': 'request-hash',
        'cloudProjectNumber': '123456789',
      });
    },
  );
}
