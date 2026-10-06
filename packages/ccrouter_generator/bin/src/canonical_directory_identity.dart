import 'dart:io';

import 'package:path/path.dart' as path;

/// Returns one stable identity for an existing directory across path aliases.
///
/// Missing or temporarily unavailable directories retain their normalized
/// absolute spelling so callers can still report bounded diagnostics.
String canonicalDirectoryIdentity(String value) {
  final directory = Directory(value).absolute;
  try {
    return path.normalize(directory.resolveSymbolicLinksSync());
  } on FileSystemException {
    return path.normalize(directory.path);
  }
}

/// Reports whether two directory spellings identify the same filesystem root.
bool hasSameDirectoryIdentity(String first, String second) => path.equals(
  canonicalDirectoryIdentity(first),
  canonicalDirectoryIdentity(second),
);
