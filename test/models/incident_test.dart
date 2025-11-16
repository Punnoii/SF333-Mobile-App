import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisabai_app/models/incident.dart';

void main() {
  group('Incident.fromFirestore', () {
    test('maps fields, trims empty lists, and casts numeric values', () async {
      final firestore = FakeFirebaseFirestore();
      final docRef = firestore.collection('incidents').doc('incident-1');
      await docRef.set({
        'title': 'Blocked sidewalk',
        'description': 'Wheelchair access blocked by vendor carts',
        'status': 'open',
        'category': 'Accessibility',
        'reporterId': 'user-1',
        'reporterName': 'Alice',
        'reporterEmail': 'alice@example.com',
        'bookmarkedBy': ['user-1', '', null],
        'affectedDisabilityTypes': ['mobility', null, '  '],
        'latitude': '13.7563',
        'longitude': 100.5018,
        'reportedAt': Timestamp.fromMillisecondsSinceEpoch(5000),
        'formattedAddress': 'Bangkok, Thailand',
        'address': {'city': 'Bangkok'},
      });

      final snapshot = await docRef.get();
      final incident = Incident.fromFirestore(snapshot);

      expect(incident.id, 'incident-1');
      expect(incident.title, 'Blocked sidewalk');
      expect(incident.description, contains('Wheelchair'));
      expect(incident.status, 'open');
      expect(incident.category, 'Accessibility');
      expect(incident.reporterId, 'user-1');
      expect(incident.reporterName, 'Alice');
      expect(incident.reporterEmail, 'alice@example.com');
      expect(incident.bookmarkedBy, equals(['user-1']));
      expect(incident.affectedDisabilityTypes, equals(['mobility']));
      expect(incident.latitude, closeTo(13.7563, 0.0001));
      expect(incident.longitude, closeTo(100.5018, 0.0001));
      expect(incident.reportedAt, isA<Timestamp>());
      expect(incident.formattedAddress, 'Bangkok, Thailand');
      expect(incident.address, containsPair('city', 'Bangkok'));
    });

    test('handles missing and null data safely', () async {
      final firestore = FakeFirebaseFirestore();
      final docRef = firestore.collection('incidents').doc('incident-2');
      await docRef.set({});

      final snapshot = await docRef.get();
      final incident = Incident.fromFirestore(snapshot);

      expect(incident.title, isEmpty);
      expect(incident.description, isEmpty);
      expect(incident.status, 'pending');
      expect(incident.category, 'Other');
      expect(incident.bookmarkedBy, isEmpty);
      expect(incident.affectedDisabilityTypes, isEmpty);
      expect(incident.latitude, isNull);
      expect(incident.longitude, isNull);
      expect(incident.formattedAddress, isNull);
      expect(incident.address, isNull);
    });
  });

  test('copyWith overrides only provided fields', () async {
    final firestore = FakeFirebaseFirestore();
    final docRef = firestore.collection('incidents').doc('incident-3');
    await docRef.set({
      'title': 'Broken curb',
      'description': 'Cracked ramp',
      'reporterId': 'user-3',
    });

    final incident = Incident.fromFirestore(await docRef.get());
    final updated = incident.copyWith(
      formattedAddress: 'New Address',
      address: {'district': 'Bang Rak'},
    );

    expect(updated.id, incident.id);
    expect(updated.title, incident.title);
    expect(updated.formattedAddress, 'New Address');
    expect(updated.address, containsPair('district', 'Bang Rak'));
    expect(incident.formattedAddress, isNull);
    expect(incident.address, isNull);
  });
}
