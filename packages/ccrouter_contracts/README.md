# ccrouter_contracts

Pure Dart contracts and immutable value types shared by CCRouter packages and
independent component contract packages. It contains Route, Service, Command,
Event, InitTask, diagnostics, lifecycle, and navigation backend contracts.

Use this package when a contracts-only package must stay independent from
Flutter and implementation packages. Application feature code should normally
depend on `ccrouter` instead.

The package does not provide a Runtime or a navigation backend. See the
[architecture documentation](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-v0.1-architecture.md)
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
