# Paisabai App - Installation Guide

## Prerequisites

1. **Flutter SDK** (version 3.9.0 or higher)
   ```bash
   flutter --version
   ```

2. **Firebase Project Setup**
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Create a new project or use existing one
   - Enable Authentication (Email/Password)
   - Enable Firestore Database
   - Enable Storage

3. **iOS/Android Development Environment**
   - For iOS: Xcode 14+ and iOS Simulator
   - For Android: Android Studio and Android Emulator

## Installation Steps

### 1. Clone and Setup Dependencies
```bash
cd /path/to/paisabai_app
flutter pub get
```

### 2. Firebase Configuration
Your `firebase_options.dart` and `google-services.json` files are already configured.

### 3. Firestore Security Rules
Add these rules to your Firestore Database:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow all operations for authenticated users
    match /{document=**} {
      allow read, write, create, update, delete: if request.auth != null;
    }
  }
}
```

### 4. Cloudinary Setup
Profile images are stored using Cloudinary. Follow these steps:

1. **Create Upload Preset in Cloudinary Dashboard:**
   - Go to [Cloudinary Console](https://console.cloudinary.com/)
   - Settings → Upload → Upload presets → Add upload preset
   - **Preset name**: `ml_default`
   - **Signing Mode**: `Unsigned`
   - **Mode**: `Upload`
   - **Folder**: Leave empty (remove any folder path)
   - **Use filename**: No
   - **Unique filename**: Yes
   - **Public ID**: Auto-generate
   - Save the preset

2. **Upload Avatar Images:**
   - Upload these files to your Cloudinary media library:
     - `Avatar.png`, `Avatar-2.png`, `Avatar-3.png`, `Avatar-4.png`, `Avatar-5.png`
     - `Avatar-6.png`, `Avatar-7.png`, `Avatar-8.png`, `Avatar-9.png`

3. **Your Cloudinary credentials are configured:**
   - Cloud Name: `drmfjha9m`

### 5. Run the App
```bash
# For iOS Simulator
flutter run -d ios

# For Android Emulator  
flutter run -d android

# For Chrome (web testing)
flutter run -d chrome
```

## App Features

### ✅ Implemented Features
- **Authentication**: Login, Register, Change Password
- **Map Interface**: Interactive map with location selection popup
- **Forum**: Create posts, like, comment functionality
- **Chat System**: Real-time messaging between users
- **Profile Management**: Edit profile with image upload
- **Navigation**: Bottom navigation with 4 tabs

### 🎨 UI/UX Features
- Dark theme matching your design
- Responsive design for different screen sizes
- Real-time updates using Firestore streams
- Image upload and caching
- Modern Material Design components

## Troubleshooting

### Common Issues:

1. **Pod install fails (iOS)**
   ```bash
   cd ios
   pod install --repo-update
   ```

2. **Build fails**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

3. **Firebase connection issues**
   - Verify `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) are properly configured
   - Check Firebase project settings

4. **Permission issues (Image picker)**
   - iOS: Add camera/photo permissions to `ios/Runner/Info.plist`
   - Android: Permissions are handled automatically

## Next Steps

1. Test all functionality on your device/simulator
2. Customize colors and styling to match your exact design
3. Add additional features like push notifications
4. Deploy to App Store/Google Play when ready

The app now fully implements your design with all core features working!
