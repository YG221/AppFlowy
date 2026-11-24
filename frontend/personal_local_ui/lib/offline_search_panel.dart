import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:personal_local_core/personal_local_core.dart';
import 'package:personal_local_ui/personal_copy.dart';

class OfflineSearchPanel extends StatefulWidget {
  const OfflineSearchPanel({
    super.key,
    required this.loadDocuments,
    required this.onOpen,
    this.excludedDocumentIds = const {},
    this.initialQuery = '',
  });

  final Future<List<SearchDocument>> Function() loadDocuments;
  final ValueChanged<SearchHit> onOpen;
  final Set<String> excludedDocumentIds;
  final String initialQuery;

  @override
  State<OfflineSearchPanel> createState() => _OfflineSearchPanelState();
}

class _OfflineSearchPanelState extends State<OfflineSearchPanel> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  var _loading = false;
  var _searched = false;
  List<SearchDocument> _documents = const [];
  List<SearchHit> _hits = const [];
  var _selected = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery.trim();
    if (query.isEmpty) {
      return;
    }
    _controller.text = query;
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _run(query);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _documents = await widget.loadDocuments();
      final hits = OfflineSearch.search(
        query: query,
        documents: _documents,
        excludedDocumentIds: widget.excludedDocumentIds,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _hits = hits;
        _selected = 0;
        _searched = query.trim().isNotEmpty;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _searched = true;
        _error = PersonalCopy.text(
          context,
          '검색 중 오류가 났습니다.',
          'Search failed.',
        );
      });
    }
  }

  void _move(int delta) {
    if (_hits.isEmpty) {
      return;
    }
    setState(() {
      _selected = (_selected + delta).clamp(0, _hits.length - 1);
    });
  }

  void _openSelection() {
    if (_hits.isEmpty) {
      return;
    }
    widget.onOpen(_hits[_selected]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emptyQuery = _controller.text.trim().isEmpty;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): _OpenIntent(),
      },
      child: Actions(
        actions: {
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (intent) => _move(intent.delta),
          ),
          _OpenIntent: CallbackAction<_OpenIntent>(
            onInvoke: (_) => _openSelection(),
          ),
        },
        child: Material(
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  PersonalCopy.text(context, '로컬 검색', 'Local search'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('offline-search-field'),
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  style: theme.textTheme.titleMedium,
                  decoration: InputDecoration(
                    filled: true,
                    hintText: PersonalCopy.text(
                      context,
                      '제목과 본문을 검색하세요',
                      'Search titles and document text',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _run,
                  onSubmitted: (_) => _openSelection(),
                ),
                const SizedBox(height: 12),
                Expanded(child: _body(theme, emptyQuery)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, bool emptyQuery) {
    if (_loading && _hits.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(key: Key('search-loading')),
      );
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (emptyQuery) {
      return Center(
        child: Text(
          PersonalCopy.text(
            context,
            '검색어를 입력하면 이 기기의 메모 제목과 본문을 찾습니다.',
            'Type to search titles and bodies on this device.',
          ),
          key: const Key('search-empty'),
        ),
      );
    }
    if (_searched && _hits.isEmpty) {
      return Center(
        child: Text(
          PersonalCopy.text(context, '결과 없음', 'No results'),
          key: const Key('search-none'),
        ),
      );
    }
    return ListView.builder(
      itemCount: _hits.length,
      itemBuilder: (context, index) {
        final hit = _hits[index];
        final selected = index == _selected;
        return ListTile(
          key: Key('search-hit-${hit.documentId}'),
          selected: selected,
          title: _highlight(
              hit.title, hit.titleHighlightStart, hit.titleHighlightEnd),
          subtitle: hit.snippet.isEmpty
              ? null
              : _highlight(
                  hit.snippet,
                  hit.snippetHighlightStart,
                  hit.snippetHighlightEnd,
                ),
          onTap: () {
            setState(() => _selected = index);
            widget.onOpen(hit);
          },
        );
      },
    );
  }

  Widget _highlight(String text, int start, int end) {
    if (start < 0 || end > text.length || start >= end) {
      return Text(text);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(backgroundColor: Color(0xFFFFF59D)),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);
  final int delta;
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}
