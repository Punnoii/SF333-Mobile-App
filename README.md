# Paisabai App

Paisabai เป็น Flutter application สำหรับรายงานเหตุ แจ้งเตือนผู้ใช้งาน และสนทนากันแบบเรียลไทม์ โดยเชื่อมต่อกับ Firebase (Auth/Firestore/Storage/Messaging) และ Cloudinary สำหรับจัดการรูปภาพ

## Requirements

- Flutter SDK 3.9.0+
- Xcode 14+ (iOS) / Android Studio + Android SDK (Android)
- Firebase Project ที่เปิดใช้ Authentication, Cloud Firestore, Storage, Cloud Messaging
- Cloudinary account (ใช้สำหรับเก็บรูปโปรไฟล์)
- FCM server key (เก็บไว้ฝั่ง backend เท่านั้น ห้ามฝังใน client)

## Quick Start

1. **Clone และติดตั้ง dependency**
   ```bash
   git clone <repo-url>
   cd SF333-Mobile-App
   flutter pub get
   ```

2. **เตรียมไฟล์ environment**
   ```bash
   cp .env.example .env    # ถ้ายังไม่มีให้คัดลอกจาก template
   ```
   กรอกค่าที่จำเป็น (อย่า commit ไฟล์ .env)
   ```
   FIREBASE_API_KEY_ANDROID=<your-key>
   FIREBASE_APP_ID_ANDROID=<your-app-id>
   FIREBASE_PROJECT_ID=<project-id>
   FIREBASE_STORAGE_BUCKET=<bucket>
   FIREBASE_MESSAGING_SENDER_ID=<sender-id>
   FIREBASE_API_KEY_IOS=<ios-key>
   FIREBASE_APP_ID_IOS=<ios-app-id>
   FIREBASE_BUNDLE_IOS_ID=<bundle-id>
   FIREBASE_API_KEY_WEB=<web-key>
   FIREBASE_APP_ID_WEB=<web-app-id>

   CLOUDINARY_CLOUD_NAME=<cloud-name>
   CLOUDINARY_UPLOAD_PRESET=<unsigned-preset>
   CLOUDINARY_BASE_IMAGE_PATH=paisabai
   ```

3. **ตั้งค่า Firebase Native Files**
   - Android: วาง `android/app/google-services.json`
   - iOS: วาง `ios/Runner/GoogleService-Info.plist`
   - สามารถใช้ `flutterfire configure` เพื่อสร้างไฟล์เหล่านี้อัตโนมัติ

4. **รันแอป**
   ```bash
   flutter run -d ios        # หรือ android / chrome
   ```

5. **ตรวจสอบโค้ด**
   ```bash
   flutter analyze
   flutter test
   ```

## Deployment Notes

- Production build ควรใช้ `--dart-define` หรือ secret manager ใน CI/CD เพื่อส่งค่าคอนฟิกแทนการพก `.env` จริงไปกับแอป
- ย้ายการส่ง push notification ไปไว้บน backend (เช่น Cloud Functions) โดยใช้ FCM server key ที่ฝั่ง server
- Rotate key ทุกครั้งที่พบว่ามีการรั่วไหล

### Push Notification Flow

1. ตัวแอปจะบันทึกรายการใหม่ลงใน Firestore collection `notifications` พร้อมข้อมูลผู้รับ/แชท
2. Backend service (แนะนำ Cloud Function ที่ authenticate ด้วย Firebase Admin SDK) รับ event จาก collection นี้แล้วเรียก `admin.messaging().send()` ไปยัง FCM
3. FCM server key จึงอยู่เฉพาะบน backend และไม่ถูก bundle ใน APK/IPA

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| `Unable to load asset: .env` | ตรวจว่ามีไฟล์ `.env` ในเครื่องและไม่ได้ลบออกจาก assets |
| Firebase auth/storage ใช้ไม่ได้ | ตรวจค่าที่กรอกใน `.env` และไฟล์ `google-services.json` / `GoogleService-Info.plist` |
| Cloudinary upload ล้มเหลว | ตรวจ `CLOUDINARY_*` ให้ถูกต้องและ preset ต้องเป็น unsigned |
| Push notification ไม่เด้ง | ตรวจว่า FCM token ถูกบันทึกใน Firestore และ backend ใช้ server key ถูกต้อง |

รายละเอียดเพิ่มเติม เช่น การสร้าง Cloudinary preset หรือ Firestore index ดูได้ที่ `README_INSTALLATION.md`
