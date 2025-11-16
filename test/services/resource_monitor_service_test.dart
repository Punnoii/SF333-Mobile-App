import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisabai_app/services/resource_monitor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.paisabai/diagnostics');
  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('sampleMemory returns stats when platform responds', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getMemoryStats');
      return {
        'residentSizeBytes': 1024 * 1024,
        'nativeHeapBytes': '2048',
        'physicalMemoryBytes': null,
        'pssBytes': '4096',
        'timestampMs': 123456789,
      };
    });

    final stats = await ResourceMonitorService.sampleMemory(contextLabel: 'test');

    expect(stats, isNotNull);
    expect(stats!.residentSizeMB, closeTo(1.0, 0.001));
    expect(stats.nativeHeapMB, closeTo(0.001953125, 0.0001));
    expect(stats.pssBytes, 4096);
    expect(stats.timestampMs, 123456789);
  });

  test('sampleMemory returns null when plugin is missing', () async {
    final stats = await ResourceMonitorService.sampleMemory();
    expect(stats, isNull);
  });

  test('sampleMemory returns null when platform throws', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'fail', message: 'boom'),
    );

    final stats = await ResourceMonitorService.sampleMemory();
    expect(stats, isNull);
  });
}
