import 'package:flutter_test/flutter_test.dart';
import 'package:paisabai_app/models/user_model.dart';

class _FakeTimestamp {
  _FakeTimestamp(this._date);

  final DateTime _date;

  DateTime toDate() => _date;
}

void main() {
  group('UserModel', () {
    test('fromFirestore maps Firestore document data correctly', () {
      final createdAt = DateTime.utc(2024, 01, 02, 12, 0, 0);
      final updatedAt = DateTime.utc(2024, 01, 03, 8, 30, 0);
      final data = {
        'username': 'alice',
        'email': 'alice@example.com',
        'phoneNumber': '123456789',
        'disabilityType': 'vision',
        'profileImageUrl': 'https://example.com/avatar.png',
        'createdAt': _FakeTimestamp(createdAt),
        'updatedAt': _FakeTimestamp(updatedAt),
      };

      final model = UserModel.fromFirestore(data, 'user-123');

      expect(model.uid, 'user-123');
      expect(model.username, 'alice');
      expect(model.email, 'alice@example.com');
      expect(model.phoneNumber, '123456789');
      expect(model.disabilityType, 'vision');
      expect(model.profileImageUrl, 'https://example.com/avatar.png');
      expect(model.createdAt, createdAt);
      expect(model.updatedAt, updatedAt);
    });

    test('fromFirestore falls back to safe defaults when data is missing', () {
      final model = UserModel.fromFirestore({}, 'user-xyz');

      expect(model.uid, 'user-xyz');
      expect(model.username, '');
      expect(model.email, '');
      expect(model.phoneNumber, '');
      expect(model.disabilityType, '');
      expect(model.profileImageUrl, '');
      expect(model.createdAt, isNull);
      expect(model.updatedAt, isNull);
    });

    test('toFirestore exports the persistent fields and generates a timestamp', () {
      final model = UserModel(
        uid: 'user-abc',
        username: 'Bob',
        email: 'bob@example.com',
        phoneNumber: '987654321',
        disabilityType: 'hearing',
        profileImageUrl: 'https://example.com/bob.png',
        createdAt: DateTime.utc(2024, 1, 1),
      );

      final before = DateTime.now();
      final map = model.toFirestore();
      final after = DateTime.now();

      expect(map, containsPair('username', 'Bob'));
      expect(map, containsPair('email', 'bob@example.com'));
      expect(map, containsPair('phoneNumber', '987654321'));
      expect(map, containsPair('disabilityType', 'hearing'));
      expect(map, containsPair('profileImageUrl', 'https://example.com/bob.png'));

      final updatedAt = map['updatedAt'] as DateTime?;
      expect(updatedAt, isNotNull);
      expect(updatedAt!.isAfter(before) || updatedAt.isAtSameMomentAs(before), isTrue);
      expect(updatedAt.isBefore(after) || updatedAt.isAtSameMomentAs(after), isTrue);
    });
  });
}
