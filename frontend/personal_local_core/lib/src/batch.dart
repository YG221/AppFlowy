class BatchEditException implements Exception {
  BatchEditException(this.messageKo);

  final String messageKo;

  @override
  String toString() => messageKo;
}

class MemoBlock {
  const MemoBlock({
    required this.id,
    required this.text,
    this.textColor,
    this.backgroundColor,
    this.preserved = const {},
  });

  final String id;
  final String text;
  final String? textColor;
  final String? backgroundColor;
  final Map<String, Object?> preserved;

  MemoBlock copy() {
    return MemoBlock(
      id: id,
      text: text,
      textColor: textColor,
      backgroundColor: backgroundColor,
      preserved: Map<String, Object?>.from(preserved),
    );
  }

  MemoBlock copyWith({
    String? text,
    String? textColor,
    bool clearTextColor = false,
    String? backgroundColor,
    bool clearBackgroundColor = false,
  }) {
    return MemoBlock(
      id: id,
      text: text ?? this.text,
      textColor: clearTextColor ? textColor : (textColor ?? this.textColor),
      backgroundColor: clearBackgroundColor
          ? backgroundColor
          : (backgroundColor ?? this.backgroundColor),
      preserved: Map<String, Object?>.from(preserved),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MemoBlock &&
        other.id == id &&
        other.text == text &&
        other.textColor == textColor &&
        other.backgroundColor == backgroundColor &&
        _mapEquals(other.preserved, preserved);
  }

  @override
  int get hashCode => Object.hash(id, text, textColor, backgroundColor);
}

class ReplacePreview {
  const ReplacePreview({
    required this.matchCount,
    required this.selectedCount,
    required this.selectedBecomeEmpty,
  });

  final int matchCount;
  final int selectedCount;
  final bool selectedBecomeEmpty;
}

/// Non-contiguous block editing. The selection is a set of ids, not a range.
class BatchEditSession {
  BatchEditSession(List<MemoBlock> blocks)
      : _blocks = blocks.map((block) => block.copy()).toList();

  final List<MemoBlock> _blocks;
  final List<List<MemoBlock>> _undo = [];
  final Set<String> selected = <String>{};

  List<MemoBlock> get blocks =>
      List<MemoBlock>.unmodifiable(_blocks.map((block) => block.copy()));

  int get undoCount => _undo.length;

  void toggle(String id) {
    if (!_blocks.any((block) => block.id == id)) {
      throw BatchEditException('없는 문단입니다.');
    }
    if (!selected.add(id)) {
      selected.remove(id);
    }
  }

  void setTextColor(String? color) {
    _mutate((block) => block.copyWith(textColor: color, clearTextColor: true));
  }

  void setBackgroundColor(String? color) {
    _mutate(
      (block) => block.copyWith(
        backgroundColor: color,
        clearBackgroundColor: true,
      ),
    );
  }

  ReplacePreview previewReplace({
    required String find,
    required String replace,
  }) {
    if (find.isEmpty) {
      throw BatchEditException('찾을 텍스트를 입력하세요.');
    }
    var matches = 0;
    var becomeEmpty = false;
    for (final block in _blocks) {
      if (!selected.contains(block.id) || !block.text.contains(find)) {
        continue;
      }
      matches += find.allMatches(block.text).length;
      if (block.text.replaceAll(find, replace).isEmpty) {
        becomeEmpty = true;
      }
    }
    return ReplacePreview(
      matchCount: matches,
      selectedCount: selected.length,
      selectedBecomeEmpty: becomeEmpty || replace.isEmpty,
    );
  }

  void applyReplace({
    required String find,
    required String replace,
    required bool confirmed,
  }) {
    final preview = previewReplace(find: find, replace: replace);
    if (preview.matchCount == 0) {
      throw BatchEditException('선택한 문단에서 찾지 못했습니다.');
    }
    final destructive = replace.isEmpty || preview.selectedBecomeEmpty;
    if (destructive && !confirmed) {
      throw BatchEditException('내용을 지우는 바꾸기입니다. 확인이 필요합니다.');
    }
    _mutate(
        (block) => block.copyWith(text: block.text.replaceAll(find, replace)));
  }

  void undo() {
    if (_undo.isEmpty) {
      return;
    }
    final previous = _undo.removeLast();
    _blocks
      ..clear()
      ..addAll(previous.map((block) => block.copy()));
  }

  void _mutate(MemoBlock Function(MemoBlock block) change) {
    if (selected.isEmpty) {
      throw BatchEditException('문단을 먼저 선택하세요.');
    }
    _undo.add(_blocks.map((block) => block.copy()).toList());
    for (var i = 0; i < _blocks.length; i++) {
      if (!selected.contains(_blocks[i].id)) {
        continue;
      }
      _blocks[i] = change(_blocks[i]);
    }
  }
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
