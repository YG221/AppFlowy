import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_local_core/personal_local_core.dart';
import 'package:personal_local_ui/personal_local_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData.dark(),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('korean body search highlights and no-result state',
      (tester) async {
    await pump(
      tester,
      OfflineSearchPanel(
        loadDocuments: () async => const [
          SearchDocument(
            id: 'doc',
            title: '회의 메모',
            blocks: [
              SearchBlock(id: 'b', text: '본문에만 김치찌개'),
            ],
          ),
        ],
        onOpen: (_) {},
      ),
    );
    expect(find.byKey(const Key('search-empty')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('offline-search-field')), '김치찌개');
    await tester.pump();
    expect(find.textContaining('김치찌개'), findsWidgets);
    expect(find.byKey(const Key('search-hit-doc')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('offline-search-field')), '없는단어');
    await tester.pump();
    expect(find.byKey(const Key('search-none')), findsOneWidget);
  });

  testWidgets('batch selection skips the middle paragraph', (tester) async {
    final session = BatchEditSession(const [
      MemoBlock(id: 'a', text: '첫째'),
      MemoBlock(id: 'b', text: '중간'),
      MemoBlock(id: 'c', text: '셋째'),
    ]);
    await pump(tester, BatchEditPanel(session: session));
    await tester.tap(find.byKey(const Key('block-a')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('block-c')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('apply-text-color')));
    await tester.pump();
    expect(session.blocks[0].textColor, '#c62828');
    expect(session.blocks[1].textColor, isNull);
    expect(session.blocks[2].textColor, '#c62828');
    await tester.tap(find.byKey(const Key('undo-batch')));
    await tester.pump();
    expect(session.blocks[0].textColor, isNull);
  });

  testWidgets('popout is labeled read-only and shows the body', (tester) async {
    await pump(
      tester,
      const MemoPopoutView(
        title: '메모',
        body: '원본 본문',
        readOnly: true,
      ),
    );
    expect(find.byKey(const Key('popout-banner')), findsOneWidget);
    expect(find.text('원본 본문'), findsOneWidget);
    expect(find.textContaining('잠긴'), findsNothing);
  });

  testWidgets('local gate has no login', (tester) async {
    await pump(tester, LocalCreateGate(onCreate: () {}));
    expect(find.text('로그인'), findsNothing);
    expect(find.byKey(const Key('create-local-workspace')), findsOneWidget);
    expect(find.textContaining('비밀번호 잠금'), findsNothing);
  });

  testWidgets('import preview names new documents', (tester) async {
    await pump(
      tester,
      const ExchangePreview(
        titles: ['한글 제목'],
        encryptedCount: 1,
        notes: ['암호화되어 있지 않은 항목은 파일을 가진 사람이 읽을 수 있습니다.'],
      ),
    );
    expect(find.text('한글 제목'), findsOneWidget);
    expect(find.byKey(const Key('encrypted-count')), findsOneWidget);
    expect(find.textContaining('덮어쓰지'), findsOneWidget);
  });
}
