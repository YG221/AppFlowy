import 'package:appflowy/personal_local/memo_popout_app.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:personal_local_core/personal_local_core.dart';
import 'package:personal_local_ui/personal_local_ui.dart';

class PersonalDocumentTools extends StatefulWidget {
  const PersonalDocumentTools({
    super.key,
    required this.editorState,
    required this.title,
  });

  final EditorState editorState;
  final String title;

  @override
  State<PersonalDocumentTools> createState() => _PersonalDocumentToolsState();
}

class _PersonalDocumentToolsState extends State<PersonalDocumentTools> {
  BatchEditSession? _session;
  List<MemoBlock> _applied = const [];
  Future<void> _pending = Future.value();

  void _openBatch() {
    final blocks = _blocksFromEditor(widget.editorState);
    setState(() {
      _session = BatchEditSession(blocks);
      _applied = blocks;
    });
  }

  void _sync() {
    final session = _session;
    if (session == null) {
      return;
    }
    final before = _applied;
    final after = List<MemoBlock>.from(session.blocks);
    _applied = after;
    _pending = _pending.then((_) {
      return applyBatchToEditor(
        editorState: widget.editorState,
        before: before,
        after: after,
      );
    });
  }

  Future<void> _popout() async {
    final body = _blocksFromEditor(widget.editorState)
        .map((block) => block.text)
        .join('\n');
    await openMemoPopout(title: widget.title, body: body);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: _openBatch, child: const Text('문단 선택')),
              TextButton(onPressed: _popout, child: const Text('작은 창으로 열기')),
            ],
          ),
        ),
        if (_session != null)
          SizedBox(
            height: 280,
            child: BatchEditPanel(
              session: _session!,
              onCommit: () {
                _sync();
              },
            ),
          ),
      ],
    );
  }
}

List<MemoBlock> _blocksFromEditor(EditorState editorState) {
  return editorState.document.root.children.map((node) {
    return MemoBlock(
      id: node.id,
      text: node.delta?.toPlainText() ?? '',
      textColor: _attribute(node, AppFlowyRichTextKeys.textColor),
      backgroundColor: _attribute(node, AppFlowyRichTextKeys.backgroundColor) ??
          _stringAttribute(node, blockComponentBackgroundColor),
      preserved: {
        'type': node.type,
      },
    );
  }).toList();
}

String? _stringAttribute(Node node, String key) {
  final value = node.attributes[key];
  return value is String && value.isNotEmpty ? value : null;
}

String? _attribute(Node node, String key) {
  final delta = node.delta;
  if (delta == null) {
    return null;
  }
  final encoded = delta.toJson();
  for (final item in encoded) {
    if (item is! Map) {
      continue;
    }
    final attributes = item['attributes'];
    if (attributes is! Map) {
      continue;
    }
    final value = attributes[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

Future<void> applyBatchToEditor({
  required EditorState editorState,
  required List<MemoBlock> before,
  required List<MemoBlock> after,
}) async {
  final beforeById = {for (final block in before) block.id: block};
  final nodes = {
    for (final node in editorState.document.root.children) node.id: node,
  };
  final transaction = editorState.transaction;
  var changed = false;
  for (final block in after) {
    final previous = beforeById[block.id];
    final node = nodes[block.id];
    if (previous == null || node == null || node.delta == null) {
      continue;
    }
    if (previous.text != block.text) {
      transaction.replaceText(node, 0, node.delta!.length, block.text);
      changed = true;
    }
    final length = block.text.length;
    if (previous.textColor != block.textColor && length > 0) {
      transaction.formatText(node, 0, length, {
        AppFlowyRichTextKeys.textColor: block.textColor ?? '',
      });
      changed = true;
    }
    if (previous.backgroundColor != block.backgroundColor && length > 0) {
      transaction.formatText(node, 0, length, {
        AppFlowyRichTextKeys.backgroundColor: block.backgroundColor ?? '',
      });
      transaction.updateNode(node, {
        blockComponentBackgroundColor: block.backgroundColor ?? '',
      });
      changed = true;
    }
  }
  if (changed) {
    await editorState.apply(transaction);
  }
}
