import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF070B14);
  static const bgCard = Color(0xFF0D1424);
  static const bgCardLight = Color(0xFF111D30);
  static const primary = Color(0xFF00C8FF);
  static const primaryDark = Color(0xFF0080FF);
  static const primaryGlow = Color(0x3300C8FF);
  static const accent = Color(0xFF1E6FFF);
  static const success = Color(0xFF00E676);
  static const warning = Color(0xFFFFB300);
  static const error = Color(0xFFFF3D57);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF7A8FAE);
  static const textHint = Color(0xFF3D5070);
  static const border = Color(0xFF1A2B42);
  static const borderLight = Color(0xFF243650);

  static const gradientPrimary = LinearGradient(
    colors: [Color(0xFF00C8FF), Color(0xFF0055FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientCard = LinearGradient(
    colors: [Color(0xFF0D1424), Color(0xFF0A1020)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientBg = LinearGradient(
    colors: [Color(0xFF070B14), Color(0xFF0A0F1E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.bgCard,
        error: AppColors.error,
      ),
      textTheme: GoogleFonts.manropeTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: AppColors.textPrimary),
          displayMedium: TextStyle(color: AppColors.textPrimary),
          displaySmall: TextStyle(color: AppColors.textPrimary),
          headlineLarge: TextStyle(color: AppColors.textPrimary),
          headlineMedium: TextStyle(color: AppColors.textPrimary),
          headlineSmall: TextStyle(color: AppColors.textPrimary),
          titleLarge: TextStyle(color: AppColors.textPrimary),
          titleMedium: TextStyle(color: AppColors.textPrimary),
          titleSmall: TextStyle(color: AppColors.textSecondary),
          bodyLarge: TextStyle(color: AppColors.textPrimary),
          bodyMedium: TextStyle(color: AppColors.textSecondary),
          bodySmall: TextStyle(color: AppColors.textHint),
          labelLarge: TextStyle(color: AppColors.textPrimary),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        indicatorColor: AppColors.primaryGlow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(color: AppColors.textHint, fontSize: 11);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary);
          }
          return const IconThemeData(color: AppColors.textHint);
        }),
      ),
      dividerColor: AppColors.border,
      cardColor: AppColors.bgCard,
    );
  }
}

class AppTextStyles {
  static TextStyle get button => GoogleFonts.getFont(
    'Onest',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
    letterSpacing: 0,
    color: Colors.white,
  );
}
