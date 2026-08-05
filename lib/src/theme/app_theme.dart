import 'package:flutter/material.dart';
import 'package:care_navigator_ph/src/design_system/app_typography.dart';

export 'package:care_navigator_ph/src/design_system/app_icons.dart';

/// Care Navigator PH visual language.
///
/// A calm blue clinical palette is shared by every route. Legacy semantic names
/// remain so existing screens inherit the same theme without route-by-route
/// color overrides.
abstract final class AppColors {
  // The core palette is intentionally quiet: ink and off-white do the
  // structural work, while blue is reserved for care actions and highlights.
  static const evergreen = Color(0xFF123B5D);
  static const evergreenDark = Color(0xFF0E2A43);
  static const forest = Color(0xFF2E6BFF);
  static const sea = Color(0xFF5B91FF);
  static const seaGlass = Color(0xFFE1EBFF);
  static const alabaster = Color(0xFFF6F6F2);
  static const paper = Colors.white;
  static const fog = Color(0xFFEFEFEA);
  static const coral = Color(0xFFFF6B57);
  static const coralSoft = Color(0xFFFFECE7);
  static const cobalt = Color(0xFF1747C8);
  static const sunflower = Color(0xFFAEC7FF);
  static const outline = Color(0xFFD8D8D1);
  static const ink = Color(0xFF16324F);
  static const inkMuted = Color(0xFF6F6F69);
  static const danger = Color(0xFFC9372C);
  static const warning = Color(0xFF985F00);
  static const success = Color(0xFF147D64);

  // Compatibility aliases. New components should use the semantic names.
  static const navy = evergreenDark;
  static const blue = forest;
  static const blueDark = evergreen;
  static const teal = sea;
  static const mint = seaGlass;
  static const canvas = alabaster;
  static const surfaceMuted = fog;
  static const deepGreen = evergreenDark;
  static const softMint = seaGlass;
  static const mist = Color(0xFFBEC5D0);
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  static const massive = 64.0;
}

abstract final class AppRadius {
  static const small = 10.0;
  static const control = 0.0;
  // Buttons use a modest radius so they read as soft rectangles rather than
  // sharp controls or pill-shaped actions.
  static const button = 14.0;
  static const medium = 14.0;
  static const large = 20.0;
  static const extraLarge = 28.0;
  static const feature = 36.0;
  static const xlarge = extraLarge;
}

abstract final class AppShadows {
  static const medium = <BoxShadow>[
    BoxShadow(color: Color(0x24102A43), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

abstract final class AppBreakpoints {
  static const compact = 600.0;
  static const medium = 920.0;
  static const expanded = 1200.0;
}

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.forest,
      onPrimary: Colors.white,
      primaryContainer: AppColors.seaGlass,
      onPrimaryContainer: AppColors.evergreenDark,
      secondary: AppColors.evergreen,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.fog,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.cobalt,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFE8ECFF),
      onTertiaryContainer: Color(0xFF172B77),
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.coralSoft,
      onErrorContainer: Color(0xFF6F2119),
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.fog,
      onSurfaceVariant: AppColors.inkMuted,
      outline: AppColors.outline,
      outlineVariant: Color(0xFFE4E4DE),
      shadow: Color(0x24102A43),
      scrim: Color(0x99102A43),
      inverseSurface: AppColors.evergreenDark,
      onInverseSurface: Colors.white,
      inversePrimary: AppColors.sunflower,
    );
    final baseText = Typography.material2021().black.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.evergreenDark,
      fontFamily: AppTypography.fontFamily,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.alabaster,
      canvasColor: AppColors.alabaster,
      dividerColor: AppColors.outline,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: baseText.copyWith(
        displayLarge: baseText.displayLarge?.copyWith(
          fontSize: 56,
          height: 1.02,
          fontWeight: FontWeight.w800,
          letterSpacing: -2.2,
        ),
        displayMedium: baseText.displayMedium?.copyWith(
          fontSize: 46,
          height: 1.06,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.7,
        ),
        displaySmall: baseText.displaySmall?.copyWith(
          fontSize: 36,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.15,
        ),
        headlineLarge: baseText.headlineLarge?.copyWith(
          fontSize: 32,
          height: 1.12,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: baseText.headlineMedium?.copyWith(
          fontSize: 27,
          height: 1.16,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontSize: 22,
          height: 1.22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontSize: 16,
          height: 1.32,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontSize: 14,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.55,
          letterSpacing: .05,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(
          color: AppColors.inkMuted,
          fontSize: 14,
          height: 1.5,
        ),
        bodySmall: baseText.bodySmall?.copyWith(
          color: AppColors.inkMuted,
          fontSize: 12,
          height: 1.45,
        ),
        labelLarge: baseText.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: .05,
        ),
        labelMedium: baseText.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: .15,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.alabaster,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 84,
        titleSpacing: AppSpacing.lg,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paper,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelStyle: const TextStyle(color: AppColors.inkMuted),
        hintStyle: const TextStyle(color: Color(0xFF8A8A83)),
        prefixIconColor: AppColors.inkMuted,
        suffixIconColor: AppColors.inkMuted,
        border: _inputBorder(AppColors.outline),
        enabledBorder: _inputBorder(AppColors.outline),
        disabledBorder: _inputBorder(const Color(0xFFE4E4DE)),
        focusedBorder: _inputBorder(AppColors.forest, width: 1.7),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.evergreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFD3D3CD),
          disabledForegroundColor: const Color(0xFF85857F),
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.paper,
          foregroundColor: AppColors.evergreen,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: AppColors.evergreen, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.evergreen,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: AppColors.evergreen, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.forest,
          minimumSize: const Size(40, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.extraLarge),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shadowColor: const Color(0x24102A43),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        titleTextStyle: baseText.headlineSmall,
        contentTextStyle: baseText.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.extraLarge),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.extraLarge),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.fog,
        selectedColor: AppColors.seaGlass,
        disabledColor: const Color(0xFFE9ECEA),
        side: BorderSide.none,
        labelStyle: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.evergreen,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: AppColors.forest,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: AppColors.forest,
        unselectedLabelColor: AppColors.inkMuted,
        labelStyle: TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        minTileHeight: 60,
        iconColor: AppColors.inkMuted,
        textColor: AppColors.ink,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.forest,
        linearTrackColor: AppColors.seaGlass,
        circularTrackColor: AppColors.seaGlass,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.evergreenDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.evergreenDark,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.paper),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              side: const BorderSide(color: AppColors.outline),
            ),
          ),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: color, width: width),
      );
}
