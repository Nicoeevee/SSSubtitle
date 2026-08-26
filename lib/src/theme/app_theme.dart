import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:m3e_core/m3e_core.dart';

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class AppColors {
  static const seed = Color(0xFF2563EB);
}

abstract final class AppRadii {
  static const panel = 28.0;
  static const field = 18.0;
  static const reading = 20.0;
}

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = M3EColorScheme.generate(
      seedColor: AppColors.seed,
      brightness: brightness,
      variant: M3EColorVariant.expressive,
    );

    final materialTypography = Typography.material2021();
    final expressiveTextTheme = M3ETypography.emphasized(
      brightness == Brightness.dark
          ? materialTypography.white
          : materialTypography.black,
      rond: 18,
      bodyRond: 12,
    );
    // material_ui exposes its own TextTheme type, so bridge each role while
    // preserving the M3E typography metrics and the bundled Google font.
    final textTheme = TextTheme(
      displayLarge: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.displayLarge,
      ),
      displayMedium: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.displayMedium,
      ),
      displaySmall: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.displaySmall,
      ),
      headlineLarge: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.headlineLarge,
      ),
      headlineMedium: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.headlineMedium,
      ),
      headlineSmall: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.headlineSmall,
      ),
      titleLarge: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.titleLarge,
      ),
      titleMedium: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.titleMedium,
      ),
      titleSmall: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.titleSmall,
      ),
      bodyLarge: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.bodyLarge,
      ),
      bodyMedium: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.bodyMedium,
      ),
      bodySmall: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.bodySmall,
      ),
      labelLarge: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.labelLarge,
      ),
      labelMedium: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.labelMedium,
      ),
      labelSmall: GoogleFonts.notoSansSc(
        textStyle: expressiveTextTheme.labelSmall,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 1,
        space: AppSpacing.md,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.secondaryContainer,
        circularTrackColor: scheme.secondaryContainer,
      ),
    );
  }
}
