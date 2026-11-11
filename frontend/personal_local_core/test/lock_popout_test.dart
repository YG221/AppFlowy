import 'dart:convert';
import 'dart:typed_data';

import 'package:personal_local_core/personal_local_core.dart';
import 'package:test/test.dart';

bool _containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) {
    return false;
  }
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return true;
    }
  }
  return false;
}

void main() {
  MemoSnapshot sample() {
    return MemoSnapshot(
      id: 'memo-1',
      title: '비밀 제목',
      body: '본문 김치찌개',
      nodes: const [
        {
          'type': 'paragraph',
          'data': {
            'delta': [
              {'insert': '본문 김치찌개'},
            ],
          },
        },
      ],
      attachments: [
        MemoAttachment(
            name: 'a.png', bytes: Uint8List.fromList(const [9, 8, 7])),
      ],
    );
  }

  Future<LockService> service({bool failPurge = false}) async {
    final snapshot = sample();
    final vault = MemoryVault({snapshot.id: snapshot})..index(snapshot);
    vault.failPurge = failPurge;
    return LockService(store: MemoryLockStore(), vault: vault);
  }

  test('wrong password, tamper, and unique salt and nonce', () async {
    final crypto = LockCrypto();
    final plain = Uint8List.fromList(utf8.encode('같은 본문'));
    final first =
        await crypto.encrypt(password: 'correct-horse', plaintext: plain);
    final second =
        await crypto.encrypt(password: 'correct-horse', plaintext: plain);
    expect(first.sublist(18, 34), isNot(second.sublist(18, 34)));
    expect(first.sublist(34, 46), isNot(second.sublist(34, 46)));
    expect(
        utf8.decode(
            await crypto.decrypt(password: 'correct-horse', envelope: first)),
        '같은 본문');
    expect(
      crypto.decrypt(password: 'wrong', envelope: first),
      throwsA(
          predicate((error) => error is LockException && error.code == 'auth')),
    );
    final tampered = Uint8List.fromList(first);
    tampered[tampered.length - 1] ^= 0x01;
    expect(
      crypto.decrypt(password: 'correct-horse', envelope: tampered),
      throwsA(isA<LockException>()),
    );
  });

  test('encrypt save reopen change and remove password', () async {
    final vault = MemoryVault({});
    final snapshot = sample();
    vault.notes[snapshot.id] = snapshot;
    vault.index(snapshot);
    final store = MemoryLockStore();
    final service = LockService(store: store, vault: vault);

    final locked = await service.lock(snapshot: snapshot, password: 'pw-1');
    expect(locked.locked, isTrue);
    expect(locked.record!.titleVisible, isFalse);
    expect(vault.notes[snapshot.id], isNull);
    expect(vault.searchIndex.containsKey(snapshot.id), isFalse);
    expect(
      _containsBytes(
          store.files[locked.record!.fileName]!, utf8.encode('김치찌개')),
      isFalse,
    );

    final wrong = await service.unlock(memoId: snapshot.id, password: 'nope');
    expect(wrong.opened, isFalse);

    final opened = await service.unlock(memoId: snapshot.id, password: 'pw-1');
    expect(opened.snapshot!.body, '본문 김치찌개');
    expect(opened.snapshot!.attachments.single.bytes, [9, 8, 7]);
    expect(vault.notes[snapshot.id], isNull);

    final changed = await service.changePassword(
      memoId: snapshot.id,
      oldPassword: 'pw-1',
      newPassword: 'pw-2',
    );
    expect(changed.locked, isTrue);
    expect((await service.unlock(memoId: snapshot.id, password: 'pw-1')).opened,
        isFalse);
    expect((await service.unlock(memoId: snapshot.id, password: 'pw-2')).opened,
        isTrue);

    final removed =
        await service.removePassword(memoId: snapshot.id, password: 'pw-2');
    expect(removed.locked, isFalse);
    expect(vault.notes[snapshot.id]!.title, '비밀 제목');
    expect(store.registry.containsKey(snapshot.id), isFalse);
  });

  test('failed purge keeps original plaintext and does not mark locked',
      () async {
    final vault = MemoryVault({});
    final snapshot = sample();
    vault.notes[snapshot.id] = snapshot;
    vault.index(snapshot);
    vault.failPurge = true;
    final store = MemoryLockStore();
    final service = LockService(store: store, vault: vault);
    final outcome = await service.lock(snapshot: snapshot, password: 'pw-1');
    expect(outcome.locked, isFalse);
    expect(vault.notes[snapshot.id]!.body, '본문 김치찌개');
    expect(vault.searchIndex[snapshot.id], contains('김치찌개'));
    expect(store.registry.containsKey(snapshot.id), isFalse);
    expect(
        store.files.values.where(
            (bytes) => utf8.decode(bytes, allowMalformed: true).contains('김치')),
        isEmpty);
  });

  test('appflowy storage blocker refuses a cosmetic lock', () async {
    final vault = MemoryVault({'memo-1': sample()});
    final service = LockService(store: MemoryLockStore(), vault: vault);
    final outcome = await service.lock(
      snapshot: sample(),
      password: 'pw-1',
      canPurgePlaintext: false,
    );
    expect(outcome.locked, isFalse);
    expect(outcome.messageKo, contains('비밀번호 창만'));
    expect(vault.notes['memo-1']!.body, contains('김치'));
    expect(
        StorageEncryptionBlocker.stores.map((store) => store.id),
        containsAll([
          'rocksdb_collab',
          'collab_snapshot',
          'tantivy',
          'historical_copies',
        ]));
  });

  test('crash before purge rolls back and keeps plaintext', () async {
    final snapshot = sample();
    final vault = MemoryVault({snapshot.id: snapshot});
    final store = MemoryLockStore();
    final service = LockService(store: store, vault: vault);
    final envelope = await service.crypto.encrypt(
      password: 'pw-1',
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(snapshot.toJson()))),
    );
    await store.writeFileAtomic('locks/${snapshot.id}.afpl', envelope);
    await store.writeRegistry(
      snapshot.id,
      LockRegistryRecord(
        memoId: snapshot.id,
        fileName: 'locks/${snapshot.id}.afpl',
        plaintextPurged: false,
        titleVisible: false,
      ),
    );
    await service.recover({snapshot.id});
    expect(store.registry.containsKey(snapshot.id), isFalse);
    expect(store.files.containsKey('locks/${snapshot.id}.afpl'), isFalse);
    expect(vault.notes[snapshot.id]!.body, '본문 김치찌개');
  });

  test('crash after purge keeps the ciphertext as the only copy', () async {
    final snapshot = sample();
    final vault = MemoryVault({snapshot.id: null});
    final store = MemoryLockStore();
    final service = LockService(store: store, vault: vault);
    final envelope = await service.crypto.encrypt(
      password: 'pw-1',
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(snapshot.toJson()))),
    );
    await store.writeFileAtomic('locks/${snapshot.id}.afpl', envelope);
    await store.writeRegistry(
      snapshot.id,
      LockRegistryRecord(
        memoId: snapshot.id,
        fileName: 'locks/${snapshot.id}.afpl',
        plaintextPurged: false,
        titleVisible: false,
      ),
    );
    await service.recover({snapshot.id});
    expect(store.registry[snapshot.id]!.plaintextPurged, isTrue);
    final opened = await service.unlock(memoId: snapshot.id, password: 'pw-1');
    expect(opened.snapshot!.body, '본문 김치찌개');
  });

  test('locked popout is obscured and closed when the memo locks', () async {
    final host = MemoryPopoutHost();
    final locked = <String>{};
    final controller = PopoutController(host: host, isLocked: locked.contains);
    final window = await controller.open(
      const PopoutRequest(documentId: 'memo-1', title: '제목', body: '보이는 본문'),
    );
    expect(window.request.body, '보이는 본문');
    expect(window.request.readOnly, isTrue);
    await controller.resize(window.id, const PopoutSize(100, 100));
    expect(window.size.width, PopoutSize.minimum.width);
    await controller.resize(window.id, const PopoutSize(800, 900));
    expect(window.size.width, 800);
    expect(host.sizes[window.id]!.height, 900);

    locked.add('memo-1');
    await controller.closeForDocument('memo-1');
    expect(window.closed, isTrue);
    final obscured = await controller.open(
      const PopoutRequest(documentId: 'memo-1', title: '제목', body: '보이는 본문'),
    );
    expect(obscured.request.body, isEmpty);
    expect(obscured.request.obscured, isTrue);
  });

  test('protected export and import keep ciphertext and new ids', () async {
    final crypto = LockCrypto();
    final envelope = await crypto.encrypt(
      password: 'pw-1',
      plaintext: Uint8List.fromList(utf8.encode('{"body":"비밀본문"}')),
    );
    final bytes = DocumentBundle.exportBundle(
      ExportRequest(
        documents: [
          ExchangeDocument(
            sourceId: 'old',
            title: '비밀 제목',
            nodes: const [],
            encryptedEnvelope: envelope,
          ),
        ],
        lockedIds: {'old'},
      ),
    );
    expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('비밀본문')));
    final plan = DocumentBundle.importBundle(bytes, existingIds: {'old'});
    expect(plan.documents.single.isEncrypted, isTrue);
    expect(plan.documents.single.newId, isNot('old'));
    expect(plan.documents.single.title, '잠긴 메모');
    final opened = await crypto.decrypt(
      password: 'pw-1',
      envelope: plan.documents.single.encryptedEnvelope!,
    );
    expect(utf8.decode(opened), contains('비밀본문'));
  });
}
