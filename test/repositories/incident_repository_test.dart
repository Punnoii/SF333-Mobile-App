import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisabai_app/repositories/incident_repository.dart';

void main() {
  group('IncidentRepository', () {
    late FakeFirebaseFirestore firestore;
    late IncidentRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = IncidentRepository(firestore: firestore);
    });

    test('fetchIncidents returns incidents ordered by timestamp desc', () async {
      await firestore.collection('incidents').doc('older').set({
        'title': 'Older',
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(1000),
      });
      await firestore.collection('incidents').doc('newer').set({
        'title': 'Newer',
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(2000),
      });

      final incidents = await repository.fetchIncidents();

      expect(incidents.map((i) => i.id).toList(), ['newer', 'older']);
      expect(incidents.first.title, 'Newer');
    });

    test('watchIncidents streams updates in order', () async {
      await firestore.collection('incidents').doc('one').set({
        'title': 'One',
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(1),
      });
      await firestore.collection('incidents').doc('two').set({
        'title': 'Two',
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(2),
      });

      final incidents = await repository.watchIncidents().first;

      expect(incidents.map((i) => i.id), ['two', 'one']);
    });

    test('watchBookmarkedIncidents filters by user', () async {
      await firestore.collection('incidents').doc('mine').set({
        'title': 'Mine',
        'bookmarkedBy': ['user-1'],
      });
      await firestore.collection('incidents').doc('other').set({
        'title': 'Other',
        'bookmarkedBy': ['user-2'],
      });

      final incidents = await repository.watchBookmarkedIncidents('user-1').first;

      expect(incidents, hasLength(1));
      expect(incidents.single.id, 'mine');
    });

    test('toggleBookmark adds and removes ids appropriately', () async {
      final docRef = firestore.collection('incidents').doc('toggle');
      await docRef.set({'bookmarkedBy': []});

      await repository.toggleBookmark(
        incidentId: 'toggle',
        userId: 'user-1',
        isBookmarked: false,
      );
      expect((await docRef.get())['bookmarkedBy'], contains('user-1'));

      await repository.toggleBookmark(
        incidentId: 'toggle',
        userId: 'user-1',
        isBookmarked: true,
      );
      expect((await docRef.get())['bookmarkedBy'], isEmpty);
    });

    test('persistIncidentAddress updates formattedAddress and address selectively', () async {
      final docRef = firestore.collection('incidents').doc('addr');
      await docRef.set({'title': 'Address test'});

      await repository.persistIncidentAddress(
        incidentId: 'addr',
        formattedAddress: 'Bangkok',
        address: {'district': 'Bang Rak'},
      );

      final data = (await docRef.get()).data();
      expect(data?['formattedAddress'], 'Bangkok');
      expect(data?['address'], containsPair('district', 'Bang Rak'));
    });
  });
}
