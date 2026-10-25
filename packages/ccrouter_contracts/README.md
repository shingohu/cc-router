# ccrouter_contracts

Pure Dart contracts and immutable value types shared by CCRouter packages and
independent component contract packages. It contains Route, Service, Command,
Event, InitTask, diagnostics, lifecycle, and navigation backend contracts.
Failure and Pending snapshots retain optional Host/Outlet attribution; structured
diagnostic events expose fixed failure reason, attempt and recovery depth without
arbitrary business cancellation codes or exception messages.

Use this package when a contracts-only package must stay independent from
Flutter and implementation packages. Application feature code should normally
depend on `ccrouter` instead.

Optional typed local UI declarations have a separate Pure Dart entry point,
`package:ccrouter_contracts/ccrouter_ui_contracts.dart`. It provides
`CCUIFragmentContract`, `CCUIFragmentDependency`, and `CCUIFragmentRenderer`;
`CCComponent.uiDependencies` records required UI consumption. Props use immutable
DTOs; Actions use plain enums, restricted immutable DTOs or restricted sealed
unions, including nested union payloads. Props remain DTO-only. Scalar types
are supported only as DTO fields, not as root Actions. DTO Actions
require UI schema 2 / Package Index schema 4 compatible tooling; union Actions
require UI schema 3 / Package Index schema 5. Union roots directly extend Object,
with public final direct leaves in the same library/parts, inherited final data
and const super.field forwarding. Export all variants and nested types. Rendering
and Host assembly require the separate Flutter package `ccrouter_ui`; these
declarations do not create another navigation Contract kind or relax Service
types. See the [UI integration guide](../../skills/ccrouter-integration-development/references/ui-fragments.md).

The package does not provide a Runtime or a navigation backend. See the
[architecture documentation](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-v0.1-architecture.md)
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
