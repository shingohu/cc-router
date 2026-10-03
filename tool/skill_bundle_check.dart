import 'dart:io';

/// The two directories distributed together to application repositories.
const skillBundleNames = [
  'ccrouter-integration-development',
  'ccrouter-cli-development',
];

/// Checks an isolated bundle, so repository-only links cannot pass accidentally.
List<String> checkSkillBundle(Directory bundle) {
  final findings = <String>[];
  final root = bundle.absolute.uri;
  final links = RegExp(r'''!?\[[^\]]*\]\(([^)\n]+)\)''');
  for (final name in skillBundleNames) {
    final skill = Directory.fromUri(root.resolve('$name/'));
    if (!File('${skill.path}/SKILL.md').existsSync()) {
      findings.add('Missing required Skill: $name/SKILL.md');
      continue;
    }
    for (final file in skill.listSync(recursive: true, followLinks: false)) {
      if (file is Link) {
        findings.add('Bundle must contain files, not symlinks: ${file.path}');
        continue;
      }
      if (file is! File || !file.path.endsWith('.md')) continue;
      for (final match in links.allMatches(file.readAsStringSync())) {
        final raw = match.group(1)!.trim();
        if (raw.startsWith('<') && !raw.contains('>')) {
          findings.add('${file.path}: malformed link $raw');
          continue;
        }
        final target = raw.startsWith('<')
            ? raw.substring(1, raw.indexOf('>'))
            : raw.split(RegExp(r'\s+')).first;
        final uri = Uri.tryParse(target);
        if (uri == null) {
          findings.add('${file.path}: invalid link $target');
          continue;
        }
        if (uri.hasScheme && uri.scheme != 'file') continue;
        if (target.startsWith('#')) continue;
        final resolved = file.absolute.uri.resolveUri(uri).removeFragment();
        if (!resolved.toString().startsWith(root.toString())) {
          findings.add('${file.path}: link escapes bundle: $target');
        } else if (!File.fromUri(resolved).existsSync() &&
            !Directory.fromUri(resolved).existsSync()) {
          findings.add('${file.path}: missing bundled reference: $target');
        }
      }
    }
  }
  return findings;
}

/// Checks documented invocations against the executable's actual help surface.
/// It never executes mutating commands, hooks, or scaffolds from documentation.
List<String> checkSkillCommands(String markdown, String help) {
  final usage = help
      .split('\n')
      .where((line) => line.startsWith('  ccrouter '));
  String route(String value) => value
      .trim()
      .split(RegExp(r'\s+'))
      .takeWhile(
        (word) =>
            !word.startsWith('<') &&
            !word.startsWith('[') &&
            !word.startsWith('-'),
      )
      .join(' ');
  final surfaces = {for (final line in usage) route(line): line};
  final findings = <String>[];
  var commands = 0;
  for (final line in markdown.split('\n')) {
    const prefix =
        'fvm dart run --verbosity=error ccrouter_generator:ccrouter ';
    if (!line.startsWith(prefix)) continue;
    commands++;
    final command = 'ccrouter ${line.substring(prefix.length)}';
    final declared = surfaces[route(command)];
    if (declared == null) {
      findings.add('Unknown documented CLI command: $command');
      continue;
    }
    for (final flag in RegExp(r'--[a-z][a-z-]*').allMatches(command)) {
      if (!RegExp(
        r'--[a-z][a-z-]*',
      ).allMatches(declared).any((entry) => entry.group(0) == flag.group(0))) {
        findings.add('Unsupported documented flag: $command');
      }
    }
  }
  if (surfaces.isEmpty) findings.add('CLI help has no command surface.');
  if (commands == 0) findings.add('Skill contains no verifiable CLI matrix.');
  return findings;
}

/// Copies only the published Skill directories, without framework docs/sources.
void copySkillBundle(Directory source, Directory destination) {
  for (final name in skillBundleNames) {
    final directory = Directory('${source.path}/$name');
    if (!directory.existsSync()) continue;
    for (final entry in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is Link)
        throw StateError('Skill contains symlink: ${entry.path}');
      if (entry is! File) continue;
      final relative = entry.path.substring(source.path.length + 1);
      final target = File('${destination.path}/$relative');
      target.parent.createSync(recursive: true);
      entry.copySync(target.path);
    }
  }
}

/// Runs from the framework repository; consumers need only the two Skill folders.
Future<void> main() async {
  final root = Directory.current;
  final temporary = Directory.systemTemp.createTempSync(
    'ccrouter-skill-bundle-',
  );
  try {
    copySkillBundle(Directory('${root.path}/skills'), temporary);
    final findings = checkSkillBundle(temporary);
    final help = await Process.run(Platform.resolvedExecutable, [
      'run',
      '--verbosity=error',
      'ccrouter_generator:ccrouter',
      '--help',
    ], workingDirectory: root.path);
    if (help.exitCode != 0) {
      findings.add('CLI help failed: ${help.stderr}');
    } else {
      findings.addAll(
        checkSkillCommands(
          File(
            '${temporary.path}/ccrouter-cli-development/SKILL.md',
          ).readAsStringSync(),
          '${help.stdout}',
        ),
      );
    }
    if (findings.isNotEmpty) {
      stderr.writeln(findings.join('\n'));
      exitCode = 1;
    } else {
      stdout.writeln(
        'Isolated two-Skill bundle and live CLI command checks passed.',
      );
    }
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
