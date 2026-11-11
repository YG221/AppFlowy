import 'package:personal_local_core/personal_local_core.dart';
import 'package:test/test.dart';

void main() {
  MemoBlock block(String id, String text) => MemoBlock(
        id: id,
        text: text,
        preserved: const {'bold': true},
      );

  test('disjoint selection skips the middle block and undo restores it', () {
    final session = BatchEditSession([
      block('a', '가'),
      block('b', '나'),
      block('c', '다'),
    ]);
    session
      ..toggle('a')
      ..toggle('c')
      ..setTextColor('#aa0000')
      ..setBackgroundColor('#fff2a8');

    final blocks = session.blocks;
    expect(blocks[0].textColor, '#aa0000');
    expect(blocks[0].backgroundColor, '#fff2a8');
    expect(blocks[1].textColor, isNull);
    expect(blocks[1].backgroundColor, isNull);
    expect(blocks[1].text, '나');
    expect(blocks[1].preserved['bold'], true);
    expect(blocks[2].textColor, '#aa0000');

    session.undo();
    expect(session.blocks[0].textColor, '#aa0000');
    expect(session.blocks[0].backgroundColor, isNull);
    expect(session.blocks[1].text, '나');
    session.undo();
    expect(session.blocks[0].textColor, isNull);
    expect(session.blocks[2].textColor, isNull);
    expect(session.blocks[1].preserved['bold'], true);
  });

  test('replace changes only selected text and requires confirmation to erase',
      () {
    final session = BatchEditSession([
      block('a', '빨강 사과'),
      block('b', '파랑 사과'),
      block('c', '노란 사과'),
    ]);
    session
      ..toggle('a')
      ..toggle('c');
    final preview = session.previewReplace(find: '사과', replace: '배');
    expect(preview.matchCount, 2);
    session.applyReplace(find: '사과', replace: '배', confirmed: true);
    expect(session.blocks.map((item) => item.text), ['빨강 배', '파랑 사과', '노란 배']);
    expect(session.blocks[0].preserved['bold'], true);

    expect(
      () => session.applyReplace(find: '배', replace: '', confirmed: false),
      throwsA(isA<BatchEditException>()),
    );
    session.applyReplace(find: '배', replace: '', confirmed: true);
    expect(session.blocks[0].text, '빨강 ');
    expect(session.blocks[1].text, '파랑 사과');
    session.undo();
    expect(session.blocks[0].text, '빨강 배');
  });
}
