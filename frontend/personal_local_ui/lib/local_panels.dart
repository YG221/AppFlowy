import 'package:flutter/material.dart';
import 'package:personal_local_ui/personal_copy.dart';

class MemoPopoutView extends StatelessWidget {
  const MemoPopoutView({
    super.key,
    required this.title,
    required this.body,
    required this.readOnly,
    this.onResize,
    this.onClose,
  });

  final String title;
  final String body;
  final bool readOnly;
  final VoidCallback? onResize;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    readOnly
                        ? PersonalCopy.text(
                            context,
                            '읽기 전용 작은 창',
                            'Read-only small window',
                          )
                        : title,
                    key: const Key('popout-banner'),
                  ),
                ),
                IconButton(
                  key: const Key('popout-resize'),
                  onPressed: onResize,
                  icon: const Icon(Icons.open_in_full),
                ),
                IconButton(
                  key: const Key('popout-close'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                body,
                key: const Key('popout-body'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LocalCreateGate extends StatelessWidget {
  const LocalCreateGate({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                PersonalCopy.text(context, '로컬 메모', 'Local notes'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                PersonalCopy.text(
                  context,
                  '계정 없이 이 폴더에 메모를 만듭니다. 로그인이나 가입은 없습니다.',
                  'Create notes in this folder without an account.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('create-local-workspace'),
                onPressed: onCreate,
                child: Text(
                  PersonalCopy.text(
                    context,
                    '로컬 작업공간 만들기',
                    'Create local workspace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExchangePreview extends StatelessWidget {
  const ExchangePreview({
    super.key,
    required this.titles,
    required this.encryptedCount,
    required this.notes,
  });

  final List<String> titles;
  final int encryptedCount;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PersonalCopy.text(context, '가져오기 미리보기', 'Import preview'),
          style: Theme.of(context).textTheme.titleMedium,
          key: const Key('import-preview-title'),
        ),
        Text(
          PersonalCopy.text(
            context,
            '새 문서로 추가합니다. 기존 메모는 덮어쓰지 않습니다.',
            'These become new documents. Existing notes are not overwritten.',
          ),
        ),
        Text('${titles.length}'),
        if (encryptedCount > 0)
          Text(
            PersonalCopy.text(
              context,
              '암호문 $encryptedCount개는 비밀번호 없이 열지 않습니다.',
              '$encryptedCount encrypted item(s) stay encrypted.',
            ),
            key: const Key('encrypted-count'),
          ),
        for (final title in titles) Text(title),
        for (final note in notes) Text(note),
      ],
    );
  }
}
