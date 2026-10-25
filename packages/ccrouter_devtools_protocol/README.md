# ccrouter_devtools_protocol

Pure Dart, versioned, read-only snapshot protocol shared by CCRouter Hosts,
embedded diagnostics, and the official DevTools Extension.

The protocol carries sanitized immutable Catalog, Runtime, and Trace Edge data.
It intentionally excludes Widgets, Navigator objects, full URIs, route
arguments, tokens, exceptions, and business results.
Protocol v1 adds optional fixed-field Failure/Fallback/Pending/InitTask records
and history/Sink health, including optional `diagnosticHealth.runtimeHealth`
navigation counters. `trackedNavigationHosts` counts captured lifetimes, not all
Adapter registrations; readers accept the former `registeredHosts` key with the
same meaning. In-flight counts represent concurrency gates, not every navigation.
Absent extension fields remain null (unsupported),
not empty/zero; malformed present fields fail decoding. Recovery selection does
not promise later success, and history omissions are independent of Sink loss.

Applications normally use `ccrouter_devtools` rather than this protocol package
directly. See the
[DevTools guide](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-devtools.md).
