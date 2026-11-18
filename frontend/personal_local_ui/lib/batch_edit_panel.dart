import 'package:flutter/material.dart';
import 'package:personal_local_core/personal_local_core.dart';
import 'package:personal_local_ui/personal_copy.dart';

class BatchEditPanel extends StatefulWidget {
  const BatchEditPanel({
    super.key,
    required this.session,
    this.onCommit,
  });

  final BatchEditSession session;
  final VoidCallback? onCommit;

  @override
  State<BatchEditPanel> createState() => _BatchEditPanelState();
}

class _BatchEditPanelState extends State<BatchEditPanel> {
  final _find = TextEditingController();
  final _replace = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  void _refresh([String? message]) {
    setState(() => _message = message);
    widget.onCommit?.call();
  }

  Future<void> _replaceText() async {
    final preview = widget.session.previewReplace(
      find: _find.text,
      replace: _replace.text,
    );
    var confirmed = true;
    if (_replace.text.isEmpty || preview.selectedBecomeEmpty) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(PersonalCopy.text(context, '내용 바꾸기', 'Replace text')),
              content: Text(
                PersonalCopy.text(
                  context,
                  '선택한 문단에서 일치하는 글자를 바꿉니다. 빈 글자로 바꾸면 해당 부분이 지워집니다.',
                  'This replaces matches in the selected paragraphs. An empty replacement deletes them.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(PersonalCopy.text(context, '취소', 'Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(PersonalCopy.text(context, '바꾸기', 'Replace')),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!confirmed) {
      return;
    }
    try {
      widget.session.applyReplace(
        find: _find.text,
        replace: _replace.text,
        confirmed: true,
      );
      _refresh(
        PersonalCopy.text(
            context, '선택한 문단만 바꿨습니다.', 'Updated selected paragraphs.'),
      );
    } on BatchEditException catch (error) {
      _refresh(error.messageKo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = widget.session.blocks;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              PersonalCopy.text(
                context,
                '문단 선택',
                'Select paragraphs',
              ),
              style: theme.textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final block in blocks)
                  CheckboxListTile(
                    key: Key('block-${block.id}'),
                    value: widget.session.selected.contains(block.id),
                    onChanged: (_) {
                      widget.session.toggle(block.id);
                      _refresh();
                    },
                    title: Text(
                      block.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    secondary: block.textColor == null
                        ? null
                        : Container(
                            key: Key('color-${block.id}'),
                            width: 16,
                            height: 16,
                            color: _parse(block.textColor),
                          ),
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const Key('apply-text-color'),
                onPressed: () {
                  widget.session.setTextColor('#c62828');
                  _refresh();
                },
                child: Text(PersonalCopy.text(context, '글자색', 'Text color')),
              ),
              TextButton(
                key: const Key('apply-bg-color'),
                onPressed: () {
                  widget.session.setBackgroundColor('#fff2a8');
                  _refresh();
                },
                child: Text(PersonalCopy.text(context, '배경색', 'Background')),
              ),
              TextButton(
                key: const Key('undo-batch'),
                onPressed: widget.session.undoCount == 0
                    ? null
                    : () {
                        widget.session.undo();
                        _refresh();
                      },
                child: Text(PersonalCopy.text(context, '실행 취소', 'Undo')),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('find-field'),
                    controller: _find,
                    decoration: InputDecoration(
                      labelText: PersonalCopy.text(context, '찾기', 'Find'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('replace-field'),
                    controller: _replace,
                    decoration: InputDecoration(
                      labelText: PersonalCopy.text(context, '바꾸기', 'Replace'),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('apply-replace'),
                  onPressed: _replaceText,
                  child: Text(PersonalCopy.text(context, '적용', 'Apply')),
                ),
              ],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_message!, key: const Key('batch-message')),
            ),
        ],
      ),
    );
  }

  Color? _parse(String? hex) {
    if (hex == null || hex.length != 7) {
      return null;
    }
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) {
      return null;
    }
    return Color(0xFF000000 | value);
  }
}
