import 'package:appflowy/personal_local/memo_popout_app.dart';
import 'package:appflowy/personal_local/portable_data_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release Windows build stores data beside the executable', () {
    final path = portableDataDirectory(
      enabled: true,
      releaseMode: true,
      isWindows: true,
      resolvedExecutable: r'C:\Notes\AppFlowy.exe',
    );
    expect(path, r'C:\Notes\AppFlowyDataDoNotRename');
  });

  test('debug, tests, and non-Windows builds keep the normal data path', () {
    expect(
      portableDataDirectory(
        enabled: true,
        releaseMode: false,
        isWindows: true,
        resolvedExecutable: r'C:\Notes\AppFlowy.exe',
      ),
      isNull,
    );
    expect(
      portableDataDirectory(
        enabled: true,
        releaseMode: true,
        isWindows: false,
        resolvedExecutable: '/opt/AppFlowy/appflowy',
      ),
      isNull,
    );
    expect(
      portableDataDirectory(
        enabled: false,
        releaseMode: true,
        isWindows: true,
        resolvedExecutable: r'C:\Notes\AppFlowy.exe',
      ),
      isNull,
    );
  });

  test('only the multi-window entrypoint is a popout process', () {
    expect(isMemoPopoutProcess(['multi_window', 'id', '{}']), isTrue);
    expect(isMemoPopoutProcess(const []), isFalse);
    expect(isMemoPopoutProcess(['AppFlowy.exe']), isFalse);
  });
}
