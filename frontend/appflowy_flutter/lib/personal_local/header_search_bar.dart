import 'package:appflowy/personal_local/personal_local_search.dart';
import 'package:flutter/material.dart';
import 'package:personal_local_ui/personal_local_ui.dart';

/// Always-visible search field in the page header.
///
/// Clicking it, or typing in it, opens the existing workspace search.
class PersonalHeaderSearchBar extends StatefulWidget {
  const PersonalHeaderSearchBar({
    super.key,
    this.onOpen,
  });

  final Future<void> Function(String query)? onOpen;

  @override
  State<PersonalHeaderSearchBar> createState() =>
      _PersonalHeaderSearchBarState();
}

class _PersonalHeaderSearchBarState extends State<PersonalHeaderSearchBar> {
  final _controller = TextEditingController();
  var _opening = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(String query) async {
    if (_opening || !mounted) {
      return;
    }
    _opening = true;
    _controller.clear();
    try {
      final open = widget.onOpen ??
          (value) => showPersonalLocalSearch(context, initialQuery: value);
      await open(query);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = PersonalCopy.text(
      context,
      '페이지와 내용을 검색',
      'Search pages and content',
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: theme.dividerColor),
    );
    return Align(
      child: SizedBox(
        height: 36,
        child: TextField(
          key: const Key('header-search-field'),
          controller: _controller,
          textAlignVertical: TextAlignVertical.center,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            hintText: hint,
            prefixIcon: const Icon(Icons.search, size: 18),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 36,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
          onTap: () => _open(_controller.text),
          onChanged: (value) {
            if (value.isNotEmpty) {
              _open(value);
            }
          },
          onSubmitted: _open,
        ),
      ),
    );
  }
}
