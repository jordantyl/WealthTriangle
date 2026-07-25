import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  // Default to Dark Mode because it looks cooler for finance apps
  bool _isDarkMode = true; 

  bool get isDarkMode => _isDarkMode;

  ThemeService() {
    _loadFromPrefs();
  }

  // Toggle the mode
  void toggleTheme(bool isOn) {
    _isDarkMode = isOn;
    _saveToPrefs();
    notifyListeners(); // Tells the whole app to repaint
  }

  // Save to storage
  _saveToPrefs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool('isDarkMode', _isDarkMode);
  }

  // Load from storage
  _loadFromPrefs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    notifyListeners();
  }
}