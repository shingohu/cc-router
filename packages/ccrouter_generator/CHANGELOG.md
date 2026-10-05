# Changelog

## 0.1.0 - Unreleased

- Preparing the first public release of CCRouter generation and CLI tooling.
- Simplified internal capability scaffolds: Services no longer create a
  redundant Contract, while Event Subscribers and reusable InitTask Contracts
  are explicit opt-ins.
- Added a schema-versioned `--profile` phase trace, atomic local latest report,
  build-target and per-Package dirty-reason diagnostics, and build_runner
  `--verbose-durations` forwarding without changing generation or cache
  invalidation behavior.
- Added `generate --watch=auto --machine`, a single-build-root build_runner
  watch path with NDJSON events, generation locking, artifact rollback, an
  emergency kill switch, and a Flutter-run lifecycle lease.
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
- Added a diagnostic-only aggregation-input fingerprint to profile traces and
  watch benchmarks. It distinguishes unchanged Builder/Host aggregation inputs
  without yet authorizing any aggregation skip or cache decision.
