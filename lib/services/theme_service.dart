import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  bool _isDarkMode = true; // Default to dark mode (current design)

  bool get isDarkMode => _isDarkMode;

  ThemeService() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_themeKey) ?? true; // Default to dark
      notifyListeners();
    } catch (e) {
      // If loading fails, keep default value and notify
      notifyListeners();
    }
  }

  bool _isToggling = false;

  Future<void> toggleTheme() async {
    // Prevent rapid toggling that can cause race conditions
    if (_isToggling) return;
    
    _isToggling = true;
    
    try {
      _isDarkMode = !_isDarkMode;
      notifyListeners();
      
      // Add small delay to prevent UI flicker
      await Future.delayed(const Duration(milliseconds: 100));
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeKey, _isDarkMode);
    } catch (e) {
      // Revert on error
      _isDarkMode = !_isDarkMode;
      notifyListeners();
    } finally {
      // Add delay before allowing next toggle
      await Future.delayed(const Duration(milliseconds: 200));
      _isToggling = false;
    }
  }

  ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.teal,
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.black.withOpacity(0.9),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      selectedItemColor: Colors.tealAccent,
      unselectedItemColor: Colors.grey,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: Colors.grey[900],
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.tealAccent,
      textColor: Colors.white,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
      titleLarge: TextStyle(color: Colors.white),
      titleMedium: TextStyle(color: Colors.white),
    ),
    iconTheme: const IconThemeData(color: Colors.tealAccent),
    cardTheme: CardThemeData(
      color: Colors.grey[800],
      elevation: 4,
    ),
  );

  ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.teal,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 1,
      iconTheme: IconThemeData(color: Colors.teal),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Colors.teal,
      unselectedItemColor: Colors.black54, // Changed from Colors.grey to darker
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.teal,
      textColor: Colors.black,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.black),
      bodyMedium: TextStyle(color: Colors.black),
      titleLarge: TextStyle(color: Colors.black),
      titleMedium: TextStyle(color: Colors.black),
      bodySmall: TextStyle(color: Colors.black87), // Added for better readability
      labelMedium: TextStyle(color: Colors.black87), // Added for better readability
      labelSmall: TextStyle(color: Colors.black54), // Added for better readability
    ),
    iconTheme: const IconThemeData(color: Colors.teal),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 2,
    ),
    // Add color scheme for better text contrast
    colorScheme: const ColorScheme.light(
      primary: Colors.teal,
      onSurface: Colors.black87, // Main text color
      onSurfaceVariant: Colors.black54, // Secondary text color
    ),
  );
}
