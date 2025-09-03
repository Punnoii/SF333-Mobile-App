import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/main_map_screen.dart';
import 'screens/login_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeService(),
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'Paisabai Auth',
            debugShowCheckedModeBanner: false,
            theme: themeService.isDarkMode ? themeService.darkTheme : themeService.lightTheme,
            home: const SplashScreen(),
            routes: {
              '/main': (_) => const MainMapScreen(),
              '/login': (_) => const LoginScreen(),
              '/change-password': (_) => const ChangePasswordScreen(),
              '/edit-profile': (_) => const EditProfileScreen(),
            },
          );
        },
      ),
    );
  }
}

