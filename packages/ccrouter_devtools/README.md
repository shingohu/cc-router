# ccrouter_devtools

Optional read-only Flutter diagnostics UI for a CCRouter Host. It displays
sanitized static Catalog and bounded Runtime snapshots, component relationships,
Route/Backend entries, failures, InitTask state, and a single trace call chain.

The panel cannot navigate, retry work, dispose scopes, activate components, or
control an Adapter. Keep it behind the documented Debug/Profile gate; Release
builds must not expose the service extension.

See the
[DevTools guide](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-devtools.md)
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
