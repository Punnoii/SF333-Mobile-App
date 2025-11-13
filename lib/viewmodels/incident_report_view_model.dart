import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/incident.dart';
import '../repositories/incident_repository.dart';
import '../services/location_service.dart';

class IncidentReportViewModel extends ChangeNotifier {
  IncidentReportViewModel({
    required IncidentRepository repository,
  }) : _repository = repository;

  final IncidentRepository _repository;

  final List<String> _statusFilters = const [
    'All',
    'pending',
    'in_progress',
    'resolved',
    'closed',
  ];

  final Map<String, String> _statusLabels = const {
    'pending': 'รอดำเนินการ',
    'in_progress': 'กำลังดำเนินการ',
    'resolved': 'แก้ไขแล้ว',
    'closed': 'ปิดเหตุ',
  };

  final Map<String, String> _categoryLabels = const {
    'Traffic': 'การจราจร',
    'Accident': 'อุบัติเหตุ',
    'Road Work': 'ซ่อมถนน',
    'Hazard': 'จุดอันตราย',
    'Crime': 'เหตุอาชญากรรม',
    'Emergency': 'เหตุฉุกเฉิน',
    'Other': 'อื่นๆ',
  };

  List<Incident> _incidents = [];
  bool _isLoading = false;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  bool _onlyNearby = false;
  final double _nearbyRadiusKm = 10;
  Position? _currentPosition;
  bool _isLocating = false;
  final Map<String, String> _addressCache = {};
  final Set<String> _addressFetching = {};
  String? _errorMessage;

  List<Incident> get incidents => List.unmodifiable(_incidents);
  List<String> get statusFilters => List.unmodifiable(_statusFilters);
  bool get isLoading => _isLoading;
  String get selectedFilter => _selectedFilter;
  String get searchQuery => _searchQuery;
  bool get onlyNearby => _onlyNearby;
  double get nearbyRadiusKm => _nearbyRadiusKm;
  Position? get currentPosition => _currentPosition;
  bool get isLocating => _isLocating;
  String? get errorMessage => _errorMessage;

  List<Incident> get filteredIncidents {
    Iterable<Incident> filtered = _incidents;
    if (_selectedFilter != 'All') {
      filtered = filtered.where((incident) => incident.status == _selectedFilter);
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((incident) {
        final searchable = <String?>[
          incident.title,
          incident.description,
          incident.formattedAddress,
          ..._addressFields(incident.address),
        ];
        return searchable
            .whereType<String>()
            .any((value) => value.toLowerCase().contains(query));
      });
    }

    if (_onlyNearby && _currentPosition != null) {
      filtered = filtered.where((incident) {
        final distance = calculateDistanceKm(incident);
        return distance != null && distance <= _nearbyRadiusKm;
      });
    }

    return filtered.toList();
  }

  Future<void> loadIncidents() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _incidents = await _repository.fetchIncidents();
    } catch (e) {
      _errorMessage = 'ไม่สามารถโหลดรายการเหตุได้ กรุณาลองใหม่อีกครั้ง';
      if (kDebugMode) {
        debugPrint('Failed to load incidents: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadIncidents();

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void updateFilter(String filter) {
    if (_selectedFilter == filter) return;
    _selectedFilter = filter;
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  Future<bool> setOnlyNearby(bool enabled) async {
    if (enabled && _currentPosition == null) {
      final success = await _getCurrentLocation();
      if (!success) {
        notifyListeners();
        return false;
      }
    }
    _onlyNearby = enabled && _currentPosition != null;
    notifyListeners();
    return _onlyNearby;
  }

  Future<bool> requestLocation() async {
    final success = await _getCurrentLocation();
    notifyListeners();
    return success;
  }

  Future<bool> _getCurrentLocation() async {
    _isLocating = true;
    _errorMessage = null;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('ต้องเปิดการใช้งาน Location Service');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('ผู้ใช้ไม่อนุญาตให้เข้าถึงตำแหน่ง');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('ระบบปฏิเสธการเข้าถึงตำแหน่งถาวร');
      }

      _currentPosition = await Geolocator.getCurrentPosition();
      return true;
    } catch (e) {
      _currentPosition = null;
      _onlyNearby = false;
      _errorMessage = 'ไม่สามารถดึงตำแหน่งได้: ${e.toString()}';
      return false;
    } finally {
      _isLocating = false;
    }
  }

  String getStatusLabel(String status) => _statusLabels[status] ?? 'ไม่ทราบสถานะ';

  String getCategoryLabel(String category) => _categoryLabels[category] ?? category;

  String? getDisplayAddress(Incident incident) {
    final formatted = _formatAddress(incident);
    if (formatted != null && formatted.trim().isNotEmpty) {
      return formatted;
    }

    final cached = _addressCache[incident.id];
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    fetchAddressForIncident(incident);
    return null;
  }

  Future<void> fetchAddressForIncident(Incident incident) async {
    if (incident.id.isEmpty ||
        incident.latitude == null ||
        incident.longitude == null ||
        _addressCache.containsKey(incident.id) ||
        _addressFetching.contains(incident.id)) {
      return;
    }
    _addressFetching.add(incident.id);
    try {
      final addressData = await LocationService.reverseGeocode(
        incident.latitude!,
        incident.longitude!,
      );
      if (addressData == null) return;

      final formattedAddress = addressData['formattedAddress']?.toString();
      final fallbackAddress = [
        addressData['houseNumber'],
        addressData['road'],
        addressData['subdistrict'],
        addressData['district'],
        addressData['province'],
        addressData['postcode'],
      ]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(' ');

      final displayAddress = (formattedAddress != null && formattedAddress.trim().isNotEmpty)
          ? formattedAddress
          : (fallbackAddress.isNotEmpty ? fallbackAddress : null);

      if (displayAddress != null) {
        _addressCache[incident.id] = displayAddress;
        notifyListeners();
      }

    } finally {
      _addressFetching.remove(incident.id);
    }
  }

  double? calculateDistanceKm(Incident incident) {
    if (_currentPosition == null || incident.latitude == null || incident.longitude == null) {
      return null;
    }
    const earthRadius = 6371;
    final dLat = _degreesToRadians(incident.latitude! - _currentPosition!.latitude);
    final dLon = _degreesToRadians(incident.longitude! - _currentPosition!.longitude);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(_currentPosition!.latitude)) *
            cos(_degreesToRadians(incident.latitude!)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  String formatTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return 'ไม่ทราบเวลา';
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inDays > 0) {
      return '${difference.inDays} วันก่อน';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ชั่วโมงก่อน';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} นาทีก่อน';
    } else {
      return 'เพิ่งสักครู่';
    }
  }

  List<String?> _addressFields(Map<String, dynamic>? address) {
    if (address == null) return const [];
    return [
      address['houseNumber']?.toString(),
      address['road']?.toString(),
      address['subdistrict']?.toString(),
      address['district']?.toString(),
      address['province']?.toString(),
      address['postcode']?.toString(),
    ];
  }

  String? _formatAddress(Incident incident) {
    if (incident.formattedAddress != null && incident.formattedAddress!.trim().isNotEmpty) {
      return incident.formattedAddress;
    }

    final address = incident.address;
    if (address != null) {
      final parts = _addressFields(address)
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        return parts.join(' ');
      }
    }
    return null;
  }

  double _degreesToRadians(double degrees) => degrees * (pi / 180);
}
