import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:scaled_app/scaled_app.dart';

import 'personal_local/memo_popout_app.dart';
import 'startup/startup.dart';

Future<void> main() async {
  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (_) => 1.0,
  );

  try {
    final controller = await WindowController.fromCurrentEngine();
    final popout = MemoPopoutArgs.tryParse(controller.arguments);
    if (popout != null) {
      runApp(MemoPopoutApp(args: popout));
      return;
    }
  } catch (_) {
    // The primary window is not a memo popout.
  }

  await runAppFlowy();
}
