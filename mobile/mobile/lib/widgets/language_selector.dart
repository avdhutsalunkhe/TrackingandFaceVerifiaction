import 'package:flutter/material.dart';
import '../core/localization/language_service.dart';
import '../core/theme/app_theme.dart';

class LanguageSelectorPill extends StatelessWidget {
  final bool isDarkBackground;
  
  const LanguageSelectorPill({
    Key? key,
    this.isDarkBackground = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, locale, child) {
        final isMarathi = locale.languageCode == 'mr';

        return Container(
          decoration: BoxDecoration(
            color: isDarkBackground 
                ? Colors.white.withOpacity(0.18) 
                : AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkBackground 
                  ? Colors.white.withOpacity(0.3) 
                  : AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOption(
                label: 'EN',
                isSelected: !isMarathi,
                onTap: () => LanguageService.instance.setLanguage('en'),
              ),
              const SizedBox(width: 2),
              _buildOption(
                label: 'मराठी',
                isSelected: isMarathi,
                onTap: () => LanguageService.instance.setLanguage('mr'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDarkBackground ? Colors.white : AppColors.primary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? (isDarkBackground ? AppColors.primary : Colors.white)
                : (isDarkBackground ? Colors.white70 : AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class LanguageSelectorAction extends StatelessWidget {
  final bool isDark;
  
  const LanguageSelectorAction({Key? key, this.isDark = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Center(
        child: LanguageSelectorPill(isDarkBackground: isDark),
      ),
    );
  }
}
