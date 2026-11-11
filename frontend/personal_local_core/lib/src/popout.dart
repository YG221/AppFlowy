class PopoutRequest {
  const PopoutRequest({
    required this.documentId,
    required this.title,
    required this.body,
    this.readOnly = true,
    this.obscured = false,
  });

  final String documentId;
  final String title;
  final String body;
  final bool readOnly;
  final bool obscured;

  PopoutRequest copyWith({
    String? body,
    bool? readOnly,
    bool? obscured,
  }) {
    return PopoutRequest(
      documentId: documentId,
      title: title,
      body: body ?? this.body,
      readOnly: readOnly ?? this.readOnly,
      obscured: obscured ?? this.obscured,
    );
  }
}

class PopoutSize {
  const PopoutSize(this.width, this.height);

  final double width;
  final double height;

  static const initial = PopoutSize(420, 560);
  static const minimum = PopoutSize(280, 240);
  static const maximum = PopoutSize(1600, 1200);
}

class PopoutWindow {
  PopoutWindow({
    required this.id,
    required this.request,
    required this.size,
  });

  final String id;
  PopoutRequest request;
  PopoutSize size;
  bool closed = false;
}

abstract class PopoutHost {
  Future<String> open({
    required PopoutRequest request,
    required PopoutSize size,
  });

  Future<void> resize(String windowId, PopoutSize size);

  Future<void> close(String windowId);
}

class PopoutController {
  PopoutController({
    required this.host,
    this.isLocked = _noneLocked,
  });

  final PopoutHost host;
  final bool Function(String documentId) isLocked;
  final Map<String, PopoutWindow> windows = {};
  var _next = 0;

  static bool _noneLocked(String documentId) => false;

  Future<PopoutWindow> open(PopoutRequest request) async {
    final locked = isLocked(request.documentId);
    final shown = locked
        ? request.copyWith(
            body: '',
            obscured: true,
            readOnly: true,
          )
        : request.copyWith(readOnly: true);
    final id = await host.open(request: shown, size: PopoutSize.initial);
    final window = PopoutWindow(
      id: id.isEmpty ? 'popout-${_next++}' : id,
      request: shown,
      size: PopoutSize.initial,
    );
    windows[window.id] = window;
    return window;
  }

  Future<void> resize(String windowId, PopoutSize requested) async {
    final window = windows[windowId];
    if (window == null || window.closed) {
      throw StateError('없는 창입니다.');
    }
    final size = PopoutSize(
      requested.width.clamp(PopoutSize.minimum.width, PopoutSize.maximum.width),
      requested.height
          .clamp(PopoutSize.minimum.height, PopoutSize.maximum.height),
    );
    await host.resize(windowId, size);
    window.size = size;
  }

  Future<void> close(String windowId) async {
    final window = windows[windowId];
    if (window == null || window.closed) {
      return;
    }
    await host.close(windowId);
    window.closed = true;
  }

  Future<void> closeForDocument(String documentId) async {
    final ids = windows.entries
        .where((entry) => entry.value.request.documentId == documentId)
        .map((entry) => entry.key)
        .toList();
    for (final id in ids) {
      await close(id);
    }
  }
}

class MemoryPopoutHost implements PopoutHost {
  final Map<String, PopoutSize> sizes = {};
  var _next = 0;

  @override
  Future<String> open({
    required PopoutRequest request,
    required PopoutSize size,
  }) async {
    final id = 'native-${_next++}';
    sizes[id] = size;
    return id;
  }

  @override
  Future<void> resize(String windowId, PopoutSize size) async {
    sizes[windowId] = size;
  }

  @override
  Future<void> close(String windowId) async {
    sizes.remove(windowId);
  }
}
