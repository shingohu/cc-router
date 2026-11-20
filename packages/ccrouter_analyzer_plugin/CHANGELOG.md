# Changelog

## 0.1.0 - Unreleased

- Resolve UI-only Contract/Renderer buffers and UI SPI references through the
  current Analysis Server session, reusing annotation identity markers. Keep
  conservative symbol proofs and unchanged isolated Analyzer constraints.
- Add a real LSP imported-Owner/unsaved-repair regression and a maintainer check
  of actual Analyzer 13 Generator metadata consumed by the Analyzer 8.4 Plugin,
  including Owner library identity, diagnostic spans and Quick Fix application.

- Prove Host/UI SPI library identity through the configured SDK for URI/symlink aliases, check Host named types/typedef references, and apply effective show/hide visibility without reporting excluded names. Analyze standalone typed UI/Renderer sources through the existing session.

- Enforce generated internal API boundaries for Dart-supported file/query URI spellings and import-target symlinks. Borrow the existing SDK URI converter for Package aliases and conditional branches without requesting full type resolution for plain imports.

- Respect conditional imports, part namespaces and Contract show/hide/local shadowing before parser-only Owner diagnostics or fixes. Match exact defining Libraries through real import/export paths.

- Require complete parser-only Owner namespace proof, including named-extension shadowing and unknown conditional/missing exports. Reject malformed/escaping URI evidence without crashes and preserve valid encoded source filenames in bridged diagnostics.

- Key Owner records by exact defining Library and source, including same-name Core Contracts and shared named UI parts. Validate portable Core/UI identity URIs and refresh both part and Library evidence.

- Prove SDK Duration and framework Gate identity before literal checks; avoid
  shadowed zero false positives and support resolved constructor aliases.

- Align argument conflicts and Quick Fixes on one private rule set: null/empty Route defaults and null InitTask identities are inactive; unknown nullable references defer. Preserve the internal Quick Fix import while sharing implementation with source diagnostics.

- Preserve Component ID identity through resolved typedefs/prefixes and const string arguments; defer unproven consumer IDs. Prove parser-only exported Owner constants and validate adjacent literal strings consistently.

- Prevent self-Owner dependency edits for Service/Command/UI, including proven imported
  component-ID constants. Reuse canonical constructor proof for parser-only prefixed
  Component fixes and remove the duplicate constructor parser.

- Unify Service/Command/UI Owner constructor proofs and resolved typedef handling. Defer stale Owner diagnostics/fixes when current Contract annotations are missing, duplicated, foreign or changed.

- Diagnose literal Service/Command Dependency aliases with `ccrouter_alias_invalid`, preserving constructor identity checks and conservative expression deferral.

- Add optional Event Contract alias with legacy default-name compatibility,
  generated Client collision checks and reserved-name diagnostics.

- Reject Object-member aliases on Service/Command/UI Contracts with shared Plugin naming validation; preserve conservative handling of computed expressions.

- Include Contract and inferred defaults in UI alias validation and collisions.
  Remove the obsolete UI version-range diagnostic; dependencies no longer expose
  a version-range argument.

- Check every conditional import/export URI for cross-Package generated internals.
  Diagnose literal Route/Contract placement IDs, self-parent and invalid/repeated
  policy IDs with canonical identity and conservative expression deferral.

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
