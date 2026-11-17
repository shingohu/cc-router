"""Compare stock build_runner versions without CCRouter or shared build state.

Run with --dart /absolute/path/to/dart. Each case owns a new temporary package;
Pub may download immutable packages into its normal cache. All files and logs
are retained in the printed temporary directories for inspection.
"""

import argparse
import json
import pathlib
import subprocess
import tempfile

BUILDER = """import 'package:build/build.dart';
Builder createBuilder(BuilderOptions options) => Emit();
class Emit implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {'.seed': ['.result']};
  @override
  Future<void> build(BuildStep step) async {
    final value = await step.readAsString(step.inputId);
    await step.writeAsString(
      step.inputId.changeExtension('.result'), 'generated:$value');
  }
}
"""
CONFIG = """builders:
  emit:
    import: 'package:incremental_probe_fixture/builder.dart'
    builder_factories: ['createBuilder']
    build_extensions: {'.seed': ['.result']}
    auto_apply: root_package
    build_to: source
"""


def run(dart, root, arguments, log):
    result = subprocess.run(
        [dart, *arguments], cwd=root, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180,
    )
    (root / log).write_text(result.stdout)
    return result


def probe(dart, runner, analyzer, build, expected):
    root = pathlib.Path(tempfile.mkdtemp(prefix=f'ccrouter-br-{runner}-'))
    (root / 'lib').mkdir()
    (root / 'pubspec.yaml').write_text(
        'name: incremental_probe_fixture\nenvironment:\n  sdk: ^3.11.0\n'
        f'dependencies:\n  analyzer: {analyzer}\n  build: {build}\n'
        f'dev_dependencies:\n  build_runner: {runner}\n'
    )
    (root / 'lib/builder.dart').write_text(BUILDER)
    (root / 'build.yaml').write_text(CONFIG)
    resolved = run(dart, root, ['pub', 'get'], 'pub.log')
    assert resolved.returncode == 0, (str(root), resolved.stdout)
    (root / 'lib/a.seed').write_text('A')
    first = run(dart, root, ['run', 'build_runner', 'build'], 'first.log')
    assert first.returncode == 0, (str(root), first.stdout)
    (root / 'lib/b.seed').write_text('B')
    (root / 'lib/b.result').write_text('generated:B')
    second = run(dart, root, ['run', 'build_runner', 'build'], 'incremental.log')
    assert second.returncode == expected, (str(root), second.stdout)
    if expected:
        assert 'Null check operator used on a null value' in second.stdout
        assert '_writeBuildOutput' in second.stdout
    else:
        assert (root / 'lib/b.result').read_text() == 'generated:B'
        again = run(dart, root, ['run', 'build_runner', 'build'], 'repeat.log')
        assert again.returncode == 0, (str(root), again.stdout)
        assert (root / 'lib/a.result').read_text() == 'generated:A'
    return {'build_runner': runner, 'directory': str(root),
            'first_exit': first.returncode, 'incremental_exit': second.returncode}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True)
    options = parser.parse_args()
    sdk = subprocess.check_output([options.dart, '--version'], text=True).strip()
    cases = [probe(options.dart, '2.15.1', '10.0.1', '4.0.7', 255),
             probe(options.dart, '2.16.1', '13.3.0', '4.0.11', 0)]
    print(json.dumps({'sdk': sdk, 'cases': cases}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
