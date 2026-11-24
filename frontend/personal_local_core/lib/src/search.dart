class SearchBlock {
  const SearchBlock({required this.id, required this.text});

  final String id;
  final String text;
}

class SearchDocument {
  const SearchDocument({
    required this.id,
    required this.title,
    required this.blocks,
  });

  final String id;
  final String title;
  final List<SearchBlock> blocks;

  String get body => blocks.map((block) => block.text).join('\n');
}

class SearchHit {
  const SearchHit({
    required this.documentId,
    required this.title,
    required this.titleMatch,
    required this.bodyMatch,
    required this.snippet,
    required this.snippetHighlightStart,
    required this.snippetHighlightEnd,
    required this.titleHighlightStart,
    required this.titleHighlightEnd,
    this.blockId,
  });

  final String documentId;
  final String title;
  final bool titleMatch;
  final bool bodyMatch;
  final String snippet;
  final int snippetHighlightStart;
  final int snippetHighlightEnd;
  final int titleHighlightStart;
  final int titleHighlightEnd;
  final String? blockId;
}

class OfflineSearch {
  const OfflineSearch._();

  static const int snippetRadius = 36;

  /// Unicode case-fold via Dart [String.toLowerCase]. Hangul syllables match
  /// as substrings. This does not call a network service.
  static List<SearchHit> search({
    required String query,
    required List<SearchDocument> documents,
    Set<String> excludedDocumentIds = const {},
  }) {
    final needle = query.toLowerCase();
    final trimmed = needle.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final hits = <SearchHit>[];
    for (final document in documents) {
      if (excludedDocumentIds.contains(document.id)) {
        continue;
      }
      final titleFold = document.title.toLowerCase();
      final titleAt = titleFold.indexOf(trimmed);
      SearchBlock? matched;
      var bodyAt = -1;
      for (final block in document.blocks) {
        final at = block.text.toLowerCase().indexOf(trimmed);
        if (at >= 0) {
          matched = block;
          bodyAt = at;
          break;
        }
      }
      if (titleAt < 0 && bodyAt < 0) {
        continue;
      }

      final snippet = _snippet(
        source: matched?.text ?? document.body,
        matchAt: bodyAt,
        matchLength: trimmed.length,
      );
      hits.add(
        SearchHit(
          documentId: document.id,
          title: document.title,
          titleMatch: titleAt >= 0,
          bodyMatch: bodyAt >= 0,
          snippet: snippet.text,
          snippetHighlightStart: snippet.start,
          snippetHighlightEnd: snippet.end,
          titleHighlightStart: titleAt < 0 ? -1 : titleAt,
          titleHighlightEnd: titleAt < 0 ? -1 : titleAt + trimmed.length,
          blockId: matched?.id,
        ),
      );
    }
    return hits;
  }

  static ({String text, int start, int end}) _snippet({
    required String source,
    required int matchAt,
    required int matchLength,
  }) {
    if (matchAt < 0 || source.isEmpty) {
      return (text: '', start: -1, end: -1);
    }
    final start = matchAt > snippetRadius ? matchAt - snippetRadius : 0;
    final rawEnd = matchAt + matchLength + snippetRadius;
    final end = rawEnd > source.length ? source.length : rawEnd;
    final prefix = start > 0 ? '…' : '';
    final suffix = end < source.length ? '…' : '';
    final text = '$prefix${source.substring(start, end)}$suffix';
    final highlightStart = prefix.length + (matchAt - start);
    return (
      text: text,
      start: highlightStart,
      end: highlightStart + matchLength,
    );
  }
}
