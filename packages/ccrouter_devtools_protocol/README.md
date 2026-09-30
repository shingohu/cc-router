# ccrouter_devtools_protocol

Pure Dart, versioned, read-only snapshot protocol shared by CCRouter Hosts,
embedded diagnostics, and the official DevTools Extension.

The protocol carries sanitized immutable Catalog, Runtime, and Trace Edge data.
It intentionally excludes Widgets, Navigator objects, full URIs, route
arguments, tokens, exceptions, and business results.

Applications normally use `ccrouter_devtools` rather than this protocol package
directly. See the
[DevTools guide](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-devtools.md).
