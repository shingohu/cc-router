# ccrouter

Flutter-facing CCRouter facade for application and component code. It exposes
runtime initialization, typed navigation, Service/Command/Event access, page
lifecycle integration, and Host-facing assembly contracts.

Business code normally imports:

```dart
import 'package:ccrouter/ccrouter.dart';
```

Do not import `ccrouter_core/src/*` or use Runtime internals directly. Navigation
backends remain separate packages; use `ccrouter_go_router` from the application
Composition Root when GoRouter is the selected backend.

The package is currently pre-release and is not yet published. See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md)
for usage and the
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md)
for current publication blockers.
