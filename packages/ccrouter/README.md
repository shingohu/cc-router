# ccrouter

Flutter-facing CCRouter facade for application and component code. Its business
entry point exposes typed navigation, Service/Command/Event access, Session
operations, and page lifecycle integration.

Business code normally imports:

```dart
import 'package:ccrouter/ccrouter.dart';
```

The application Composition Root imports `ccrouter_host.dart` for
`CCRouterHost.initialize`, `shutdown`, `runInitTasks`, and `CCHostAssembly`.
These lifecycle entry points are absent from the business `CCRouter` facade;
feature components must not initialize or shut down the Runtime. Unmounting a
navigation Host does not shut down the shared Runtime.

Default Page/Dialog routes follow the nearest MaterialApp/CupertinoApp ancestor;
explicit route types take precedence. Optional Android predictive-back Host
wiring observes Flutter-owned animation and Pop. See the
[support and lifecycle guide](../../docs/CCRouter-predictive-back.md) for its
default-off switch, local gates, Theme constraints, and recovery behavior.
For typed cross-component local UI, opt in separately to `ccrouter_ui` and its
[integration guide](../../skills/ccrouter-integration-development/references/ui-fragments.md).

Do not import `ccrouter_core/src/*` or use Runtime internals directly. Navigation
backends remain separate packages; use `ccrouter_go_router` from the application
Composition Root when GoRouter is the selected backend.

The package is currently pre-release and is not yet published. See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md)
for usage and the
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md)
for current publication blockers.
