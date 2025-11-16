import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable representation of an incident record stored in Firestore.
class Incident {
  Incident({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.category,
    required this.reporterId,
    required this.reporterName,
    required this.reporterEmail,
    required this.bookmarkedBy,
    required this.affectedDisabilityTypes,
    required this.latitude,
    required this.longitude,
    required this.reportedAt,
    required this.formattedAddress,
    required this.address,
  });

  final String id;
  final String title;
  final String description;
  final String status;
  final String category;
  final String reporterId;
  final String reporterName;
  final String reporterEmail;
  final List<String> bookmarkedBy;
  final List<String> affectedDisabilityTypes;
  final double? latitude;
  final double? longitude;
  final Timestamp? reportedAt;
  final String? formattedAddress;
  final Map<String, dynamic>? address;

  factory Incident.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Incident(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
      category: (data['category'] ?? 'Other').toString(),
      reporterId: (data['reporterId'] ?? '').toString(),
      reporterName: (data['reporterName'] ?? '').toString(),
      reporterEmail: (data['reporterEmail'] ?? '').toString(),
      bookmarkedBy: _asStringList(data['bookmarkedBy']),
      affectedDisabilityTypes: _asStringList(data['affectedDisabilityTypes']),
      latitude: _asNullableDouble(data['latitude']),
      longitude: _asNullableDouble(data['longitude']),
      reportedAt: _asTimestamp(data['reportedAt']) ?? _asTimestamp(data['timestamp']),
      formattedAddress: data['formattedAddress']?.toString(),
      address: data['address'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(data['address'] as Map<String, dynamic>)
          : null,
    );
  }

  Incident copyWith({
    String? formattedAddress,
    Map<String, dynamic>? address,
  }) {
    return Incident(
      id: id,
      title: title,
      description: description,
      status: status,
      category: category,
      reporterId: reporterId,
      reporterName: reporterName,
      reporterEmail: reporterEmail,
      bookmarkedBy: bookmarkedBy,
      affectedDisabilityTypes: affectedDisabilityTypes,
      latitude: latitude,
      longitude: longitude,
      reportedAt: reportedAt,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      address: address ?? this.address,
    );
  }

  static double? _asNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static List<String> _asStringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item?.toString())
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList();
    }
    return [];
  }

  static Timestamp? _asTimestamp(dynamic value) {
    return value is Timestamp ? value : null;
  }
}
