# Changelog

## 0.1.0 - Unreleased

- Accept immutable final DTO UI Actions, reject proven non-data/behavioral shapes,
  and preserve required UI Owner checks for mixed UI schema 2 metadata.
  Full constructor/default schema and export validation remain Generator-owned.

- Restore missing UI Owner diagnostics and Quick Fixes for resolved typedef
  constructors; distinguish part source locations from defining-library identity
  in regenerated UI metadata without weakening exact Contract matching.

- Fix UI constructor identity checks so ordinary factory functions cannot receive
  invalid dependency fixes; preserve same-name Contract Owners in separate
  libraries and reject nested Renderer functions.
- Add conservative UI Fragment alias, dependency, Action, Renderer and SPI
  diagnostics with canonical symbol identity and incomplete-buffer deferral.
- Include UI Owner metadata in the required-dependency diagnostic and safe
  imported-constant Quick Fix; legacy metadata without identity defers.
- Consume structured UI Host failures through the existing validated Generator
  snapshot bridge without adding generation or another Analyzer session.

- Preparing the first public release of CCRouter Analysis Server diagnostics.
- Added Metadata-driven missing Service/Command owner diagnostics and a
  conservative required-dependency Quick Fix for directly editable lists.
- Aligned Package role and Workspace resolution hints with Generator semantics,
  including package-local/Pure Dart guidance without an active watch.
- Publish and clear Pub-resolution drift hints for explicit Workspace members,
  including members analyzed through a shared Workspace context.
- Consume exact-resolution structured diagnostics from an active Generator
  watch or the latest eligible Host one-shot result. Stale, mismatched, and
  superseded snapshots remain fail-open and never replace generation checks.
- Refresh authored diagnostics after generated metadata, Package role, or
  Workspace resolution changes through bounded filesystem identity indexes,
  without opening a second Analyzer graph or requiring an Analysis Server
  restart for ordinary source changes.
