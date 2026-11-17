import 'package:flutter/material.dart';

class AppTheme {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.light);

  static void toggle() {
    mode.value = mode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}
