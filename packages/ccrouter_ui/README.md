# ccrouter_ui

Optional typed local UI composition for CCRouter. Public Pure Dart contracts
live in `ccrouter_contracts/ccrouter_ui_contracts.dart`; implementations return
ordinary Flutter widgets and consumers call their generated UI Client.

Import `ccrouter_ui.dart` in component code. `ccrouter_ui_host.dart` belongs to
the application Composition Root; `ccrouter_ui_generated.dart` is generated
SPI. This package creates no RouteEntry, navigation stack or Fragment Scope.

See [integration guidance](../../skills/ccrouter-integration-development/references/ui-fragments.md)
and the [design and implementation record](../../docs/CCRouter-ui-fragment-design.md).
