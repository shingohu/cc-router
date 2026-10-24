# ccrouter_core

Pure Dart CCRouter Runtime implementation. It owns component registration,
dependency validation, scopes, typed capability dispatch, navigation policy,
bounded diagnostics, and lifecycle cleanup.
Payload-free diagnostic health reports history omissions separately from external
Sink delivery; reading it does not copy histories or create a subscription.

This is an implementation dependency of the Flutter facade, not the normal
business API. Applications and components should import `package:ccrouter/ccrouter.dart`
and must not import `ccrouter_core/src/*`.

See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md)
for supported public entry points and the
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md)
for publication status.
