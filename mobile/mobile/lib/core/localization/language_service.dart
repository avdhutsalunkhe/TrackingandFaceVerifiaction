import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static final LanguageService instance = LanguageService._internal();

  LanguageService._internal();

  static const String _prefKey = 'user_selected_language';
  final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(const Locale('en'));

  String get currentLanguageCode => localeNotifier.value.languageCode;
  bool get isMarathi => currentLanguageCode == 'mr';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString(_prefKey) ?? 'en';
      localeNotifier.value = Locale(savedLang);
    } catch (_) {
      localeNotifier.value = const Locale('en');
    }
  }

  Future<void> setLanguage(String langCode) async {
    if (langCode != 'en' && langCode != 'mr') return;
    localeNotifier.value = Locale(langCode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, langCode);
    } catch (_) {}
  }

  Future<void> toggleLanguage() async {
    final nextLang = isMarathi ? 'en' : 'mr';
    await setLanguage(nextLang);
  }
}
