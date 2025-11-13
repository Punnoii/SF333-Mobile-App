import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable representation of an incident record stored in Firestore.
class Incident {
  Incident({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.category,
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
      latitude: _asNullableDouble(data['latitude']),
      longitude: _asNullableDouble(data['longitude']),
      reportedAt: data['reportedAt'] is Timestamp ? data['reportedAt'] as Timestamp : null,
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
}
