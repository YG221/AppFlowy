import 'package:flutter/widgets.dart';
import 'package:scaled_app/scaled_app.dart';

import 'personal_local/memo_popout_app.dart';
import 'startup/startup.dart';

Future<void> main(List<String> args) async {
  // The secondary engine is started with these arguments. It must not run
  // the normal startup: that loads the Rust core a second time and aborts.
  if (isMemoPopoutProcess(args)) {
    WidgetsFlutterBinding.ensureInitialized();
    final raw = args.length > 2 ? args[2] : '';
    final popout = MemoPopoutArgs.tryParse(raw) ??
        const MemoPopoutArgs(title: '', body: '', readOnly: true);
    runApp(MemoPopoutApp(args: popout));
    return;
  }

  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (_) => 1.0,
  );

  await runAppFlowy();
}
