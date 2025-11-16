import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paisabai_app/services/monitoring_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServiceJobScope', () {
    test('records successful job completion', () async {
      await ServiceJobScope.run('job_success', () async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });

      final snapshot = SessionNetworkTracker.instance.snapshot();
      final summary = snapshot.jobSummaries.firstWhere(
        (job) => job.jobName == 'job_success',
        orElse: () => throw StateError('job_success not recorded'),
      );

      expect(summary.successes, greaterThan(0));
      expect(summary.failures, equals(0));
      expect(summary.lastLatency, isNotNull);
    });

    test('records failed jobs without swallowing error', () async {
      await expectLater(
        () => ServiceJobScope.run('job_fail', () async => throw Exception('boom')),
        throwsException,
      );

      final snapshot = SessionNetworkTracker.instance.snapshot();
      final summary = snapshot.jobSummaries.firstWhere(
        (job) => job.jobName == 'job_fail',
        orElse: () => throw StateError('job_fail not recorded'),
      );

      expect(summary.failures, greaterThan(0));
      expect(summary.successes, 0);
    });
  });

  group('NetworkTrackedClient', () {
    test('tracks bytes in/out and status codes for requests', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.contentLength, greaterThan(0));
        return http.Response('reply', 201);
      });

      await ServiceJobScope.run('network_job', () async {
        final client = NetworkTrackedClient(inner: mockClient);
        final request = http.Request('POST', Uri.parse('https://example.com'))
          ..bodyBytes = utf8.encode('payload');
        final response = await client.send(request);
        expect(await response.stream.bytesToString(), 'reply');
      });

      final snapshot = SessionNetworkTracker.instance.snapshot();
      final summary = snapshot.jobSummaries.firstWhere(
        (job) => job.jobName == 'network_job',
        orElse: () => throw StateError('network_job not recorded'),
      );

      expect(summary.bytesOut, greaterThanOrEqualTo(7), reason: 'Tracks outbound payload');
      expect(summary.bytesIn, greaterThanOrEqualTo(5), reason: 'Tracks inbound response length');
      expect(summary.lastStatusCode, 201);
    });
  });
}
