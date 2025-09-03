class UserModel {
  final String uid;
  final String username;
  final String email;
  final String phoneNumber;
  final String disabilityType;
  final String profileImageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.uid,
    required this.username,
    required this.email,
    required this.phoneNumber,
    required this.disabilityType,
    required this.profileImageUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromFirestore(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      username: data['username'] ?? '',
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      disabilityType: data['disabilityType'] ?? '',
      profileImageUrl: data['profileImageUrl'] ?? '',
      createdAt: data['createdAt']?.toDate(),
      updatedAt: data['updatedAt']?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'username': username,
      'email': email,
      'phoneNumber': phoneNumber,
      'disabilityType': disabilityType,
      'profileImageUrl': profileImageUrl,
      'updatedAt': DateTime.now(),
    };
  }
}
