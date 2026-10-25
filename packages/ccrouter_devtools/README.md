# ccrouter_devtools

Optional read-only Flutter diagnostics UI for a CCRouter Host. It displays
sanitized static Catalog and bounded Runtime snapshots, component relationships,
Route/Backend entries, failures, InitTask state, and a single trace call chain.
Overview shows bounded history completeness, external Sink delivery health and
optional Runtime navigation health (Entry, captured Host lifetime, concurrency
gate and observer queue counts). Counts do not prove resource leaks or expose
controls; missing producer support remains unavailable rather than zero.
While subscribed the default Provider compares lightweight state every 250ms;
full histories refresh only on changes, including non-navigation work and Runtime
restart. The panel unsubscribes when TickerMode is disabled or it is disposed.

The panel cannot navigate, retry work, dispose scopes, activate components, or
control an Adapter. Keep it behind the documented Debug/Profile gate; Release
builds must not expose the service extension.

See the
[DevTools guide](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-devtools.md)
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
