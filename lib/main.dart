import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/main_map_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'services/logging_service.dart';
import 'services/location_service.dart';
import 'services/monitoring_service.dart';
import 'services/resource_monitor_service.dart';
import 'config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure location search API is enabled even if initialization fails later
  LocationService.setApiSearchEnabled(true);

  final bootstrapTimer = Stopwatch()..start();

  await runZonedGuarded<Future<void>>(
    () async {
      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        LoggingService.error(
          'Flutter error caught',
          error: details.exception,
          stackTrace: details.stack,
          category: 'FlutterError',
        );
      };

      try {
        // Load environment variables with timeout
        await dotenv.load(fileName: ".env").timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            LoggingService.warning(
              'Environment loading timed out, continuing with defaults',
              category: 'AppBootstrap',
            );
          },
        );

        // Initialize Firebase with timeout
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Firebase initialization timed out');
          },
        );

        await PerformanceMonitor.instance.enable();
        await PerformanceMonitor.instance.startStartupTrace(
          preTraceMillis: bootstrapTimer.elapsedMilliseconds,
        );
        FrameMonitorService.instance.initialize(
          slowFrameThreshold: AppConfig.slowFrameThreshold,
          logSlowFrames: AppConfig.logSlowFrames || AppConfig.enablePerformanceOverlay,
        );

        // Initialize notification service
        await NotificationService.initialize();

        runApp(const MyApp());
        PerformanceMonitor.instance.stopStartupTraceOnFirstFrame();
        unawaited(ResourceMonitorService.sampleMemory(contextLabel: 'post_bootstrap'));
      } catch (e, stack) {
        await FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
        LoggingService.error(
          'App initialization error',
          error: e,
          stackTrace: stack,
          category: 'AppBootstrap',
        );
        runApp(const MyApp());
        PerformanceMonitor.instance.stopStartupTraceOnFirstFrame();
      }
    },
    (error, stack) async {
      await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      LoggingService.error(
        'Uncaught zone error',
        error: error,
        stackTrace: stack,
        category: 'AppBootstrap',
      );
    },
  );
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
            showPerformanceOverlay: AppConfig.enablePerformanceOverlay && kDebugMode,
            home: const SplashScreen(),
            routes: {
              '/main': (_) => const MainMapScreen(),
              '/login': (_) => const LoginScreen(),
              '/register': (_) => const RegisterScreen(),
              '/change-password': (_) => const ChangePasswordScreen(),
              '/edit-profile': (_) => const EditProfileScreen(),
            },
          );
        },
      ),
    );
  }
}
