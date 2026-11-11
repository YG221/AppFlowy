import 'package:flutter/material.dart';

class PersonalCopy {
  const PersonalCopy._();

  static bool korean(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode;
    return code == null || code == 'ko';
  }

  static String text(BuildContext context, String ko, String en) =>
      korean(context) ? ko : en;
}
