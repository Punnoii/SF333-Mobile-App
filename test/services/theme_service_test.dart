import 'package:flutter_test/flutter_test.dart';
import 'package:paisabai_app/services/theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _flushAsync() async {
  await pumpEventQueue(times: 5);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeService', () {
    test('defaults to dark mode when no preference is stored', () async {
      final service = ThemeService();
      await _flushAsync();

      expect(service.isDarkMode, isTrue);
    });

    test('loads stored preference during initialization', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': false});

      final service = ThemeService();
      await _flushAsync();

      expect(service.isDarkMode, isFalse);
    });

    test('toggleTheme flips the value and persists it', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': true});

      final service = ThemeService();
      await _flushAsync();

      expect(service.isDarkMode, isTrue);

      await service.toggleTheme();
      expect(service.isDarkMode, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('theme_mode'), isFalse);
    });

    test('toggleTheme prevents concurrent toggles but allows later changes', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': true});

      final service = ThemeService();
      await _flushAsync();

      final firstToggle = service.toggleTheme();
      final secondToggle = service.toggleTheme(); // Should be ignored while first is running.

      await Future.wait([firstToggle, secondToggle]);

      expect(service.isDarkMode, isFalse, reason: 'Only one toggle should have applied');

      await service.toggleTheme();
      expect(service.isDarkMode, isTrue, reason: 'Toggle should work again once previous call finished');
    });
  });
}
