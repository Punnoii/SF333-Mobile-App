import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';

/// Handles reads/writes for the incidents collection.
class IncidentRepository {
  IncidentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<Incident>> fetchIncidents() async {
    final snapshot = await _firestore
        .collection('incidents')
        .orderBy('reportedAt', descending: true)
        .get();
    return snapshot.docs.map(Incident.fromFirestore).toList();
  }

  Future<void> persistIncidentAddress({
    required String incidentId,
    String? formattedAddress,
    Map<String, dynamic>? address,
  }) async {
    if (formattedAddress == null && address == null) return;
    await _firestore.collection('incidents').doc(incidentId).update({
      if (formattedAddress != null) 'formattedAddress': formattedAddress,
      if (address != null) 'address': address,
    });
  }
}
