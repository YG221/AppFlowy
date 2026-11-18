import 'package:path/path.dart' as p;

/// Folder kept beside the Windows executable for this portable edition.
const portableDataFolderName = 'AppFlowyDataDoNotRename';

/// Returns the portable data directory, or null when this process should
/// keep using the normal application-support path.
///
/// Release Windows builds of the personal-local edition store notes next to
/// the exe. Tests and debug runs stay on the usual path.
String? portableDataDirectory({
  required bool enabled,
  required bool releaseMode,
  required bool isWindows,
  required String resolvedExecutable,
}) {
  if (!enabled || !releaseMode || !isWindows) {
    return null;
  }
  final context = p.Context(style: p.Style.windows);
  final folder = context.dirname(resolvedExecutable);
  if (folder.isEmpty || folder == '.' || folder == resolvedExecutable) {
    return null;
  }
  return context.join(folder, portableDataFolderName);
}
