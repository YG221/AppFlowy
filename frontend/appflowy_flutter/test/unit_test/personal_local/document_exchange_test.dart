import 'dart:typed_data';

import 'package:appflowy/personal_local/personal_local_exchange.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_local_core/personal_local_core.dart';

import '../../util.dart';

void main() {
  late AppFlowyUnitTest testContext;

  setUpAll(() async {
    testContext = await AppFlowyUnitTest.ensureInitialized();
  });

  test('export and import a live document without overwriting it', () async {
    const keptMarker = '합성본문-그대로-9c2e';
    const movedMarker = '합성본문-내보낼-4b71';

    final parent = await testContext.createWorkspace();
    final kept = await _createDocument(parent.id, '그대로 둘 메모');
    final moved = await _createDocument(parent.id, '내보낼 메모');

    await _writeMarker(kept.id, keptMarker);
    await _writeMarker(moved.id, movedMarker);

    final beforeKept = await _plainText(kept.id);
    final beforeMoved = await _plainText(moved.id);
    expect(beforeKept, contains(keptMarker));
    expect(beforeMoved, contains(movedMarker));

    final bytes = await exportPersonalViews([moved]);
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes), isNot(contains(keptMarker)));

    final existing = await ViewBackendService.getAllViews();
    final existingIds = existing.fold(
      (value) => value.items.map((view) => view.id).toSet(),
      (error) => throw Exception(error),
    );
    expect(existingIds, containsAll([kept.id, moved.id]));

    final plan = DocumentBundle.importBundle(
      Uint8List.fromList(bytes),
      existingIds: Set<String>.of(existingIds),
    );
    expect(plan.documents, hasLength(1));
    final imported = plan.documents.single;
    expect(imported.newId, isNot(moved.id));
    expect(imported.newId, isNot(kept.id));
    expect(existingIds, isNot(contains(imported.newId)));
    expect(imported.title, '내보낼 메모');
    expect(_nodesText(imported.nodes), contains(movedMarker));
    expect(plan.notes, isNotEmpty);

    final created = await commitPersonalImport(
      plan: plan,
      workspaceId: parent.id,
    );
    expect(created, hasLength(1));
    final createdId = created.single;
    expect(existingIds, isNot(contains(createdId)));
    expect(createdId, isNot(moved.id));
    expect(createdId, isNot(kept.id));

    final after = await ViewBackendService.getAllViews();
    final views = after.fold(
      (value) => value.items,
      (error) => throw Exception(error),
    );
    final ids = views.map((view) => view.id).toSet();
    expect(ids, containsAll([kept.id, moved.id, createdId]));
    expect(views.where((view) => view.id == moved.id).single.name, '내보낼 메모');
    expect(views.where((view) => view.id == kept.id).single.name, '그대로 둘 메모');

    expect(await _plainText(kept.id), beforeKept);
    expect(await _plainText(moved.id), beforeMoved);
    expect(await _plainText(createdId), contains(movedMarker));
    expect(await _plainText(createdId), isNot(contains(keptMarker)));
  });
}

Future<ViewPB> _createDocument(String parentId, String name) async {
  final result = await ViewBackendService.createView(
    layoutType: ViewLayoutPB.Document,
    parentViewId: parentId,
    name: name,
    section: ViewSectionPB.Public,
  );
  return result.fold((view) => view, (error) => throw Exception(error));
}

Future<void> _writeMarker(String documentId, String marker) async {
  final bloc = DocumentBloc(documentId: documentId)
    ..add(const DocumentEvent.initial());
  try {
    final state = await bloc.stream
        .firstWhere((next) => !next.isLoading)
        .timeout(const Duration(seconds: 20));
    final editor = state.editorState;
    expect(editor, isNotNull, reason: 'document $documentId did not open');
    final opened = editor!;
    final node = opened.document.root.children.isEmpty
        ? null
        : opened.document.root.children.first;
    if (node == null) {
      final transaction = opened.transaction;
      transaction.insertNode([0], paragraphNode(text: marker));
      await opened.apply(transaction);
    } else {
      await opened.insertText(0, marker, node: node);
    }
    await _waitForText(documentId, marker);
  } finally {
    await bloc.close();
  }
}

Future<void> _waitForText(String documentId, String marker) async {
  for (var attempt = 0; attempt < 25; attempt++) {
    final text = await _plainText(documentId);
    if (text.contains(marker)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('document $documentId did not persist "$marker"');
}

Future<String> _plainText(String documentId) async {
  final opened = await DocumentService().getDocument(documentId: documentId);
  return opened.fold(
    (data) {
      final document = data.toDocument();
      if (document == null) {
        return '';
      }
      return _walk(document.root);
    },
    (error) => throw Exception(error),
  );
}

String _walk(Node node) {
  final buffer = StringBuffer();
  final delta = node.delta;
  if (delta != null) {
    buffer.write(delta.toPlainText());
  }
  for (final child in node.children) {
    buffer.write(_walk(child));
  }
  return buffer.toString();
}

String _nodesText(List<Map<String, Object?>> nodes) {
  final buffer = StringBuffer();
  void walk(Map<String, Object?> node) {
    final data = node['data'];
    if (data is Map) {
      final delta = data['delta'];
      if (delta is List) {
        for (final operation in delta) {
          if (operation is Map && operation['insert'] is String) {
            buffer.write(operation['insert']);
          }
        }
      }
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map) {
          walk(Map<String, Object?>.from(child));
        }
      }
    }
  }

  for (final node in nodes) {
    walk(node);
  }
  return buffer.toString();
}
