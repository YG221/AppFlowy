import 'package:personal_local_core/personal_local_core.dart';
import 'package:test/test.dart';

void main() {
  test('korean body-only and title search with highlight', () {
    final docs = [
      const SearchDocument(
        id: 'a',
        title: '회의 메모',
        blocks: [
          SearchBlock(id: 'b1', text: '앞부분 내용'),
          SearchBlock(id: 'b2', text: '본문에만 있는 한글 단어 김치찌개 레시피'),
        ],
      ),
    ];

    final bodyHits = OfflineSearch.search(query: '김치찌개', documents: docs);
    expect(bodyHits, hasLength(1));
    expect(bodyHits.single.bodyMatch, isTrue);
    expect(bodyHits.single.titleMatch, isFalse);
    expect(bodyHits.single.blockId, 'b2');
    final snippet = bodyHits.single.snippet;
    final start = bodyHits.single.snippetHighlightStart;
    final end = bodyHits.single.snippetHighlightEnd;
    expect(snippet.substring(start, end), '김치찌개');

    final titleHits = OfflineSearch.search(query: '회의', documents: docs);
    expect(titleHits.single.titleMatch, isTrue);
    expect(
        titleHits.single.title.substring(
          titleHits.single.titleHighlightStart,
          titleHits.single.titleHighlightEnd,
        ),
        '회의');

    expect(
      OfflineSearch.search(query: 'CAFÉ', documents: [
        const SearchDocument(
          id: 'c',
          title: 'café menu',
          blocks: [SearchBlock(id: 'p', text: 'unicode café')],
        ),
      ]).single.bodyMatch,
      isTrue,
    );
  });

  test('empty query and no match are distinct empty lists', () {
    const docs = [
      SearchDocument(
        id: 'a',
        title: '제목',
        blocks: [SearchBlock(id: 'b', text: '본문')],
      ),
    ];
    expect(OfflineSearch.search(query: '   ', documents: docs), isEmpty);
    expect(OfflineSearch.search(query: '없는단어', documents: docs), isEmpty);
  });

  test('locked document is excluded even if plaintext is still in the list',
      () {
    const docs = [
      SearchDocument(
        id: 'secret',
        title: '비밀',
        blocks: [SearchBlock(id: 'b', text: '비밀번호 김치')],
      ),
    ];
    expect(
      OfflineSearch.search(
        query: '김치',
        documents: docs,
        excludedDocumentIds: {'secret'},
      ),
      isEmpty,
    );
  });
}
