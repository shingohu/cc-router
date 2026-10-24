import 'dart:convert';
import 'dart:io';

import 'markdown_links.dart';

void main() {
  final rootResult = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  if (rootResult.exitCode != 0) {
    stderr.writeln('Run this check from inside a Git repository.');
    exitCode = 2;
    return;
  }
  final root = Directory('${rootResult.stdout}'.trim());
  final filesResult = Process.runSync(
    'git',
    [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '-z',
      '--',
      '*.md',
    ],
    workingDirectory: root.path,
    stdoutEncoding: const SystemEncoding(),
  );
  if (filesResult.exitCode != 0) {
    stderr.writeln('Unable to enumerate current Markdown files.');
    exitCode = 2;
    return;
  }

  final markdownPaths = '${filesResult.stdout}'
      .split('\u0000')
      .where((path) => path.isNotEmpty)
      .toSet()
      // Include new authored files before staging; ignore deleted tracked
      // paths and excluded scratch files, matching the current worktree.
      .where((path) => File('${root.path}/$path').existsSync())
      .toList(growable: false);
  final findings = <String>[];
  for (final path in markdownPaths) {
    final file = File('${root.path}/$path');
    final source = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    for (final reference in markdownReferences(source)) {
      Uri? target;
      try {
        target = localMarkdownTarget(reference.target, file.absolute.uri);
      } on FormatException {
        findings.add('$path: malformed local link `${reference.target}`');
        continue;
      }
      if (target == null) continue;
      if (!File.fromUri(target).existsSync() &&
          !Directory.fromUri(target).existsSync()) {
        findings.add('$path: missing local link target `${reference.target}`');
      }
    }
  }

  _checkIndexCoverage(root, markdownPaths, 'docs', 'docs/README.md', findings);
  _checkIndexCoverage(
    root,
    markdownPaths,
    'demo/docs',
    'demo/README.md',
    findings,
  );

  if (findings.isEmpty) {
    stdout.writeln(
      'Documentation check passed for ${markdownPaths.length} Markdown files.',
    );
    return;
  }
  stderr.writeln('Documentation check found ${findings.length} item(s):');
  for (final finding in findings) {
    stderr.writeln('  $finding');
  }
  exitCode = 1;
}

void _checkIndexCoverage(
  Directory root,
  List<String> markdownPaths,
  String directoryPath,
  String indexPath,
  List<String> findings,
) {
  final index = File('${root.path}/$indexPath');
  if (!index.existsSync()) {
    findings.add('$indexPath: missing documentation index');
    return;
  }
  final linkedTargets = <Uri>{};
  for (final reference in markdownReferences(index.readAsStringSync())) {
    if (reference.isImage) continue;
    try {
      final target = localMarkdownTarget(reference.target, index.absolute.uri);
      if (target != null) linkedTargets.add(target);
    } on FormatException {
      // The main link check already reports malformed local destinations.
    }
  }
  // Use the same Git-selected current files as the link check: ignored scratch
  // documents must not become index requirements, while new authored files do.
  final prefix = '$directoryPath/';
  for (final path in markdownPaths) {
    if (path == indexPath || !path.startsWith(prefix)) continue;
    if (path.substring(prefix.length).contains('/')) continue;
    final target = File('${root.path}/$path').absolute.uri.normalizePath();
    if (!linkedTargets.contains(target)) {
      findings.add('$indexPath: does not reference $path');
    }
  }
}
