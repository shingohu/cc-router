import 'dart:convert';
import 'dart:io';

final _markdownLink = RegExp(r'''!?\[[^\]]*\]\(([^)\n]+)\)''');

void main() {
  final rootResult = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  if (rootResult.exitCode != 0) {
    stderr.writeln('Run this check from inside a Git repository.');
    exitCode = 2;
    return;
  }
  final root = Directory('${rootResult.stdout}'.trim());
  final trackedResult = Process.runSync(
    'git',
    ['ls-files', '-z', '*.md'],
    workingDirectory: root.path,
    stdoutEncoding: const SystemEncoding(),
  );
  if (trackedResult.exitCode != 0) {
    stderr.writeln('Unable to enumerate tracked Markdown files.');
    exitCode = 2;
    return;
  }

  final markdownPaths = '${trackedResult.stdout}'
      .split('\u0000')
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  final findings = <String>[];
  for (final path in markdownPaths) {
    final file = File('${root.path}${Platform.pathSeparator}$path');
    final source = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    for (final match in _markdownLink.allMatches(source)) {
      final target = _localTarget(match.group(1)!);
      if (target == null) continue;
      final targetPath = target.split('#').first;
      if (targetPath.isEmpty) continue;
      late final String decoded;
      try {
        decoded = Uri.decodeComponent(targetPath);
      } on FormatException {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        findings.add('$path:$line: malformed local link `$targetPath`');
        continue;
      }
      final resolved = File(
        '${file.parent.path}${Platform.pathSeparator}$decoded',
      ).absolute;
      if (!resolved.existsSync() && !Directory(resolved.path).existsSync()) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        findings.add('$path:$line: missing local link target `$targetPath`');
      }
    }
  }

  _checkIndexCoverage(root, 'docs', 'docs/README.md', findings);
  _checkIndexCoverage(root, 'demo/docs', 'demo/README.md', findings);

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

String? _localTarget(String rawTarget) {
  var target = rawTarget.trim();
  if (target.startsWith('<')) {
    final end = target.indexOf('>');
    if (end < 0) return null;
    target = target.substring(1, end);
  } else {
    target = target.split(RegExp(r'\s+')).first;
  }
  if (target.isEmpty || target.startsWith('#')) return null;
  final uri = Uri.tryParse(target);
  if (uri != null && uri.hasScheme) return null;
  return target;
}

void _checkIndexCoverage(
  Directory root,
  String directoryPath,
  String indexPath,
  List<String> findings,
) {
  final directory = Directory('${root.path}/$directoryPath');
  final index = File('${root.path}/$indexPath');
  if (!index.existsSync()) {
    findings.add('$indexPath: missing documentation index');
    return;
  }
  final indexSource = index.readAsStringSync();
  for (final entity in directory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    final name = entity.uri.pathSegments.last;
    if (entity.absolute.path == index.absolute.path) continue;
    if (!indexSource.contains(name)) {
      findings.add('$indexPath: does not reference $directoryPath/$name');
    }
  }
}
