import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:personal_local_core/personal_local_core.dart';
import 'package:test/test.dart';

void main() {
  ExchangeDocument koreanDoc(String id) {
    return ExchangeDocument(
      sourceId: id,
      title: '한글 제목',
      nodes: [
        {
          'id': 'n1',
          'type': 'paragraph',
          'data': {
            'delta': [
              {
                'insert': '굵은 ',
                'attributes': {'bold': true},
              },
              {'insert': '김치'},
            ],
          },
          'children': [],
        },
      ],
      attachments: [
        ExchangeAttachment(
          name: '사진.png',
          bytes: Uint8List.fromList(const [1, 2, 3, 4]),
        ),
      ],
    );
  }

  test('roundtrip keeps korean rich text and attachment with new ids', () {
    final bytes = DocumentBundle.exportBundle(
      ExportRequest(documents: [koreanDoc('old-1'), koreanDoc('old-2')]),
    );
    final plan = DocumentBundle.importBundle(
      bytes,
      existingIds: {'old-1', 'old-2', 'kept'},
    );
    expect(plan.documents, hasLength(2));
    expect(plan.documents.map((doc) => doc.newId).toSet(), hasLength(2));
    expect(plan.documents.every((doc) => doc.newId != 'old-1'), isTrue);
    expect(plan.documents.every((doc) => doc.newId != 'kept'), isTrue);
    final node = plan.documents.first.nodes.single;
    final delta = (node['data']! as Map)['delta'] as List;
    expect(delta.first['attributes']['bold'], true);
    expect((delta.last['insert'] as String), '김치');
    expect(node['id'], isNot('n1'));
    expect(plan.documents.first.attachments.single.bytes, [1, 2, 3, 4]);
    expect(plan.encryption, 'none');
    expect(plan.notes.join('\n'), contains('암호화되어 있지 않습니다'));
  });

  test('parent links remap and missing parent does not overwrite', () {
    final bytes = DocumentBundle.exportBundle(
      ExportRequest(
        documents: [
          ExchangeDocument(sourceId: 'parent', title: '부모', nodes: const []),
          ExchangeDocument(
            sourceId: 'child',
            title: '자식',
            parentSourceId: 'parent',
            nodes: const [],
          ),
          ExchangeDocument(
            sourceId: 'orphan',
            title: '고아',
            parentSourceId: 'missing',
            nodes: const [],
          ),
        ],
      ),
    );
    final existing = <String, String>{'kept': '그대로'};
    final plan = DocumentBundle.importBundle(bytes, existingIds: {'kept'});
    final byTitle = {for (final doc in plan.documents) doc.title: doc};
    expect(byTitle['자식']!.parentNewId, byTitle['부모']!.newId);
    expect(byTitle['고아']!.parentNewId, isNull);
    expect(existing['kept'], '그대로');
  });

  test('zip slip, symlink, executable, and oversize are rejected', () {
    Uint8List zipWith(void Function(Archive archive) build) {
      final archive = Archive();
      build(archive);
      return Uint8List.fromList(ZipEncoder().encode(archive)!);
    }

    expect(
      () => DocumentBundle.importBundle(
        zipWith((archive) {
          final data = utf8.encode('x');
          archive.addFile(ArchiveFile('../secret.txt', data.length, data));
        }),
        existingIds: {},
      ),
      throwsA(isA<BundleException>()),
    );

    expect(
      () => DocumentBundle.importBundle(
        zipWith((archive) {
          final link = ArchiveFile('documents/link', 1, [120]);
          link.mode = 0xA1FF;
          archive.addFile(link);
        }),
        existingIds: {},
      ),
      throwsA(isA<BundleException>()),
    );

    expect(
      () => DocumentBundle.importBundle(
        zipWith((archive) {
          final data = utf8.encode('MZ');
          archive.addFile(ArchiveFile('documents/run.exe', data.length, data));
        }),
        existingIds: {},
      ),
      throwsA(isA<BundleException>()),
    );

    final huge = Uint8List(BundleLimits.maxCompressedBytes + 1);
    expect(
      () => DocumentBundle.importBundle(huge, existingIds: {}),
      throwsA(
        predicate(
            (error) => error is BundleException && error.code == 'too_large'),
      ),
    );
  });

  test('declared zip bomb ratio is rejected before decode', () {
    final bytes = Uint8List(64);
    void u16(int offset, int value) {
      bytes[offset] = value & 0xff;
      bytes[offset + 1] = (value >> 8) & 0xff;
    }

    void u32(int offset, int value) {
      bytes[offset] = value & 0xff;
      bytes[offset + 1] = (value >> 8) & 0xff;
      bytes[offset + 2] = (value >> 16) & 0xff;
      bytes[offset + 3] = (value >> 24) & 0xff;
    }

    u32(0, 0x04034b50);
    u16(8, 8);
    u32(18, 1);
    u32(22, 8 * 1024 * 1024);
    u16(26, 13);
    final name = utf8.encode('manifest.json');
    bytes.setRange(30, 43, name);
    expect(
      () => DocumentBundle.importBundle(bytes, existingIds: {}),
      throwsA(
        predicate(
          (error) =>
              error is BundleException &&
              (error.code == 'ratio' || error.code == 'corrupt'),
        ),
      ),
    );
  });

  test('remote urls are stripped and not fetched', () {
    final bytes = DocumentBundle.exportBundle(
      ExportRequest(
        documents: [
          ExchangeDocument(
            sourceId: 'd',
            title: '링크',
            nodes: [
              {
                'type': 'image',
                'data': {'url': 'https://example.test/secret.png'},
              },
            ],
          ),
        ],
      ),
    );
    final plan = DocumentBundle.importBundle(bytes, existingIds: {});
    expect((plan.documents.single.nodes.single['data']! as Map)['url'], '');
    expect(plan.notes.join(), isNot(contains('example.test')));
  });

  test('locked export without confirmation is refused', () {
    expect(
      () => DocumentBundle.exportBundle(
        ExportRequest(
          documents: [
            const ExchangeDocument(sourceId: 's', title: '비밀', nodes: []),
          ],
          lockedIds: {'s'},
        ),
      ),
      throwsA(isA<BundleException>()),
    );
  });

  test('id minting stops instead of looping when every id is taken', () {
    final bytes = DocumentBundle.exportBundle(
      ExportRequest(documents: [koreanDoc('old')]),
    );
    expect(
      () => DocumentBundle.importBundle(
        bytes,
        existingIds: {'always-taken'},
        newId: () => 'always-taken',
      ),
      throwsA(isA<BundleException>()),
    );
  });
}
