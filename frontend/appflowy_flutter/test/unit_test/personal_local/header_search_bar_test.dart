import 'package:appflowy/personal_local/header_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('header search is a wide field with a magnifier', (tester) async {
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 44,
            child: PersonalHeaderSearchBar(
              onOpen: (query) async => queries.add(query),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('페이지와 내용을 검색'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('header-search-field'))).width,
      greaterThan(600),
    );

    await tester.tap(find.byKey(const Key('header-search-field')));
    await tester.pump();
    expect(queries, ['']);

    await tester.enterText(
      find.byKey(const Key('header-search-field')),
      '메모',
    );
    await tester.pump();
    expect(queries, ['', '메모']);
  });
}
