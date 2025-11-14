import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;

import 'logging_service.dart';

/// Coordinates Firebase Performance traces, session network metrics, and
/// Timeline spans so we can build dashboards for cold start and background jobs.
class PerformanceMonitor {
  PerformanceMonitor._();

  static final PerformanceMonitor instance = PerformanceMonitor._();

  bool _enabled = false;
  Trace? _startupTrace;

  Future<void> enable() async {
    if (_enabled) return;
    try {
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);
      _enabled = true;
    } catch (error, stack) {
      LoggingService.warning(
        'Unable to enable Firebase Performance: $error',
        category: 'PerformanceMonitor',
      );
      LoggingService.error(
        'Stack when enabling Firebase Performance',
        error: error,
        stackTrace: stack,
        category: 'PerformanceMonitor',
      );
    }
  }

  Future<void> startStartupTrace({int? preTraceMillis}) async {
    if (!_enabled) return;
    _startupTrace = FirebasePerformance.instance.newTrace('app_startup');
    if (preTraceMillis != null && preTraceMillis > 0) {
      _startupTrace?.setMetric('pre_trace_ms', preTraceMillis);
    }
    await _startupTrace?.start();
  }

  void stopStartupTraceOnFirstFrame() {
    if (!_enabled || _startupTrace == null) return;
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) async {
      await _startupTrace?.stop();
      _startupTrace = null;
    });
  }

  Trace? startServiceTrace(String jobName) {
    if (!_enabled) return null;
    final sanitized = jobName.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
    final trace = FirebasePerformance.instance.newTrace('service_$sanitized');
    unawaited(trace.start());
    return trace;
  }

  Future<T> runTimelineTask<T>(String label, Future<T> Function() task) async {
    developer.Timeline.startSync(label);
    try {
      return await task();
    } finally {
      developer.Timeline.finishSync();
    }
  }
}

/// Hooks into SchedulerBinding to log slow frames when dev overlay is enabled.
class FrameMonitorService {
  FrameMonitorService._();

  static final FrameMonitorService instance = FrameMonitorService._();

  bool _initialized = false;

  void initialize({
    Duration slowFrameThreshold = const Duration(milliseconds: 16),
    bool logSlowFrames = false,
  }) {
    if (!logSlowFrames) {
      return;
    }
    if (_initialized) {
      return;
    }
    _initialized = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        final buildMs = timing.buildDuration.inMilliseconds;
        final rasterMs = timing.rasterDuration.inMilliseconds;
        if (timing.totalSpan >= slowFrameThreshold) {
          LoggingService.warning(
            'Slow frame build=${buildMs}ms raster=${rasterMs}ms',
            category: 'FrameMonitor',
          );
        }
      }
    });
  }
}

class SessionNetworkTracker {
  SessionNetworkTracker._();

  static final SessionNetworkTracker instance = SessionNetworkTracker._();

  final DateTime startedAt = DateTime.now().toUtc();
  final Map<String, _JobNetworkTotals> _jobTotals = {};
  int _bytesIn = 0;
  int _bytesOut = 0;

  int get bytesIn => _bytesIn;
  int get bytesOut => _bytesOut;

  void recordBytesIn(int bytes, {String? jobName}) {
    if (bytes <= 0) return;
    _bytesIn += bytes;
    if (jobName != null) {
      _jobTotals.putIfAbsent(jobName, () => _JobNetworkTotals(jobName)).bytesIn += bytes;
    }
  }

  void recordBytesOut(int bytes, {String? jobName}) {
    if (bytes <= 0) return;
    _bytesOut += bytes;
    if (jobName != null) {
      _jobTotals.putIfAbsent(jobName, () => _JobNetworkTotals(jobName)).bytesOut += bytes;
    }
  }

  void markJobCompleted({
    required String jobName,
    required Duration elapsed,
    required bool success,
    required int bytesIn,
    required int bytesOut,
    int? statusCode,
  }) {
    final totals = _jobTotals.putIfAbsent(jobName, () => _JobNetworkTotals(jobName));
    totals.lastLatency = elapsed;
    totals.lastStatusCode = statusCode;
    if (success) {
      totals.successful = min(totals.successful + 1, 1 << 30);
    } else {
      totals.failed = min(totals.failed + 1, 1 << 30);
    }
    if (totals.bytesIn == 0 && bytesIn > 0) {
      totals.bytesIn = bytesIn;
    }
    if (totals.bytesOut == 0 && bytesOut > 0) {
      totals.bytesOut = bytesOut;
    }

    LoggingService.info(
      'Job $jobName completed in ${elapsed.inMilliseconds}ms | '
      'bytesIn=$bytesIn bytesOut=$bytesOut status=${statusCode ?? '-'} success=$success',
      category: 'SessionNetwork',
    );
  }

  SessionNetworkSnapshot snapshot() {
    return SessionNetworkSnapshot(
      bytesIn: _bytesIn,
      bytesOut: _bytesOut,
      startedAt: startedAt,
      jobSummaries: _jobTotals.values
          .map(
            (job) => SessionJobSummary(
              jobName: job.jobName,
              bytesIn: job.bytesIn,
              bytesOut: job.bytesOut,
              successes: job.successful,
              failures: job.failed,
              lastLatency: job.lastLatency,
              lastStatusCode: job.lastStatusCode,
            ),
          )
          .toList(growable: false),
    );
  }
}

class SessionNetworkSnapshot {
  const SessionNetworkSnapshot({
    required this.bytesIn,
    required this.bytesOut,
    required this.startedAt,
    required this.jobSummaries,
  });

  final int bytesIn;
  final int bytesOut;
  final DateTime startedAt;
  final List<SessionJobSummary> jobSummaries;
}

class SessionJobSummary {
  const SessionJobSummary({
    required this.jobName,
    required this.bytesIn,
    required this.bytesOut,
    required this.successes,
    required this.failures,
    this.lastLatency,
    this.lastStatusCode,
  });

  final String jobName;
  final int bytesIn;
  final int bytesOut;
  final int successes;
  final int failures;
  final Duration? lastLatency;
  final int? lastStatusCode;
}

class _JobNetworkTotals {
  _JobNetworkTotals(this.jobName);

  final String jobName;
  int bytesIn = 0;
  int bytesOut = 0;
  int successful = 0;
  int failed = 0;
  Duration? lastLatency;
  int? lastStatusCode;
}

class ServiceJobScope {
  ServiceJobScope._(this.name) {
    _trace = PerformanceMonitor.instance.startServiceTrace(name);
    _stopwatch.start();
  }

  static final Object _zoneKey = Object();

  final String name;
  final Stopwatch _stopwatch = Stopwatch();
  Trace? _trace;
  int _bytesIn = 0;
  int _bytesOut = 0;
  Duration? _lastNetworkLatency;
  int? _lastStatusCode;
  bool _completed = false;

  static ServiceJobScope? get current =>
      Zone.current[_zoneKey] != null ? Zone.current[_zoneKey] as ServiceJobScope : null;

  static Future<T> run<T>(String name, Future<T> Function() task) {
    final scope = ServiceJobScope._(name);
    return runZoned(
      () async {
        try {
          final result = await task();
          scope._complete(success: true);
          return result;
        } catch (error, stack) {
          scope._complete(success: false, error: error, stackTrace: stack);
          rethrow;
        }
      },
      zoneValues: {_zoneKey: scope},
    );
  }

  void addBytesIn(int bytes) {
    if (bytes > 0) {
      _bytesIn += bytes;
    }
  }

  void addBytesOut(int bytes) {
    if (bytes > 0) {
      _bytesOut += bytes;
    }
  }

  void updateNetworkResult({Duration? latency, int? statusCode}) {
    _lastNetworkLatency = latency ?? _lastNetworkLatency;
    _lastStatusCode = statusCode ?? _lastStatusCode;
  }

  void _complete({required bool success, Object? error, StackTrace? stackTrace}) {
    if (_completed) return;
    _completed = true;
    _stopwatch.stop();
    final elapsed = _stopwatch.elapsed;

    if (_trace != null) {
      _trace!.setMetric('bytes_in', _bytesIn);
      _trace!.setMetric('bytes_out', _bytesOut);
      if (_lastNetworkLatency != null) {
        _trace!.setMetric('last_network_latency_ms', _lastNetworkLatency!.inMilliseconds);
      }
      if (_lastStatusCode != null) {
        _trace!.putAttribute('status_code', '${_lastStatusCode!}');
      }
      _trace!.putAttribute('success', '$success');
      unawaited(_trace!.stop());
    }

    SessionNetworkTracker.instance.markJobCompleted(
      jobName: name,
      elapsed: elapsed,
      success: success,
      bytesIn: _bytesIn,
      bytesOut: _bytesOut,
      statusCode: _lastStatusCode,
    );

    if (!success && error != null) {
      LoggingService.error(
        'Service job $name failed',
        error: error,
        stackTrace: stackTrace,
        category: 'ServiceJob',
      );
    }
  }
}

/// Wraps [http.Client] to intercept bytes per session/job without touching call sites.
class NetworkTrackedClient extends http.BaseClient {
  NetworkTrackedClient({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final scope = ServiceJobScope.current;
    final String? jobName = scope?.name;
    final int outboundBytes = _estimateRequestSize(request);
    if (outboundBytes > 0) {
      SessionNetworkTracker.instance.recordBytesOut(outboundBytes, jobName: jobName);
      scope?.addBytesOut(outboundBytes);
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (error) {
      stopwatch.stop();
      scope?.updateNetworkResult(latency: stopwatch.elapsed);
      rethrow;
    }

    final trackedStream = _wrapStream(
      response.stream,
      jobName: jobName,
      scope: scope,
      stopwatch: stopwatch,
      statusCode: response.statusCode,
    );

    return http.StreamedResponse(
      trackedStream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  Stream<List<int>> _wrapStream(
    Stream<List<int>> stream, {
    String? jobName,
    ServiceJobScope? scope,
    required Stopwatch stopwatch,
    required int statusCode,
  }) {
    return stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          SessionNetworkTracker.instance.recordBytesIn(data.length, jobName: jobName);
          scope?.addBytesIn(data.length);
          sink.add(data);
        },
        handleDone: (sink) {
          stopwatch.stop();
          scope?.updateNetworkResult(
            latency: stopwatch.elapsed,
            statusCode: statusCode,
          );
          sink.close();
        },
        handleError: (error, stack, sink) {
          stopwatch.stop();
          scope?.updateNetworkResult(
            latency: stopwatch.elapsed,
            statusCode: statusCode,
          );
          sink.addError(error, stack);
        },
      ),
    );
  }

  int _estimateRequestSize(http.BaseRequest request) {
    final length = request.contentLength;
    if (length != null && length > 0) {
      return length;
    }
    return 0;
  }

  @override
  void close() {
    _inner.close();
  }
}
