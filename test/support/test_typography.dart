import 'dart:io';

import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> loadDeterministicTestFonts() async {
  var ancestor = File(Platform.resolvedExecutable).parent;
  Directory? fontDirectory;
  for (var depth = 0; depth < 12; depth++) {
    final candidate = Directory(
      '${ancestor.path}${Platform.pathSeparator}bin'
      '${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts'
      '${Platform.pathSeparator}material_fonts',
    );
    if (File(
      '${candidate.path}${Platform.pathSeparator}roboto-regular.ttf',
    ).existsSync()) {
      fontDirectory = candidate;
      break;
    }
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) break;
    ancestor = parent;
  }
  if (fontDirectory == null) {
    throw StateError('Flutter SDK Roboto fonts were not found.');
  }

  for (final family in const ['Roboto', 'Ahem']) {
    final loader = FontLoader(family)
      ..addFont(_readFont(fontDirectory, 'roboto-regular.ttf'))
      ..addFont(_readFont(fontDirectory, 'roboto-medium.ttf'))
      ..addFont(_readFont(fontDirectory, 'roboto-bold.ttf'));
    await loader.load();
  }
  final iconLoader = FontLoader('MaterialIcons')
    ..addFont(_readFont(fontDirectory, 'materialicons-regular.otf'));
  await iconLoader.load();
}

ThemeData deterministicTestTheme() {
  final theme = AppTheme.light;
  final buttonTextStyle = WidgetStatePropertyAll<TextStyle?>(
    theme.textTheme.labelLarge?.copyWith(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.w600,
    ),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(
        textStyle: buttonTextStyle,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        textStyle: buttonTextStyle,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: theme.textButtonTheme.style?.copyWith(textStyle: buttonTextStyle),
    ),
  );
}

Future<ByteData> _readFont(Directory directory, String name) async {
  final bytes = await File(
    '${directory.path}${Platform.pathSeparator}$name',
  ).readAsBytes();
  return ByteData.sublistView(bytes);
}
