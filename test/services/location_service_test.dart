import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paisabai_app/services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _cacheKey(String query) => 'location_cache_${query.trim().toLowerCase()}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocationService.resetTestOverrides();
  });

  group('LocationService.searchPlaces', () {
    test('returns empty list when the query is blank', () async {
      expect(await LocationService.searchPlaces(''), isEmpty);
      expect(await LocationService.searchPlaces('   '), isEmpty);
    });

    test('returns empty list for short queries when no cache is present', () async {
      expect(await LocationService.searchPlaces('ab'), isEmpty);
    });

    test('returns empty list when API calls are disabled and no cache exists', () async {
      expect(await LocationService.searchPlaces('Bangkok'), isEmpty);
    });

    test('returns cached results even when API calls are disabled', () async {
      final query = 'Bangkok';
      final cachedResults = [
        {
          'type': 'place',
          'title': 'Bangkok, Thailand',
          'latitude': 13.7563,
          'longitude': 100.5018,
          'source': 'cache',
          'category': 'general',
        },
      ];

      final cacheData = jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'results': cachedResults,
      });

      SharedPreferences.setMockInitialValues({_cacheKey(query): cacheData});

      final results = await LocationService.searchPlaces(query);

      expect(results, equals(cachedResults));
    });
  });

  group('LocationService.searchPlaces with API enabled', () {
    test('returns formatted results from the API', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.queryParameters['q']?.toLowerCase(),
          contains('bangkok thailand'),
        );
        final results = [
          {
            'display_name': 'Bangkok, Thailand',
            'lat': '13.7563',
            'lon': '100.5018',
            'type': 'city',
            'category': 'boundary',
          },
        ];
        return http.Response(jsonEncode(results), 200, headers: {'content-type': 'application/json'});
      });

      LocationService.configure(enableApiSearch: true, httpClient: mockClient);

      final results = await LocationService.searchPlaces('Bangkok');

      expect(results, hasLength(1));
      final first = results.first;
      expect(first['title'], 'Bangkok, Thailand');
      expect(first['latitude'], closeTo(13.7563, 0.0001));
      expect(first['longitude'], closeTo(100.5018, 0.0001));
      expect(first['category'], 'general');
      expect(first['source'], 'api');
    });

    test('trims overly long display names', () async {
      final mockClient = MockClient((request) async {
        final results = [
          {
            'display_name':
                'Long Name Part 1, Long Name Part 2, Long Name Part 3, Long Name Part 4, Long Name Part 5',
            'lat': '1',
            'lon': '1',
            'type': 'station',
            'category': 'transport',
          },
        ];
        return http.Response(jsonEncode(results), 200);
      });

      LocationService.configure(enableApiSearch: true, httpClient: mockClient);

      final results = await LocationService.searchPlaces('Station');

      expect(results.first['title'], 'Long Name Part 1, Long Name Part 2, Long Name Part 3...');
      expect(results.first['category'], 'transport');
    });

    test('returns empty list when API responds with non-200', () async {
      final mockClient = MockClient((request) async => http.Response('Server error', 500));

      LocationService.configure(enableApiSearch: true, httpClient: mockClient);

      expect(await LocationService.searchPlaces('Bangkok'), isEmpty);
    });

    test('returns empty list when HTTP client throws', () async {
      final mockClient = MockClient((request) async => throw TimeoutException('boom'));

      LocationService.configure(enableApiSearch: true, httpClient: mockClient);

      expect(await LocationService.searchPlaces('Bangkok'), isEmpty);
    });
  });

  group('LocationService.clearExpiredCache', () {
    test('removes only expired cache entries', () async {
      final expiredTimestamp =
          DateTime.now().subtract(const Duration(hours: 25)).millisecondsSinceEpoch;
      final freshTimestamp =
          DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;

      SharedPreferences.setMockInitialValues({
        'location_cache_old': jsonEncode({'timestamp': expiredTimestamp, 'results': []}),
        'location_cache_new': jsonEncode({'timestamp': freshTimestamp, 'results': []}),
      });

      await LocationService.clearExpiredCache();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('location_cache_old'), isNull);
      expect(prefs.getString('location_cache_new'), isNotNull);
    });
  });
}
