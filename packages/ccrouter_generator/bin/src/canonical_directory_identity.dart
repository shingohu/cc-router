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

/// Returns one stable identity for an existing file across path aliases.
///
/// Missing or atomically replaced files retain their normalized absolute
/// spelling so callers can still produce deterministic failure diagnostics.
String canonicalFileIdentity(String value) {
  final file = File(value).absolute;
  try {
    return path.normalize(file.resolveSymbolicLinksSync());
  } on FileSystemException {
    return path.normalize(file.path);
  }
}

/// Reports whether two file spellings identify the same filesystem entry.
bool hasSameFileIdentity(String first, String second) =>
    path.equals(canonicalFileIdentity(first), canonicalFileIdentity(second));
