import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:personal_local_core/personal_local_core.dart';
import 'package:personal_local_ui/personal_local_ui.dart';

/// Reads document text from the local collab database. Locked ids are not read.
Future<List<SearchDocument>> loadOfflineSearchDocuments({
  Set<String> excludedDocumentIds = const {},
}) async {
  final views = await ViewBackendService.getAllViews();
  final items = views.fold((value) => value.items, (_) => <ViewPB>[]);
  final documents = <SearchDocument>[];
  final service = DocumentService();
  for (final view in items) {
    if (view.layout != ViewLayoutPB.Document) {
      continue;
    }
    if (excludedDocumentIds.contains(view.id)) {
      continue;
    }
    final opened = await service.getDocument(documentId: view.id);
    final blocks = opened.fold(
      (data) => _blocksFromDocument(data.toDocument()),
      (_) => const <SearchBlock>[],
    );
    documents.add(
      SearchDocument(id: view.id, title: view.name, blocks: blocks),
    );
  }
  return documents;
}

List<SearchBlock> _blocksFromDocument(Document? document) {
  final start = document?.root.children.firstOrNull;
  if (document == null || start == null) {
    return const [];
  }
  final blocks = <SearchBlock>[];
  final iterator = NodeIterator(document: document, startNode: start);
  while (iterator.moveNext()) {
    final text = iterator.current.delta?.toPlainText() ?? '';
    if (text.trim().isEmpty) {
      continue;
    }
    blocks.add(SearchBlock(id: iterator.current.id, text: text));
  }
  return blocks;
}

Future<void> showPersonalLocalSearch(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        child: SizedBox(
          width: 720,
          height: 560,
          child: OfflineSearchPanel(
            loadDocuments: loadOfflineSearchDocuments,
            onOpen: (hit) {
              Navigator.of(dialogContext).pop();
              hit.documentId.navigateTo();
              if (hit.blockId != null) {
                getIt<ActionNavigationBloc>().add(
                  ActionNavigationEvent.performAction(
                    action: NavigationAction(
                      objectId: hit.documentId,
                      type: ActionType.jumpToBlock,
                      arguments: {
                        ActionArgumentKeys.blockId: hit.blockId,
                      },
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
    },
  );
}
