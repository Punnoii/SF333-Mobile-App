import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'logging_service.dart';

class LocationService {
  static const String _logCategory = 'LocationService';
  static const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org/search';
  static const Duration _timeout = Duration(seconds: 3);
  static const String _cachePrefix = 'location_cache_';
  static const Duration _cacheExpiry = Duration(hours: 24);
  
  // Configuration - set to false to disable API calls temporarily
  static bool _enableApiSearch = false;
  static http.Client _httpClient = http.Client();
  
  static String _lastQuery = '';
  static List<Map<String, dynamic>> _lastResults = [];

  /// Allow overriding runtime configuration for testing or feature flags.
  @visibleForTesting
  static void configure({
    bool? enableApiSearch,
    http.Client? httpClient,
  }) {
    if (enableApiSearch != null) {
      _enableApiSearch = enableApiSearch;
    }
    if (httpClient != null) {
      _httpClient = httpClient;
    }
  }

  @visibleForTesting
  static void resetTestOverrides() {
    _enableApiSearch = false;
    _httpClient = http.Client();
    _lastQuery = '';
    _lastResults = [];
  }

  /// Search for places using Nominatim (OpenStreetMap) API with caching and debouncing
  /// Returns a list of location results with coordinates and display names
  static Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];
    
    final cleanQuery = query.trim().toLowerCase();
    
    // Return cached results if same query
    if (cleanQuery == _lastQuery && _lastResults.isNotEmpty) {
      return _lastResults;
    }
    
    // Check cache first
    final cachedResults = await _getCachedResults(cleanQuery);
    if (cachedResults.isNotEmpty) {
      _lastQuery = cleanQuery;
      _lastResults = cachedResults;
      return cachedResults;
    }
    
    // Skip API call for very short queries to reduce load or if API is disabled
    if (cleanQuery.length < 3 || !_enableApiSearch) {
      return [];
    }
    
    try {
      final encodedQuery = Uri.encodeComponent('$cleanQuery Thailand');
      final url = '$_nominatimBaseUrl?q=$encodedQuery&format=json&limit=10&countrycodes=th&addressdetails=1';
      
      final response = await _httpClient
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'PaisabaiApp/1.0 (Flutter Mobile App)',
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        // Filter and format results
        final results = data
            .where((item) => item['lat'] != null && item['lon'] != null)
            .take(10) // Limit results
            .map<Map<String, dynamic>>((item) {
          // Clean up display name for better readability
          String displayName = item['display_name'] ?? item['name'] ?? 'Unknown Place';
          
          // Shorten very long display names
          if (displayName.length > 80) {
            final parts = displayName.split(', ');
            if (parts.length > 3) {
              displayName = '${parts[0]}, ${parts[1]}, ${parts[2]}...';
            }
          }
          
          return {
            'type': 'place',
            'title': displayName,
            'latitude': double.tryParse(item['lat'].toString()) ?? 0.0,
            'longitude': double.tryParse(item['lon'].toString()) ?? 0.0,
            'source': 'api',
            'category': _categorizePlace(item),
          };
        }).toList();
        
        // Cache successful results
        await _cacheResults(cleanQuery, results);
        
        _lastQuery = cleanQuery;
        _lastResults = results;
        
        return results;
      } else {
        LoggingService.warning(
          'Nominatim API request failed with status: ${response.statusCode}',
          category: _logCategory,
        );
      }
    } on TimeoutException {
      LoggingService.warning(
        'Nominatim API timeout - using cached/static results only',
        category: _logCategory,
      );
    } catch (e, stack) {
      LoggingService.error(
        'Error searching places from Nominatim API',
        error: e,
        stackTrace: stack,
        category: _logCategory,
      );
    }
    
    return [];
  }

  /// Categorize places based on OpenStreetMap tags
  static String _categorizePlace(Map<String, dynamic> item) {
    final type = item['type']?.toString().toLowerCase() ?? '';
    final category = item['category']?.toString().toLowerCase() ?? '';
    
    if (category.contains('amenity')) {
      if (type.contains('restaurant') || type.contains('cafe')) return 'restaurant';
      if (type.contains('hospital') || type.contains('clinic')) return 'hospital';
      if (type.contains('school') || type.contains('university')) return 'education';
      if (type.contains('bank') || type.contains('atm')) return 'finance';
      return 'amenity';
    }
    
    if (category.contains('shop')) return 'shop';
    if (category.contains('tourism')) return 'tourism';
    if (category.contains('transport')) return 'transport';
    
    return 'general';
  }

  /// Cache results to local storage
  static Future<void> _cacheResults(String query, List<Map<String, dynamic>> results) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$query';
      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'results': results,
      };
      await prefs.setString(cacheKey, json.encode(cacheData));
    } catch (e, stack) {
      LoggingService.error(
        'Error caching results',
        error: e,
        stackTrace: stack,
        category: _logCategory,
      );
    }
  }
  
  /// Get cached results if they exist and are not expired
  static Future<List<Map<String, dynamic>>> _getCachedResults(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$query';
      final cachedString = prefs.getString(cacheKey);
      
      if (cachedString != null) {
        final cacheData = json.decode(cachedString);
        final timestamp = cacheData['timestamp'] as int;
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        
        // Check if cache is still valid
        if (DateTime.now().difference(cacheTime) < _cacheExpiry) {
          final results = (cacheData['results'] as List)
              .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
              .toList();
          return results;
        }
      }
    } catch (e, stack) {
      LoggingService.error(
        'Error reading cached results',
        error: e,
        stackTrace: stack,
        category: _logCategory,
      );
    }
    
    return [];
  }
  
  /// Clear old cache entries
  static Future<void> clearExpiredCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_cachePrefix));
      
      for (final key in keys) {
        final cachedString = prefs.getString(key);
        if (cachedString != null) {
          final cacheData = json.decode(cachedString);
          final timestamp = cacheData['timestamp'] as int;
          final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          
          if (DateTime.now().difference(cacheTime) >= _cacheExpiry) {
            await prefs.remove(key);
          }
        }
      }
    } catch (e, stack) {
      LoggingService.error(
        'Error clearing expired cache',
        error: e,
        stackTrace: stack,
        category: _logCategory,
      );
    }
  }
  
  /// Check if the location service is available
  static Future<bool> isServiceAvailable() async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse('$_nominatimBaseUrl?q=Bangkok&format=json&limit=1'),
            headers: {'User-Agent': 'PaisabaiApp/1.0 (Flutter Mobile App)'},
          )
          .timeout(const Duration(seconds: 2));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
