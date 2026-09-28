import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Returns a deterministic SHA-256 fingerprint for a public Contract shape.
///
/// Maps are sorted recursively and descriptive/source fields are intentionally
/// supplied by each builder only when they are part of the public shape. The
/// digest detects an omitted version bump; it is not an authenticity token.
String contractShapeFingerprint(Object? shape) {
  final canonical = jsonEncode(_canonicalize(shape));
  return sha256.convert(utf8.encode(canonical)).toString();
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((left, right) => '${left.key}'.compareTo('${right.key}'));
    return <String, Object?>{
      for (final entry in entries) '${entry.key}': _canonicalize(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}
