import 'dart:convert';
import 'dart:io';

final class _Rule {
  const _Rule(this.name, this.pattern);

  final String name;
  final RegExp pattern;
}

final _rules = <_Rule>[
  _Rule('macOS absolute home path', RegExp(r'/Users/[A-Za-z0-9._-]+/')),
  _Rule('Linux absolute home path', RegExp(r'/home/[A-Za-z0-9._-]+/')),
  _Rule(
    'Windows absolute home path',
    RegExp(r'[A-Za-z]:\\Users\\[A-Za-z0-9._-]+\\'),
  ),
  _Rule(
    'private key material',
    RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
  ),
  _Rule('GitHub access token', RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}')),
  _Rule('AWS access key', RegExp(r'AKIA[0-9A-Z]{16}')),
  _Rule(
    'committed credential field',
    RegExp(
      r'''["'](?:keyPassword|storePassword|clientSecret|apiKey|accessToken)["']\s*:\s*["'][^"'${}<>]{8,}["']''',
    ),
  ),
  _Rule(
    'Apple development team',
    RegExp(r'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\s*;'),
  ),
];

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
    ['ls-files', '-z'],
    workingDirectory: root.path,
    stdoutEncoding: const SystemEncoding(),
  );
  if (trackedResult.exitCode != 0) {
    stderr.writeln('Unable to enumerate tracked files.');
    exitCode = 2;
    return;
  }

  final findings = <String>[];
  final paths = '${trackedResult.stdout}'
      .split('\u0000')
      .where((path) => path.isNotEmpty);
  for (final path in paths) {
    if (path == 'tool/release_sensitivity_check.dart') continue;
    final file = File('${root.path}${Platform.pathSeparator}$path');
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    if (bytes.contains(0)) continue;
    final source = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(source);
    for (var index = 0; index < lines.length; index++) {
      for (final rule in _rules) {
        if (rule.pattern.hasMatch(lines[index])) {
          findings.add('$path:${index + 1}: ${rule.name}');
        }
      }
    }
  }

  if (findings.isEmpty) {
    stdout.writeln('Release sensitivity check passed.');
    return;
  }
  stderr.writeln('Release sensitivity check found ${findings.length} item(s):');
  for (final finding in findings) {
    stderr.writeln('  $finding');
  }
  stderr.writeln('Values are intentionally omitted from this report.');
  exitCode = 1;
}
