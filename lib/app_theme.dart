import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Use wherever headings, labels, buttons, or high-impact text appears inline
  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) =>
      GoogleFonts.barlowCondensed(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      );

  // Use these helpers wherever numbers / stats / percentages appear inline
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    List<Shadow>? shadows,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        shadows: shadows,
      );

  static ThemeData get darkTheme {
    const primaryColor = Color(0xFF8B5CF6);
    const secondaryColor = Color(0xFFFF5C7A);
    const successColor = Color(0xFF2DD4BF);
    const backgroundColor = Color(0xFF0F0F17);    // Base — screen itself
    const deepBackgroundColor = Color(0xFF0F0F17); // Base — nav bar
    const surfaceColor = Color(0xFF181824);         // Surface — cards
    const elevatedColor = Color(0xFF202033);        // Elevated — rows, inputs inside cards
    const borderColor = Color(0xFF2A2A42);          // Rim — structural lines
    const textColor = Color(0xFFEEEEF5);
    const mutedTextColor = Color(0xFF8888A0);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: successColor,
      surface: surfaceColor,
      onSurface: textColor,
      onPrimary: Colors.white,
    ).copyWith(
      surfaceContainerHighest: elevatedColor,
    );

    // Inter as base, headings overridden to Barlow Condensed
    final textTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
      headlineLarge: GoogleFonts.barlowCondensed(
        color: textColor,
        fontSize: 36,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: GoogleFonts.barlowCondensed(
        color: textColor,
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: GoogleFonts.barlowCondensed(
        color: textColor,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: GoogleFonts.barlowCondensed(
        color: textColor,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: GoogleFonts.barlowCondensed(
        color: textColor,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: GoogleFonts.inter(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: GoogleFonts.inter(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: GoogleFonts.inter(
        color: mutedTextColor,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: GoogleFonts.inter(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: GoogleFonts.inter(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: GoogleFonts.inter(
        color: mutedTextColor,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: backgroundColor,

      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.barlowCondensed(
          color: textColor,
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),

      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderColor, width: 1),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.barlowCondensed(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.8),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: primaryColor,
          side: const BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.barlowCondensed(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.8),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: GoogleFonts.inter(color: mutedTextColor, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: mutedTextColor, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryColor, width: 1.4),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: successColor,
        borderRadius: BorderRadius.all(Radius.circular(999)),
        linearMinHeight: 8,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: deepBackgroundColor,
        indicatorColor: primaryColor,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(color: textColor, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceColor,
        contentTextStyle: GoogleFonts.inter(color: textColor, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      dividerColor: borderColor,
    );
  }
}
