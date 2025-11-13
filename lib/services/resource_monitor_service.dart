import 'package:flutter/services.dart';

import 'logging_service.dart';

class ResourceMonitorService {
  static const MethodChannel _channel = MethodChannel('com.paisabai/diagnostics');

  static Future<MemoryStats?> sampleMemory({String contextLabel = 'runtime'}) async {
    try {
      final response = await _channel.invokeMethod<Map<dynamic, dynamic>>('getMemoryStats');
      if (response == null) {
        return null;
      }
      final stats = MemoryStats.fromMap(Map<String, dynamic>.from(response));
      LoggingService.info(
        'Memory[$contextLabel] rss=${stats.residentSizeMB.toStringAsFixed(1)}MB '
        'nativeHeap=${stats.nativeHeapMB?.toStringAsFixed(1) ?? '-'}MB',
        category: 'ResourceMonitor',
      );
      return stats;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error, stack) {
      LoggingService.warning(
        'Platform exception collecting memory stats: ${error.message}',
        category: 'ResourceMonitor',
      );
      LoggingService.error(
        'Error collecting memory stats',
        error: error,
        stackTrace: stack,
        category: 'ResourceMonitor',
      );
      return null;
    }
  }
}

class MemoryStats {
  const MemoryStats({
    required this.residentSizeBytes,
    required this.timestampMs,
    this.nativeHeapBytes,
    this.physicalMemoryBytes,
    this.pssBytes,
  });

  final int residentSizeBytes;
  final int timestampMs;
  final int? nativeHeapBytes;
  final int? physicalMemoryBytes;
  final int? pssBytes;

  double get residentSizeMB => residentSizeBytes / (1024 * 1024);

  double? get nativeHeapMB =>
      nativeHeapBytes != null ? nativeHeapBytes! / (1024 * 1024) : null;

  factory MemoryStats.fromMap(Map<String, dynamic> map) {
    return MemoryStats(
      residentSizeBytes: map['residentSizeBytes'] is int
          ? map['residentSizeBytes'] as int
          : int.tryParse('${map['residentSizeBytes']}') ?? 0,
      nativeHeapBytes: _parseInt(map['nativeHeapBytes']),
      physicalMemoryBytes: _parseInt(map['physicalMemoryBytes']),
      pssBytes: _parseInt(map['pssBytes']),
      timestampMs: _parseInt(map['timestampMs']) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse('$value');
  }
}
