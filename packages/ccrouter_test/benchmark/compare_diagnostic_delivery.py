"""Compare both Core implementations in one AOT process without editing checkout.

Run from any directory:
  python3 packages/ccrouter_test/benchmark/compare_diagnostic_delivery.py \
    --reference <baseline-commit> --output /tmp/sink-comparison.json

Requires the workspace package config and fvm. Temporary sources/executable are
kept for inspection; neither Git state nor production sources are modified.
The fixture deliberately uses dynamic Runtime calls on both paths, because the
two Core libraries have distinct Runtime types but share the same contracts.
"""

import argparse
import json
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tempfile
from urllib.parse import urljoin


def compare(reference, output, reference_core=None):
    root = Path(__file__).resolve().parents[3]
    work = Path(tempfile.mkdtemp(prefix="ccrouter-sink-comparison-"))
    core = work / "reference_core"
    if reference_core is not None:
        source = Path(reference_core).resolve()
        if not (source / "lib/ccrouter_core.dart").is_file():
            raise RuntimeError("Reference directory has no Core library")
        shutil.copytree(source / "lib", core / "lib")
        provenance = {"referenceCorePath": str(source)}
    else:
        reference_sha = subprocess.check_output(
            ["git", "rev-parse", "--verify", reference + "^{commit}"], cwd=root, text=True
        ).strip()
        prefix = "packages/ccrouter_core/"
        paths = subprocess.check_output(
            ["git", "ls-tree", "-r", "--name-only", reference_sha, "--", prefix + "lib"],
            cwd=root, text=True,
        ).splitlines()
        if not paths:
            raise RuntimeError("Reference has no Core library")
        for path in paths:
            target = core / path.removeprefix(prefix)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(subprocess.check_output(
                ["git", "show", reference_sha + ":" + path], cwd=root
            ))
        provenance = {"referenceCommit": reference_sha}
    package_config = root / ".dart_tool/package_config.json"
    config = json.loads(package_config.read_text())
    for package in config["packages"]:
        package["rootUri"] = urljoin(package_config.as_uri(), package["rootUri"])
    legacy = next(p for p in config["packages"] if p["name"] == "ccrouter_core").copy()
    legacy.update(name="ccrouter_core_reference", rootUri=core.as_uri() + "/")
    config["packages"].append(legacy)
    config_path = work / "package_config.json"
    config_path.write_text(json.dumps(config))

    fixture = Path(__file__).with_name("diagnostic_delivery.dart").read_text()
    helpers = fixture[fixture.index("final class _Command"):]
    source = r"""
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_core_reference/ccrouter_core.dart' as legacy;

Future<void> main() async {
  const commands = 10000;
  final runs = [
    <String, Object>{'label': 'before', 'samples': <Map<String, Object>>[]},
    <String, Object>{'label': 'after', 'samples': <Map<String, Object>>[]},
  ];
  final cpu = _ThreadCpuClock.open();
  try {
    for (var round = 0; round < 51; round++) {
      for (final mode in round.isEven ? ['off', 'sync', 'future'] : ['future', 'sync', 'off']) {
        final sinks = [for (var i = 0; i < 2; i++) mode == 'off' ? null : _Sink(mode == 'future')];
        CCDiagnosticsConfig config(int i) => CCDiagnosticsConfig(
          sink: sinks[i], defaultEnabled: false,
          policies: const [CCDiagnosticCategoryPolicy(category: CCDiagnosticCategory.command)],
        );
        final runtimes = <dynamic>[
          legacy.CCRouterRuntime.forTesting(traceCapacity: 0, diagnostics: config(0)),
          CCRouterRuntime.forTesting(traceCapacity: 0, diagnostics: config(1)),
        ];
        for (final runtime in runtimes) {
          runtime.registerCommand<_Command, void>((_, _) {});
          runtime.initialize();
        }
        final commandCpu = [0.0, 0.0], totalCpu = [0.0, 0.0];
        final commandWall = [0, 0], totalWall = [0, 0];
        for (var index = 0; index < commands; index += 64) {
          // Adjacent small batches share scheduling and frequency conditions;
          // reverse order on each batch and round to avoid first-run bias.
          for (final variant in ((index ~/ 64) + round).isEven ? [0, 1] : [1, 0]) {
            final dynamic runtime = runtimes[variant];
            final totalStart = cpu?.microseconds;
            final total = Stopwatch()..start();
            final command = Stopwatch()..start();
            final commandStart = cpu?.microseconds;
            for (var j = index; j < index + 64 && j < commands; j++) {
              await runtime.command(const _Command());
            }
            if (commandStart != null) commandCpu[variant] += cpu!.microseconds - commandStart;
            command.stop();
            await Future<void>.delayed(Duration.zero);
            total.stop();
            if (totalStart != null) totalCpu[variant] += cpu!.microseconds - totalStart;
            commandWall[variant] += command.elapsedMicroseconds;
            totalWall[variant] += total.elapsedMicroseconds;
          }
        }
        for (var variant = 0; variant < 2; variant++) {
          final sink = sinks[variant];
          if (sink != null && sink.count != commands) throw StateError('Lost events: ${sink.count}');
          if (round > 1) {
            (runs[variant]['samples'] as List<Map<String, Object>>).add({
              'round': round, 'mode': mode,
              'commandUsPerEvent': commandWall[variant] / commands,
              'deliveryUsPerEvent': totalWall[variant] / commands,
              if (cpu != null) 'commandCpuUsPerEvent': commandCpu[variant] / commands,
              if (cpu != null) 'deliveryCpuUsPerEvent': totalCpu[variant] / commands,
            });
          }
          await runtimes[variant].dispose();
        }
      }
    }
  } finally { cpu?.dispose(); }
  print(jsonEncode({'runs': runs}));
}
""" + helpers
    entry = work / "compare.dart"
    entry.write_text(source)
    executable = work / "compare"
    subprocess.run(
        ["fvm", "dart", "compile", "exe", str(entry),
         "--packages=" + str(config_path), "-o", str(executable)],
        cwd=root, check=True,
    )
    result = json.loads(subprocess.check_output([str(executable)], text=True))
    summary = {}
    for mode in ["off", "sync", "future"]:
        summary[mode] = {}
        for variant in ["before", "after"]:
            samples = [sample for run in result["runs"] if run["label"] == variant
                       for sample in run["samples"] if sample["mode"] == mode]
            keys = [key for key in samples[0] if key.endswith("UsPerEvent")]
            summary[mode][variant] = {
                key: statistics.median(sample[key] for sample in samples) for key in keys
            }
        for key in keys:
            summary[mode][key + "ChangePercent"] = (
                summary[mode]["after"][key] / summary[mode]["before"][key] - 1
            ) * 100
    result.update(**provenance, platform=platform.platform(),
                  method="same-process AOT Core libraries alternating adjacent 64-command batches; common contracts; dynamic Runtime dispatch on both paths",
                  measuredRounds=49, batchSize=64, samplesPerModePerVariant=49, summary=summary)
    Path(output).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    print("Sources and executable: " + str(work))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    references = parser.add_mutually_exclusive_group(required=True)
    references.add_argument("--reference", help="Git baseline commit")
    references.add_argument("--reference-core", help="Saved uncommitted Core package baseline")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    compare(args.reference, args.output, args.reference_core)
