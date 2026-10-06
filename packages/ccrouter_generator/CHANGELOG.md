# Changelog

## 0.1.0 - Unreleased

- Preparing the first public release of CCRouter generation and CLI tooling.
- Fixed clean Workspace and SDK-switch generation by rebuilding a missing
  build_runner executable snapshot through Pub and retrying once after Dart
  reports `Wrong full snapshot version`, instead of leaving generation on the
  slower source entrypoint.
- Simplified internal capability scaffolds: Services no longer create a
  redundant Contract, while Event Subscribers and reusable InitTask Contracts
  are explicit opt-ins.
- Added a schema-versioned `--profile` phase trace, atomic local latest report,
  build-target and per-Package dirty-reason diagnostics, and build_runner
  `--verbose-durations` forwarding without changing generation or cache
  invalidation behavior.
- Made detailed profiling opt-in for direct generation, Pub Hook preflight, and
  watch cycles. Default output retains only the final elapsed time; benchmarks
  and diagnostic agents can request the complete trace with `--profile`.
- Added `generate --watch=auto --machine`, a single-build-root build_runner
  watch path with NDJSON events, generation locking, artifact rollback, an
  emergency kill switch, and a Flutter-run lifecycle lease.
- Added atomically published local watch status plus read-only `watch status`
  and `watch follow` commands. Flutter-run hooks print the status and log paths
  without mixing watch NDJSON into Flutter Tool's machine stdout; status
  publication remains fail-open and cannot fail generation.
- Added a narrow stdin-only gate for Hook-started `flutter run --machine`.
  IDE reload requests now wait for a stable watch input revision, surface
  Generator failures as daemon errors, and require Hot Restart after Host
  topology changes. `CCROUTER_DISABLE_HOT_RELOAD_GATE=1` restores direct
  machine input forwarding.
- Added a Windows Flutter-run supervisor with a versioned watch-lease
  heartbeat. Handled exits clean up immediately, while watch expires an orphaned
  lease after an uncatchable supervisor termination.
- Made POSIX and Windows Pub Hook wrappers locate real Flutter/Dart commands by
  global-option arity instead of matching command-like text in arbitrary
  option values, script arguments, or trailing business arguments.
- Bounded build_runner watch shutdown through SIGINT, SIGTERM, and final
  SIGKILL stages so a stuck child cannot block session restart indefinitely.
- Routed the successful Flutter-run watch start summary through stdout like
  preflight success, while retaining real hook failures on stderr so IDEs do
  not render a healthy background watch as an error.
- Coordinated post-pub generation with an already active same-Host watch. The
  Hook now waits for aggregation proven against the exact current Pub
  resolution inputs and surfaces bounded Builder/validation diagnostics on
  failure instead of reporting only a generation-lock conflict.
- Added diagnostic-only structured build_runner phase, activity, execution,
  and invalidation counters to watch build events and the real-edit benchmark.
  Unknown upstream formats remain bounded raw diagnostics and never affect
  generation decisions.
- Removed redundant fast-path and Build Plan inspection after a successful
  watch Builder cycle while retaining all validation and input barriers; added
  `CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION` for reference-path comparison.
- One-shot generation, check, and clean commands now fail with an actionable
  diagnostic instead of waiting indefinitely behind an active root watch;
  watch startup also fails fast while a one-shot command owns or awaits the
  root generation lock.
- Watch aggregation cycles now execute through the generator kernel in process,
  avoiding a fresh Dart/generator startup after every successful Builder cycle.
  `CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE=1` restores the subprocess reference
  path for byte-for-byte and timing comparisons.
- Reused one exact-content planning snapshot when publishing the local fast-path
  manifest and Build Plan state, removing duplicate cycle-end scans while
  retaining atomic writes and all input barriers. Set
  `CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT=1` for the reference path.
- Reused the final watch input-barrier snapshot when publishing local planning
  state and, on a verified aggregation hit, reused only aggregation-owned entry
  bytes while rereading current Builder outputs. Profile traces report the
  evidence mode; `CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE=1` restores recapture.
- Reused the exact current managed-output bytes already read by the watch
  output-delta scan when publishing planning state. Set
  `CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE=1` to retain delta reporting
  while restoring the separate planning output scan for isolated A/B.
- Added a diagnostic-only aggregation-input fingerprint to profile traces and
  watch benchmarks, then used the proven identity only after Builder completes
  to reuse verified aggregation outputs. The local proof also checks exact
  output bytes, reuses existing cycle snapshots instead of rescanning, retains
  validation and input barriers, and fails closed behind
  `CCROUTER_DISABLE_AGGREGATION_REUSE=1` and `--no-cache --check` references.
