import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:personal_local_core/personal_local_core.dart';
import 'package:personal_local_ui/personal_local_ui.dart';

Future<void> showPersonalDocumentExchange(
  BuildContext context, {
  required String workspaceId,
}) async {
  final views = await ViewBackendService.getAllViews();
  final documents = views.fold(
    (value) => value.items
        .where((view) => view.layout == ViewLayoutPB.Document)
        .toList(),
    (_) => <ViewPB>[],
  );
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ExchangeDialog(
      documents: documents,
      workspaceId: workspaceId,
    ),
  );
}

class _ExchangeDialog extends StatefulWidget {
  const _ExchangeDialog({
    required this.documents,
    required this.workspaceId,
  });

  final List<ViewPB> documents;
  final String workspaceId;

  @override
  State<_ExchangeDialog> createState() => _ExchangeDialogState();
}

class _ExchangeDialogState extends State<_ExchangeDialog> {
  final _selected = <String>{};
  String? _message;
  ImportPlan? _preview;
  Uint8List? _pendingImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: SizedBox(
        width: 560,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('문서 내보내기 / 문서 가져오기', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                '파일을 직접 전달하는 방식입니다. 앱이 메시지를 보내거나 업로드하지 않습니다. '
                '암호화하지 않은 문서는 파일을 가진 사람이 읽을 수 있습니다.',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final view in widget.documents)
                      CheckboxListTile(
                        value: _selected.contains(view.id),
                        title: Text(view.name.isEmpty ? '제목 없음' : view.name),
                        onChanged: (checked) {
                          setState(() {
                            if (checked ?? false) {
                              _selected.add(view.id);
                            } else {
                              _selected.remove(view.id);
                            }
                          });
                        },
                      ),
                    if (_preview != null)
                      ExchangePreview(
                        titles: _preview!.documents
                            .map((doc) => doc.title)
                            .toList(),
                        encryptedCount: _preview!.documents
                            .where((doc) => doc.isEncrypted)
                            .length,
                        notes: _preview!.notes,
                      ),
                  ],
                ),
              ),
              if (_message != null) Text(_message!),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _export,
                    child: const Text('문서 내보내기'),
                  ),
                  OutlinedButton(
                    onPressed: _pickImport,
                    child: const Text('문서 가져오기'),
                  ),
                  if (_pendingImport != null)
                    FilledButton(
                      onPressed: _commitImport,
                      child: const Text('새 문서로 추가'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    if (_selected.isEmpty) {
      setState(() => _message = '내보낼 메모를 선택하세요.');
      return;
    }
    final chosen =
        widget.documents.where((view) => _selected.contains(view.id));
    final exchangeDocs = <ExchangeDocument>[];
    for (final view in chosen) {
      exchangeDocs.add(await _readDocument(view));
    }
    final bytes = DocumentBundle.exportBundle(
      ExportRequest(documents: exchangeDocs),
    );
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '문서 내보내기',
      fileName: 'appflowy-documents.afbundle.zip',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (path == null) {
      return;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    if (!mounted) {
      return;
    }
    setState(() => _message = '파일을 저장했습니다. 앱이 전송하지는 않습니다.');
  }

  Future<void> _pickImport() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '문서 가져오기',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) {
      return;
    }
    try {
      final plan = DocumentBundle.importBundle(
        Uint8List.fromList(bytes),
        existingIds: widget.documents.map((view) => view.id).toSet(),
      );
      setState(() {
        _preview = plan;
        _pendingImport = Uint8List.fromList(bytes);
        _message = null;
      });
    } on BundleException catch (error) {
      setState(() {
        _preview = null;
        _pendingImport = null;
        _message = error.messageKo;
      });
    }
  }

  Future<void> _commitImport() async {
    final plan = _preview;
    if (plan == null) {
      return;
    }
    final created = <String>[];
    try {
      final root = await getIt<ApplicationDataStorage>().getPath();
      for (final document in plan.documents) {
        if (document.isEncrypted) {
          final directory = Directory(
            path.join(root, 'personal_local_protected', document.newId),
          );
          await directory.create(recursive: true);
          final file = File(path.join(directory.path, 'note.afpl'));
          await file.writeAsBytes(document.encryptedEnvelope!, flush: true);
          final explanation = paragraphNode(
            text:
                '이 메모의 본문은 암호화된 파일로만 보관됩니다. 이 버전은 협업 저장소의 평문을 지울 수 없어 잠긴 본문을 열지 않습니다.',
          );
          final page = pageNode(children: [explanation]);
          explanation.parent = page;
          final placeholder = Document(root: page);
          final initial =
              DocumentDataPBFromTo.fromDocument(placeholder)?.writeToBuffer();
          final view = await ViewBackendService.createView(
            layoutType: ViewLayoutPB.Document,
            parentViewId: widget.workspaceId,
            name: '잠긴 메모',
            initialDataBytes: initial,
            section: ViewSectionPB.Public,
          );
          final createdView =
              view.fold((value) => value, (error) => throw error);
          created.add(createdView.id);
          continue;
        }
        final nodes = await _materializeAttachments(
          document: document,
          storageRoot: root,
        );
        final editorDocument = _documentFromNodes(nodes);
        final initial =
            DocumentDataPBFromTo.fromDocument(editorDocument)?.writeToBuffer();
        final view = await ViewBackendService.createView(
          layoutType: ViewLayoutPB.Document,
          parentViewId: widget.workspaceId,
          name: document.title,
          initialDataBytes: initial,
          section: ViewSectionPB.Public,
        );
        final createdView = view.fold((value) => value, (error) => throw error);
        created.add(createdView.id);
      }
      if (!mounted) {
        return;
      }
      setState(() => _message = '새 문서 ${created.length}개를 추가했습니다.');
      _pendingImport = null;
    } catch (error) {
      for (final id in created) {
        await ViewBackendService.deleteView(viewId: id);
      }
      if (!mounted) {
        return;
      }
      setState(
        () => _message = '가져오기에 실패했습니다. 새로 만들다 만 문서는 지웠고, 기존 메모는 그대로입니다.',
      );
    }
  }
}

Future<ExchangeDocument> _readDocument(ViewPB view) async {
  final opened = await DocumentService().getDocument(documentId: view.id);
  final nodes = opened.fold(
    (data) {
      final document = data.toDocument();
      if (document == null) {
        return const <Map<String, Object?>>[];
      }
      return document.root.children.map(_nodeToMap).toList();
    },
    (_) => const <Map<String, Object?>>[],
  );
  return ExchangeDocument(
    sourceId: view.id,
    title: view.name,
    nodes: nodes,
  );
}

Map<String, Object?> _nodeToMap(Node node) {
  return {
    'type': node.type,
    'data': node.attributes,
    'children': node.children.map(_nodeToMap).toList(),
  };
}

Document _documentFromNodes(List<Map<String, Object?>> nodes) {
  final children = nodes.map(_nodeFromMap).toList();
  if (children.isEmpty) {
    children.add(paragraphNode(text: ''));
  }
  final page = pageNode(children: children);
  for (final child in page.children) {
    child.parent = page;
  }
  return Document(root: page);
}

Node _nodeFromMap(Map<String, Object?> json) {
  final rawChildren = json['children'];
  final children = <Node>[];
  if (rawChildren is List) {
    for (final child in rawChildren) {
      if (child is Map) {
        children.add(_nodeFromMap(Map<String, Object?>.from(child)));
      }
    }
  }
  final data = json['data'];
  final node = Node(
    type: json['type'] as String? ?? ParagraphBlockKeys.type,
    attributes:
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    children: children,
  );
  for (final child in children) {
    child.parent = node;
  }
  return node;
}

Future<List<Map<String, Object?>>> _materializeAttachments({
  required ImportedDocument document,
  required String storageRoot,
}) async {
  final directory = Directory(
    path.join(storageRoot, 'personal_local_imports', document.newId),
  );
  final resolvedRoot = directory.absolute.path;
  await directory.create(recursive: true);
  final byName = <String, String>{};
  for (final attachment in document.attachments) {
    final safeName = path.basename(attachment.name);
    final file = File(path.join(resolvedRoot, safeName));
    if (!path.isWithin(resolvedRoot, file.path) &&
        file.path != path.join(resolvedRoot, safeName)) {
      continue;
    }
    await file.writeAsBytes(attachment.bytes, flush: true);
    byName[safeName] = file.path;
  }
  return document.nodes.map((node) => _rewriteUrls(node, byName)).toList();
}

Map<String, Object?> _rewriteUrls(
  Map<String, Object?> node,
  Map<String, String> byName,
) {
  final copy = <String, Object?>{};
  node.forEach((key, value) {
    if (value is Map) {
      copy[key] = _rewriteUrls(Map<String, Object?>.from(value), byName);
    } else if (value is List) {
      copy[key] = value
          .map(
            (item) => item is Map
                ? _rewriteUrls(Map<String, Object?>.from(item), byName)
                : item,
          )
          .toList();
    } else if ((key == 'url' || key == 'src') && value is String) {
      copy[key] = byName[path.basename(value)] ?? '';
    } else {
      copy[key] = value;
    }
  });
  return copy;
}
