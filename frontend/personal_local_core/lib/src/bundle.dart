import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class BundleException implements Exception {
  BundleException(this.code, this.messageKo);

  final String code;
  final String messageKo;

  @override
  String toString() => '$code: $messageKo';
}

class BundleLimits {
  const BundleLimits._();

  static const maxEntries = 256;
  static const maxCompressedBytes = 32 * 1024 * 1024;
  static const maxUncompressedBytes = 64 * 1024 * 1024;
  static const maxSingleFile = 16 * 1024 * 1024;
  static const maxRatio = 100;
}

class ExchangeAttachment {
  const ExchangeAttachment({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

class ExchangeDocument {
  const ExchangeDocument({
    required this.sourceId,
    required this.title,
    required this.nodes,
    this.parentSourceId,
    this.attachments = const [],
    this.encryptedEnvelope,
    this.unsupportedNotes = const [],
  });

  final String sourceId;
  final String title;
  final String? parentSourceId;

  /// Rich-text node tree. Ignored when [encryptedEnvelope] is set.
  final List<Map<String, Object?>> nodes;
  final List<ExchangeAttachment> attachments;
  final Uint8List? encryptedEnvelope;
  final List<String> unsupportedNotes;

  bool get isEncrypted => encryptedEnvelope != null;
}

class ImportedDocument {
  const ImportedDocument({
    required this.newId,
    required this.title,
    required this.nodes,
    this.parentNewId,
    this.attachments = const [],
    this.encryptedEnvelope,
    this.notes = const [],
  });

  final String newId;
  final String title;
  final String? parentNewId;
  final List<Map<String, Object?>> nodes;
  final List<ExchangeAttachment> attachments;
  final Uint8List? encryptedEnvelope;
  final List<String> notes;

  bool get isEncrypted => encryptedEnvelope != null;
}

class ImportPlan {
  const ImportPlan({
    required this.documents,
    required this.notes,
    required this.encryption,
  });

  final List<ImportedDocument> documents;
  final List<String> notes;

  /// `none` means anyone who has the file can read it.
  final String encryption;
}

class ExportRequest {
  const ExportRequest({
    required this.documents,
    this.allowPlaintextOfLocked = false,
    this.lockedIds = const {},
  });

  final List<ExchangeDocument> documents;
  final bool allowPlaintextOfLocked;
  final Set<String> lockedIds;
}

const bundleFormat = 'appflowy-personal-document-bundle';
const bundleFormatVersion = 1;

const _forbiddenExtensions = <String>{
  '.exe',
  '.bat',
  '.cmd',
  '.ps1',
  '.dll',
  '.scr',
  '.com',
  '.msi',
  '.vbs',
  '.hta',
  '.js',
  '.jar',
  '.sh',
  '.app',
};

class DocumentBundle {
  const DocumentBundle._();

  static Uint8List exportBundle(
    ExportRequest request, {
    DateTime? exportedAt,
    String Function(int index)? idForPath,
  }) {
    final archive = Archive();
    final manifestDocs = <Map<String, Object?>>[];
    final notes = <String>[
      '암호화하지 않은 문서는 파일을 가진 사람이 읽을 수 있습니다. 이 묶음은 전송하지 않으며, 받는 사람에게 파일을 직접 전달해야 합니다.',
    ];
    var index = 0;
    for (final document in request.documents) {
      if (request.lockedIds.contains(document.sourceId) &&
          document.encryptedEnvelope == null &&
          !request.allowPlaintextOfLocked) {
        throw BundleException(
          'locked_plaintext',
          '잠긴 메모는 암호문을 그대로 내보내야 합니다. 평문 내보내기는 확인 후에만 가능합니다.',
        );
      }
      final docKey = idForPath?.call(index) ?? 'doc-$index';
      index++;
      final entry = <String, Object?>{
        'sourceId': document.sourceId,
        'title': document.isEncrypted ? '잠긴 메모' : document.title,
        'parentSourceId': document.parentSourceId,
        'protection': document.isEncrypted ? 'aes-gcm-v1' : 'none',
      };
      if (document.isEncrypted) {
        final path = 'protected/$docKey.afpl';
        _addBytes(archive, path, document.encryptedEnvelope!);
        entry['envelopePath'] = path;
        entry['titleVisible'] = false;
      } else {
        final path = 'documents/$docKey.json';
        final sanitized = _sanitizeNodes(document.nodes);
        notes.addAll(sanitized.notes);
        notes.addAll(document.unsupportedNotes);
        _addBytes(
          archive,
          path,
          Uint8List.fromList(
            utf8.encode(jsonEncode({'nodes': sanitized.nodes})),
          ),
        );
        entry['documentPath'] = path;
        entry['titleVisible'] = true;
        final attachments = <Map<String, String>>[];
        for (final attachment in document.attachments) {
          final safe = _safeRelative(attachment.name);
          _rejectExecutable(safe);
          final path = 'attachments/$docKey/$safe';
          _addBytes(archive, path, attachment.bytes);
          attachments.add({'path': path, 'name': safe});
        }
        entry['attachments'] = attachments;
      }
      manifestDocs.add(entry);
    }

    final manifest = <String, Object?>{
      'format': bundleFormat,
      'formatVersion': bundleFormatVersion,
      'exportedAt':
          (exportedAt ?? DateTime.utc(2026, 11, 11)).toIso8601String(),
      'encryption': 'none',
      'readableByFileHolder': true,
      'notes': notes.toSet().toList(),
      'documents': manifestDocs,
    };
    _addBytes(
      archive,
      'manifest.json',
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    );
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw BundleException('encode', '묶음을 만들지 못했습니다.');
    }
    return Uint8List.fromList(encoded);
  }

  static ImportPlan importBundle(
    Uint8List bytes, {
    required Set<String> existingIds,
    String Function()? newId,
  }) {
    _preflight(bytes);
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.files.length > BundleLimits.maxEntries) {
      throw BundleException('too_many', '묶음의 항목이 너무 많습니다.');
    }
    final files = <String, Uint8List>{};
    var total = 0;
    for (final file in archive.files) {
      if (file.isSymbolicLink || (file.mode & 0xF000) == 0xA000) {
        throw BundleException('symlink', '심볼릭 링크는 가져올 수 없습니다.');
      }
      final name = _safeZipName(file.name);
      if (!file.isFile) {
        continue;
      }
      final content = file.content;
      final data = Uint8List.fromList(content);
      if (data.length > BundleLimits.maxSingleFile) {
        throw BundleException('too_large', '파일이 너무 큽니다.');
      }
      total += data.length;
      if (total > BundleLimits.maxUncompressedBytes) {
        throw BundleException('too_large', '묶음이 너무 큽니다.');
      }
      _rejectExecutable(name);
      if (files.containsKey(name)) {
        throw BundleException('duplicate', '중복된 경로가 있습니다.');
      }
      files[name] = data;
    }

    final manifestBytes = files['manifest.json'];
    if (manifestBytes == null) {
      throw BundleException('manifest', 'manifest.json이 없습니다.');
    }
    final manifest = jsonDecode(utf8.decode(manifestBytes));
    if (manifest is! Map ||
        manifest['format'] != bundleFormat ||
        manifest['formatVersion'] != bundleFormatVersion) {
      throw BundleException('schema', '지원하지 않는 묶음 형식입니다.');
    }
    final rawDocs = manifest['documents'];
    if (rawDocs is! List) {
      throw BundleException('schema', '문서 목록이 없습니다.');
    }

    var sequence = 0;
    String mint() {
      for (var attempt = 0; attempt < 10000; attempt++) {
        final id = newId?.call() ?? 'imported-${sequence++}';
        if (!existingIds.contains(id)) {
          existingIds.add(id);
          return id;
        }
      }
      throw BundleException('id', '새 문서 아이디를 만들지 못했습니다.');
    }

    final idMap = <String, String>{};
    final pending = <Map<String, Object?>>[];
    final notes = <String>[
      '가져온 문서는 새 ID로 만들어지며 기존 메모를 덮어쓰지 않습니다.',
    ];
    if (manifest['encryption'] == 'none') {
      notes.add('이 파일은 암호화되어 있지 않습니다. 파일을 가진 사람이 읽을 수 있습니다.');
    }
    for (final raw in rawDocs) {
      if (raw is! Map) {
        throw BundleException('schema', '문서 항목이 잘못되었습니다.');
      }
      final sourceId = raw['sourceId'];
      if (sourceId is! String || sourceId.isEmpty) {
        throw BundleException('schema', '문서 ID가 없습니다.');
      }
      idMap[sourceId] = mint();
      pending.add(Map<String, Object?>.from(raw));
    }

    final imported = <ImportedDocument>[];
    for (final raw in pending) {
      final sourceId = raw['sourceId']! as String;
      final newDocumentId = idMap[sourceId]!;
      final parent = raw['parentSourceId'];
      final parentNewId = parent is String ? idMap[parent] : null;
      if (parent is String && parentNewId == null) {
        notes.add('상위 문서를 찾지 못해 "$sourceId" 문서를 최상위로 가져왔습니다.');
      }
      if (raw['protection'] == 'aes-gcm-v1') {
        final path = raw['envelopePath'];
        if (path is! String) {
          throw BundleException('schema', '암호문 경로가 없습니다.');
        }
        final envelope = files[_safeZipName(path)];
        if (envelope == null) {
          throw BundleException('missing', '암호문 파일이 없습니다.');
        }
        imported.add(
          ImportedDocument(
            newId: newDocumentId,
            title: '잠긴 메모',
            parentNewId: parentNewId,
            nodes: const [],
            encryptedEnvelope: envelope,
            notes: const ['비밀번호 없이 본문을 열지 않았습니다. 보호 상태는 유지됩니다.'],
          ),
        );
        continue;
      }

      final path = raw['documentPath'];
      if (path is! String) {
        throw BundleException('schema', '문서 경로가 없습니다.');
      }
      final docBytes = files[_safeZipName(path)];
      if (docBytes == null) {
        throw BundleException('missing', '문서 파일이 없습니다.');
      }
      final decoded = jsonDecode(utf8.decode(docBytes));
      if (decoded is! Map || decoded['nodes'] is! List) {
        throw BundleException('schema', '문서 본문 형식이 잘못되었습니다.');
      }
      final nodes = <Map<String, Object?>>[];
      for (final node in decoded['nodes'] as List) {
        if (node is Map) {
          nodes.add(_rewriteNode(Map<String, Object?>.from(node), mint));
        }
      }
      final attachments = <ExchangeAttachment>[];
      final listed = raw['attachments'];
      if (listed is List) {
        for (final item in listed) {
          if (item is! Map) {
            continue;
          }
          final itemPath = item['path'];
          final itemName = item['name'];
          if (itemPath is! String || itemName is! String) {
            continue;
          }
          final data = files[_safeZipName(itemPath)];
          if (data == null) {
            notes.add('첨부 $itemName 을(를) 찾지 못했습니다.');
            continue;
          }
          attachments.add(
            ExchangeAttachment(name: _safeRelative(itemName), bytes: data),
          );
        }
      }
      imported.add(
        ImportedDocument(
          newId: newDocumentId,
          title: (raw['title'] as String?) ?? '가져온 메모',
          parentNewId: parentNewId,
          nodes: nodes,
          attachments: attachments,
        ),
      );
    }

    return ImportPlan(
      documents: imported,
      notes: notes,
      encryption: 'none',
    );
  }

  static void _preflight(Uint8List bytes) {
    if (bytes.length > BundleLimits.maxCompressedBytes) {
      throw BundleException('too_large', '묶음이 너무 큽니다.');
    }
    var offset = 0;
    var entries = 0;
    var totalUncompressed = 0;
    while (offset + 30 <= bytes.length) {
      final signature = _u32(bytes, offset);
      if (signature == 0x02014b50 || signature == 0x06054b50) {
        break;
      }
      if (signature != 0x04034b50) {
        throw BundleException('corrupt', 'ZIP 형식이 아닙니다.');
      }
      final flags = _u16(bytes, offset + 6);
      final method = _u16(bytes, offset + 8);
      final compressed = _u32(bytes, offset + 18);
      final uncompressed = _u32(bytes, offset + 22);
      final nameLength = _u16(bytes, offset + 26);
      final extraLength = _u16(bytes, offset + 28);
      if (offset + 30 + nameLength + extraLength > bytes.length) {
        throw BundleException('corrupt', 'ZIP 헤더가 손상되었습니다.');
      }
      final name = utf8.decode(
        bytes.sublist(offset + 30, offset + 30 + nameLength),
        allowMalformed: false,
      );
      _safeZipName(name);
      if ((flags & 0x1) != 0) {
        throw BundleException('encrypted_zip', '암호가 걸린 ZIP은 지원하지 않습니다.');
      }
      if (method != 0 && method != 8) {
        throw BundleException('method', '지원하지 않는 압축 방식입니다.');
      }
      if (compressed == 0xFFFFFFFF || uncompressed == 0xFFFFFFFF) {
        throw BundleException('zip64', 'ZIP64는 지원하지 않습니다.');
      }
      if ((flags & 0x8) != 0 && uncompressed == 0) {
        throw BundleException(
          'data_descriptor',
          '크기를 미리 알 수 없는 항목은 거부합니다.',
        );
      }
      if (uncompressed > BundleLimits.maxSingleFile) {
        throw BundleException('too_large', '항목이 너무 큽니다.');
      }
      totalUncompressed += uncompressed;
      if (totalUncompressed > BundleLimits.maxUncompressedBytes) {
        throw BundleException('too_large', '압축을 푼 크기가 너무 큽니다.');
      }
      if (compressed > 0 &&
          uncompressed > compressed * BundleLimits.maxRatio &&
          uncompressed > 1024 * 1024) {
        throw BundleException('ratio', '압축률이 비정상입니다.');
      }
      entries++;
      if (entries > BundleLimits.maxEntries) {
        throw BundleException('too_many', '항목이 너무 많습니다.');
      }
      final dataStart = offset + 30 + nameLength + extraLength;
      if (dataStart + compressed > bytes.length) {
        throw BundleException('corrupt', 'ZIP 데이터가 잘렸습니다.');
      }
      offset = dataStart + compressed;
    }
    if (entries == 0) {
      throw BundleException('empty', '빈 묶음입니다.');
    }
  }

  static String _safeZipName(String name) {
    final normalized = name.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('\u0000') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw BundleException('path', '허용되지 않는 경로입니다.');
    }
    for (final part in normalized.split('/')) {
      if (part == '..' || part == '.') {
        throw BundleException('path', '경로 탈출은 거부합니다.');
      }
    }
    const allowedPrefix = [
      'manifest.json',
      'documents/',
      'attachments/',
      'protected/',
    ];
    final ok = allowedPrefix.any(normalized.startsWith) ||
        normalized == 'manifest.json';
    if (!ok) {
      throw BundleException('path', '허용되지 않는 묶음 경로입니다.');
    }
    return normalized;
  }

  static String _safeRelative(String name) {
    final base = name.split(RegExp(r'[\\/]')).last;
    if (base.isEmpty ||
        base == '.' ||
        base == '..' ||
        base.contains('\u0000')) {
      throw BundleException('path', '첨부 이름이 잘못되었습니다.');
    }
    return base;
  }

  static void _rejectExecutable(String name) {
    final lower = name.toLowerCase();
    for (final extension in _forbiddenExtensions) {
      if (lower.endsWith(extension)) {
        throw BundleException(
          'executable',
          '실행 파일은 가져오거나 넣지 않습니다. 자동 실행하지 않습니다.',
        );
      }
    }
  }

  static void _addBytes(Archive archive, String name, Uint8List bytes) {
    _safeZipName(name);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static ({List<Map<String, Object?>> nodes, List<String> notes})
      _sanitizeNodes(
    List<Map<String, Object?>> nodes,
  ) {
    final notes = <String>[];
    final sanitized = nodes.map((node) => _sanitizeNode(node, notes)).toList();
    return (nodes: sanitized, notes: notes);
  }

  static Map<String, Object?> _sanitizeNode(
    Map<String, Object?> node,
    List<String> notes,
  ) {
    final copy = <String, Object?>{};
    node.forEach((key, value) {
      copy[key] = _sanitizeValue(key, value, notes);
    });
    return copy;
  }

  static Object? _sanitizeValue(String key, Object? value, List<String> notes) {
    if (value is Map) {
      return _sanitizeNode(Map<String, Object?>.from(value), notes);
    }
    if (value is List) {
      return value.map((item) => _sanitizeValue(key, item, notes)).toList();
    }
    if (value is String && (key == 'url' || key == 'src' || key == 'href')) {
      final lower = value.toLowerCase();
      if (lower.startsWith('http://') ||
          lower.startsWith('https://') ||
          lower.startsWith('file:')) {
        notes.add('원격 또는 file 주소는 가져오지 않고 제거했습니다.');
        return '';
      }
      if (value.startsWith('/') ||
          value.contains('..') ||
          value.contains(':\\')) {
        notes.add('절대 경로와 상위 폴더 경로는 묶음에 넣지 않았습니다.');
        return value.split(RegExp(r'[\\/]')).last;
      }
    }
    return value;
  }

  static Map<String, Object?> _rewriteNode(
    Map<String, Object?> node,
    String Function() mint,
  ) {
    final copy = Map<String, Object?>.from(node);
    if (copy.containsKey('id')) {
      copy['id'] = mint();
    }
    final children = copy['children'];
    if (children is List) {
      copy['children'] = children
          .whereType<Map>()
          .map((child) => _rewriteNode(Map<String, Object?>.from(child), mint))
          .toList();
    }
    return copy;
  }
}

int _u16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
