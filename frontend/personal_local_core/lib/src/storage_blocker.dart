/// Why a password dialog on an AppFlowy collab note would not be encryption.
class PlaintextStore {
  const PlaintextStore({
    required this.id,
    required this.detailKo,
  });

  final String id;
  final String detailKo;
}

class StorageEncryptionBlocker {
  const StorageEncryptionBlocker._();

  static const stores = <PlaintextStore>[
    PlaintextStore(
      id: 'rocksdb_collab',
      detailKo:
          '문서 본문은 CollabKVDB(RocksDB)의 Yrs 상태에 저장됩니다. 같은 문서에 덮어쓰면 삭제된 글자가 CRDT 상태에 남을 수 있고, 문서를 지우는 Rust API는 Dart에 연결되어 있지 않습니다.',
    ),
    PlaintextStore(
      id: 'collab_snapshot',
      detailKo:
          'SQLite collab_snapshot.data에 문서당 최대 5개의 인코딩된 스냅샷이 남습니다. 스냅샷 삭제는 Dart에서 호출할 수 없습니다.',
    ),
    PlaintextStore(
      id: 'tantivy',
      detailKo:
          'Tantivy 색인이 본문과 제목을 저장합니다. 색인 삭제 함수는 있으나 검색 삭제 이벤트가 앱에 노출되어 있지 않고, 세그먼트 파일은 병합 전까지 삭제 문서를 남길 수 있습니다.',
    ),
    PlaintextStore(
      id: 'folder_title',
      detailKo: '메모 제목은 폴더 협업 데이터의 보기 이름으로 저장됩니다.',
    ),
    PlaintextStore(
      id: 'memory_cache',
      detailKo:
          '문서를 닫아도 DocumentManager가 약 120초 동안 메모리에 유지합니다. 디버그 빌드는 문서 JSON을 로그로 남길 수 있습니다.',
    ),
    PlaintextStore(
      id: 'historical_copies',
      detailKo:
          'SQLite WAL, RocksDB의 이전 파일, 운영체제 임시 파일, OneDrive 같은 폴더 버전 기록은 앱이 지울 수 없습니다.',
    ),
  ];

  static const summaryKo =
      '이 저장 구조에서는 선택한 메모의 평문을 안전하게 지울 수 없습니다. 비밀번호 창만 보여 주면 암호화가 아니므로 잠금을 완료하지 않습니다. 작업공간 전체가 암호화되는 것도 아닙니다.';
}
