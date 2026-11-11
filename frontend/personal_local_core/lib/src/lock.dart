import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'storage_blocker.dart';

class LockException implements Exception {
  LockException(this.code, this.messageKo);

  final String code;
  final String messageKo;

  @override
  String toString() => messageKo;
}

class MemoAttachment {
  const MemoAttachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class MemoSnapshot {
  const MemoSnapshot({
    required this.id,
    required this.title,
    required this.body,
    required this.nodes,
    this.attachments = const [],
  });

  final String id;
  final String title;
  final String body;
  final List<Map<String, Object?>> nodes;
  final List<MemoAttachment> attachments;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'nodes': nodes,
        'attachments': [
          for (final attachment in attachments)
            {
              'name': attachment.name,
              'bytes': base64Encode(attachment.bytes),
            },
        ],
      };

  static MemoSnapshot fromJson(Map<String, Object?> json) {
    final attachments = <MemoAttachment>[];
    final raw = json['attachments'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          attachments.add(
            MemoAttachment(
              name: item['name'] as String? ?? 'file',
              bytes: Uint8List.fromList(base64Decode(item['bytes'] as String)),
            ),
          );
        }
      }
    }
    final nodes = <Map<String, Object?>>[];
    final rawNodes = json['nodes'];
    if (rawNodes is List) {
      for (final node in rawNodes) {
        if (node is Map) {
          nodes.add(Map<String, Object?>.from(node));
        }
      }
    }
    return MemoSnapshot(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      nodes: nodes,
      attachments: attachments,
    );
  }
}

class LockRegistryRecord {
  const LockRegistryRecord({
    required this.memoId,
    required this.fileName,
    required this.plaintextPurged,
    required this.titleVisible,
  });

  final String memoId;
  final String fileName;
  final bool plaintextPurged;
  final bool titleVisible;

  Map<String, Object?> toJson() => {
        'memoId': memoId,
        'fileName': fileName,
        'plaintextPurged': plaintextPurged,
        'titleVisible': titleVisible,
      };

  static LockRegistryRecord fromJson(Map<String, Object?> json) {
    return LockRegistryRecord(
      memoId: json['memoId']! as String,
      fileName: json['fileName']! as String,
      plaintextPurged: json['plaintextPurged'] == true,
      titleVisible: json['titleVisible'] == true,
    );
  }
}

class LockOutcome {
  const LockOutcome._({
    required this.locked,
    required this.messageKo,
    this.record,
  });

  const LockOutcome.locked(LockRegistryRecord record)
      : this._(
          locked: true,
          messageKo:
              '이 메모의 본문·제목·첨부를 암호화했습니다. 목록에는 "잠긴 메모"만 보입니다. 작업공간 전체 암호화는 아닙니다. 비밀번호를 잊으면 복구할 수 없습니다.',
          record: record,
        );

  const LockOutcome.refused(String messageKo)
      : this._(locked: false, messageKo: messageKo);

  final bool locked;
  final String messageKo;
  final LockRegistryRecord? record;
}

class UnlockOutcome {
  const UnlockOutcome.opened(this.snapshot)
      : opened = true,
        messageKo = '';

  const UnlockOutcome.failed(this.messageKo)
      : opened = false,
        snapshot = null;

  final bool opened;
  final String messageKo;
  final MemoSnapshot? snapshot;
}

/// AES-GCM-256 with Argon2id. Parameters are stored in the envelope.
class LockCrypto {
  LockCrypto({Random? random}) : _random = random ?? Random.secure();

  static const version = 1;
  static const memoryKiB = 19456;
  static const iterations = 2;
  static const parallelism = 1;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const headerLength = 46;

  final Random _random;
  final AesGcm _aes = AesGcm.with256bits();

  Future<Uint8List> encrypt({
    required String password,
    required Uint8List plaintext,
  }) async {
    if (password.isEmpty) {
      throw LockException('empty_password', '비밀번호가 비어 있습니다.');
    }
    final salt = _randomBytes(saltLength);
    final nonce = _randomBytes(nonceLength);
    final header = _header(salt: salt, nonce: nonce);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: await _key(password, salt, memoryKiB, iterations, parallelism),
      nonce: nonce,
      aad: header,
    );
    final out = BytesBuilder(copy: false)
      ..add(header)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    final envelope = out.toBytes();
    final roundtrip = await decrypt(password: password, envelope: envelope);
    if (!_bytesEqual(roundtrip, plaintext)) {
      throw LockException('roundtrip', '암호화 확인에 실패했습니다. 원본을 유지합니다.');
    }
    return envelope;
  }

  Future<Uint8List> decrypt({
    required String password,
    required Uint8List envelope,
  }) async {
    if (envelope.length < headerLength + 16) {
      throw LockException('format', '암호문 형식이 너무 짧습니다.');
    }
    if (utf8.decode(envelope.sublist(0, 4)) != 'AFPL' ||
        envelope[4] != version) {
      throw LockException('format', '지원하지 않는 암호문입니다.');
    }
    if (envelope[5] != 1) {
      throw LockException('format', '지원하지 않는 키 유도 함수입니다.');
    }
    final memory = _u32(envelope, 6);
    final iterations = _u32(envelope, 10);
    final parallelism = _u32(envelope, 14);
    if (memory < memoryKiB ||
        iterations < LockCrypto.iterations ||
        parallelism < 1) {
      throw LockException('weak_kdf', '너무 약한 키 유도 설정은 거부합니다.');
    }
    final salt = envelope.sublist(18, 34);
    final nonce = envelope.sublist(34, 46);
    final tag = envelope.sublist(envelope.length - 16);
    final cipherText = envelope.sublist(headerLength, envelope.length - 16);
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: await _key(password, salt, memory, iterations, parallelism),
        aad: envelope.sublist(0, headerLength),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw LockException(
        'auth',
        '비밀번호가 맞지 않거나 암호문이 손상되었습니다.',
      );
    }
  }

  Future<SecretKey> _key(
    String password,
    List<int> salt,
    int memory,
    int iterations,
    int parallelism,
  ) {
    final kdf = Argon2id(
      parallelism: parallelism,
      memory: memory,
      iterations: iterations,
      hashLength: 32,
    );
    return kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  Uint8List _header({required List<int> salt, required List<int> nonce}) {
    final header = Uint8List(headerLength);
    header.setRange(0, 4, utf8.encode('AFPL'));
    header[4] = version;
    header[5] = 1;
    _putU32(header, 6, memoryKiB);
    _putU32(header, 10, iterations);
    _putU32(header, 14, parallelism);
    header.setRange(18, 34, salt);
    header.setRange(34, 46, nonce);
    return header;
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }
}

abstract class LockStore {
  Future<void> writeFileAtomic(String name, Uint8List bytes);
  Future<Uint8List?> readFile(String name);
  Future<void> deleteFile(String name);
  Future<void> writeRegistry(String memoId, LockRegistryRecord? record);
  Future<LockRegistryRecord?> readRegistry(String memoId);
  Future<List<String>> listFiles();
}

abstract class PlaintextVault {
  Future<bool> plaintextStillPresent(String memoId);
  Future<void> purge(String memoId);
  Future<void> restore(MemoSnapshot snapshot);
}

class LockService {
  LockService({
    required this.store,
    required this.vault,
    LockCrypto? crypto,
  }) : crypto = crypto ?? LockCrypto();

  final LockStore store;
  final PlaintextVault vault;
  final LockCrypto crypto;
  final Map<String, MemoSnapshot> session = {};

  Future<LockOutcome> lock({
    required MemoSnapshot snapshot,
    required String password,
    bool canPurgePlaintext = true,
    String? refusalKo,
  }) async {
    if (!canPurgePlaintext) {
      return LockOutcome.refused(
        refusalKo ?? StorageEncryptionBlocker.summaryKo,
      );
    }
    final fileName = 'locks/${snapshot.id}.afpl';
    Uint8List envelope;
    try {
      envelope = await crypto.encrypt(
        password: password,
        plaintext:
            Uint8List.fromList(utf8.encode(jsonEncode(snapshot.toJson()))),
      );
    } on LockException catch (error) {
      return LockOutcome.refused(error.messageKo);
    }
    await store.writeFileAtomic(fileName, envelope);
    final checked = await store.readFile(fileName);
    if (checked == null) {
      return LockOutcome.refused('암호문을 저장하지 못했습니다. 원본을 유지합니다.');
    }
    try {
      final again = await crypto.decrypt(password: password, envelope: checked);
      final decoded = MemoSnapshot.fromJson(
        Map<String, Object?>.from(jsonDecode(utf8.decode(again)) as Map),
      );
      if (decoded.title != snapshot.title || decoded.body != snapshot.body) {
        await store.deleteFile(fileName);
        return LockOutcome.refused('저장한 암호문을 확인하지 못했습니다. 원본을 유지합니다.');
      }
    } on LockException {
      await store.deleteFile(fileName);
      return LockOutcome.refused('저장한 암호문을 확인하지 못했습니다. 원본을 유지합니다.');
    }

    await store.writeRegistry(
      snapshot.id,
      LockRegistryRecord(
        memoId: snapshot.id,
        fileName: fileName,
        plaintextPurged: false,
        titleVisible: false,
      ),
    );
    try {
      await vault.purge(snapshot.id);
    } catch (error) {
      await _rollback(snapshot.id, fileName);
      return LockOutcome.refused('평문을 지우지 못했습니다. 잠금을 취소하고 원본을 유지합니다.');
    }
    if (await vault.plaintextStillPresent(snapshot.id)) {
      await _rollback(snapshot.id, fileName);
      return LockOutcome.refused('평문이 아직 남아 있어 잠금을 취소했습니다.');
    }
    final record = LockRegistryRecord(
      memoId: snapshot.id,
      fileName: fileName,
      plaintextPurged: true,
      titleVisible: false,
    );
    await store.writeRegistry(snapshot.id, record);
    session.remove(snapshot.id);
    return LockOutcome.locked(record);
  }

  Future<UnlockOutcome> unlock({
    required String memoId,
    required String password,
  }) async {
    final record = await store.readRegistry(memoId);
    if (record == null || !record.plaintextPurged) {
      return const UnlockOutcome.failed('잠긴 메모가 아닙니다.');
    }
    final envelope = await store.readFile(record.fileName);
    if (envelope == null) {
      return const UnlockOutcome.failed('암호문 파일을 찾지 못했습니다.');
    }
    try {
      final clear =
          await crypto.decrypt(password: password, envelope: envelope);
      final snapshot = MemoSnapshot.fromJson(
        Map<String, Object?>.from(jsonDecode(utf8.decode(clear)) as Map),
      );
      session[memoId] = snapshot;
      return UnlockOutcome.opened(snapshot);
    } on LockException catch (error) {
      return UnlockOutcome.failed(error.messageKo);
    }
  }

  void forgetSession(String memoId) {
    session.remove(memoId);
  }

  Future<LockOutcome> changePassword({
    required String memoId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final record = await store.readRegistry(memoId);
    if (record == null || !record.plaintextPurged) {
      return const LockOutcome.refused('잠긴 메모가 아닙니다.');
    }
    final envelope = await store.readFile(record.fileName);
    if (envelope == null) {
      return const LockOutcome.refused('암호문 파일을 찾지 못했습니다.');
    }
    Uint8List clear;
    try {
      clear = await crypto.decrypt(password: oldPassword, envelope: envelope);
    } on LockException catch (error) {
      return LockOutcome.refused(error.messageKo);
    }
    final replacement =
        await crypto.encrypt(password: newPassword, plaintext: clear);
    final tempName = '${record.fileName}.tmp';
    await store.writeFileAtomic(tempName, replacement);
    final checked = await store.readFile(tempName);
    if (checked == null) {
      return const LockOutcome.refused('새 암호문을 확인하지 못했습니다. 이전 비밀번호가 유지됩니다.');
    }
    try {
      final again =
          await crypto.decrypt(password: newPassword, envelope: checked);
      if (!_bytesEqual(again, clear)) {
        await store.deleteFile(tempName);
        return const LockOutcome.refused('새 암호문 확인에 실패했습니다. 이전 비밀번호가 유지됩니다.');
      }
    } on LockException {
      await store.deleteFile(tempName);
      return const LockOutcome.refused('새 암호문 확인에 실패했습니다. 이전 비밀번호가 유지됩니다.');
    }
    await store.writeFileAtomic(record.fileName, checked);
    await store.deleteFile(tempName);
    session.remove(memoId);
    return LockOutcome.locked(record);
  }

  Future<LockOutcome> removePassword({
    required String memoId,
    required String password,
  }) async {
    final opened = await unlock(memoId: memoId, password: password);
    if (!opened.opened || opened.snapshot == null) {
      return LockOutcome.refused(opened.messageKo);
    }
    try {
      await vault.restore(opened.snapshot!);
    } catch (error) {
      return const LockOutcome.refused('원본을 복원하지 못했습니다. 암호문은 유지됩니다.');
    }
    final present = await vault.plaintextStillPresent(memoId);
    if (!present) {
      return const LockOutcome.refused('복원 확인에 실패했습니다. 암호문은 유지됩니다.');
    }
    final record = await store.readRegistry(memoId);
    if (record != null) {
      await store.deleteFile(record.fileName);
    }
    await store.writeRegistry(memoId, null);
    session.remove(memoId);
    return const LockOutcome.refused('비밀번호를 제거했습니다. 메모는 다시 평문입니다.');
  }

  Future<void> recoverIncomplete() async {
    final files = await store.listFiles();
    for (final name in files) {
      if (!name.endsWith('.afpl') || name.endsWith('.tmp')) {
        if (name.endsWith('.tmp')) {
          await store.deleteFile(name);
        }
        continue;
      }
    }
  }

  /// Call after a crash. Does not delete the only remaining copy.
  Future<void> recover(Set<String> memoIds) async {
    for (final memoId in memoIds) {
      final record = await store.readRegistry(memoId);
      final fileName = record?.fileName ?? 'locks/$memoId.afpl';
      final hasCipher = await store.readFile(fileName) != null;
      final hasPlain = await vault.plaintextStillPresent(memoId);
      if (record == null) {
        if (hasCipher && hasPlain) {
          await store.deleteFile(fileName);
        } else if (hasCipher && !hasPlain) {
          await store.writeRegistry(
            memoId,
            LockRegistryRecord(
              memoId: memoId,
              fileName: fileName,
              plaintextPurged: true,
              titleVisible: false,
            ),
          );
        }
        continue;
      }
      if (!record.plaintextPurged && hasPlain) {
        await _rollback(memoId, record.fileName);
      } else if (!record.plaintextPurged && !hasPlain && hasCipher) {
        await store.writeRegistry(
          memoId,
          LockRegistryRecord(
            memoId: memoId,
            fileName: record.fileName,
            plaintextPurged: true,
            titleVisible: false,
          ),
        );
      }
    }
  }

  Future<void> _rollback(String memoId, String fileName) async {
    await store.writeRegistry(memoId, null);
    await store.deleteFile(fileName);
  }
}

class MemoryLockStore implements LockStore {
  final Map<String, Uint8List> files = {};
  final Map<String, LockRegistryRecord> registry = {};

  @override
  Future<void> deleteFile(String name) async {
    files.remove(name);
  }

  @override
  Future<List<String>> listFiles() async => files.keys.toList();

  @override
  Future<Uint8List?> readFile(String name) async => files[name];

  @override
  Future<LockRegistryRecord?> readRegistry(String memoId) async =>
      registry[memoId];

  @override
  Future<void> writeFileAtomic(String name, Uint8List bytes) async {
    files[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeRegistry(String memoId, LockRegistryRecord? record) async {
    if (record == null) {
      registry.remove(memoId);
    } else {
      registry[memoId] = record;
    }
  }
}

class MemoryVault implements PlaintextVault {
  MemoryVault(this.notes);

  final Map<String, MemoSnapshot?> notes;
  final Map<String, String> searchIndex = {};
  bool failPurge = false;

  void index(MemoSnapshot snapshot) {
    searchIndex[snapshot.id] = '${snapshot.title}\n${snapshot.body}';
  }

  @override
  Future<bool> plaintextStillPresent(String memoId) async =>
      notes[memoId] != null;

  @override
  Future<void> purge(String memoId) async {
    if (failPurge) {
      throw StateError('purge failed');
    }
    notes[memoId] = null;
    searchIndex.remove(memoId);
  }

  @override
  Future<void> restore(MemoSnapshot snapshot) async {
    notes[snapshot.id] = snapshot;
    index(snapshot);
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

void _putU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

int _u32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
