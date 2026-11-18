import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const memoPopoutKind = 'memo-popout';
const memoPopoutEntrypoint = 'multi_window';

/// True when this Dart process is the read-only popout engine.
bool isMemoPopoutProcess(List<String> args) {
  return args.isNotEmpty && args.first == memoPopoutEntrypoint;
}

class MemoPopoutArgs {
  const MemoPopoutArgs({
    required this.title,
    required this.body,
    required this.readOnly,
  });

  final String title;
  final String body;
  final bool readOnly;

  Map<String, Object?> toJson() => {
        'kind': memoPopoutKind,
        'title': title,
        'body': body,
        'readOnly': true,
      };

  static MemoPopoutArgs? tryParse(String raw) {
    if (!raw.contains(memoPopoutKind)) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return MemoPopoutArgs(
        title: decoded['title'] as String? ?? '',
        body: decoded['body'] as String? ?? '',
        readOnly: true,
      );
    } catch (_) {
      return null;
    }
  }
}

class MemoPopoutApp extends StatefulWidget {
  const MemoPopoutApp({super.key, required this.args});

  final MemoPopoutArgs args;

  @override
  State<MemoPopoutApp> createState() => _MemoPopoutAppState();
}

class _MemoPopoutAppState extends State<MemoPopoutApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListTile(
              title: Text('읽기 전용 작은 창'),
              subtitle: Text('원본 메모는 이 창에서 수정되지 않습니다.'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.args.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(widget.args.body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openMemoPopout({
  required String title,
  required String body,
}) async {
  final args = MemoPopoutArgs(
    title: title,
    body: body,
    readOnly: true,
  );
  final controller = await WindowController.create(
    WindowConfiguration(
      arguments: jsonEncode(args.toJson()),
      hiddenAtLaunch: false,
    ),
  );
  await controller.show();
}
