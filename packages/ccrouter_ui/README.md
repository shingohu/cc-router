# ccrouter_ui

Optional typed local UI composition for CCRouter. Public Pure Dart contracts
live in `ccrouter_contracts/ccrouter_ui_contracts.dart`; implementations return
ordinary Flutter widgets and consumers call their generated UI Client.

Import `ccrouter_ui.dart` in component code. `ccrouter_ui_host.dart` belongs to
the application Composition Root; `ccrouter_ui_generated.dart` is generated
SPI. This package creates no RouteEntry, navigation stack or Fragment Scope.

Props are restricted immutable DTOs. Actions may be plain enums, restricted
immutable DTOs or restricted sealed unions, including nested union payloads.
Props remain DTO-only; scalar types are supported only as data fields.
Union Actions require UI schema 3 / Package Index schema 5 with matching tooling.
DTO Actions without unions need UI schema 2 / Package Index 4 compatible tooling. Flutter State owns instance
resources; `active: false` suppresses Actions, while pausing work and Session
reset remain application responsibilities. Runtime shutdown invalidates old
callbacks, and reinitialization requires an explicit UI subtree remount.
Contract version snapshots must match exactly. Schema/version/range changes
revoke retained sinks before rebuild validation; restoring valid glue creates
a new sink rather than reviving an old callback.

See [integration guidance](../../skills/ccrouter-integration-development/references/ui-fragments.md)
and the [design and implementation record](../../docs/CCRouter-ui-fragment-design.md).
The [independent enum/DTO validation](../../docs/validation/ui-fragment-adoption-20261020/README.md)
documents a verified local technical workflow. It does not establish final API
freeze, human onboarding usability, distribution readiness or device coverage.
