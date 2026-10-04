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
