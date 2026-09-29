/// Read-only Flutter diagnostics for CCRouter Hosts.
///
/// This optional package provides an embeddable panel for development builds.
/// It observes bounded, sanitized CCRouter snapshots and never exposes a
/// Navigator, Runtime, Route Scope, or mutating control.
library;

export 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';
export 'src/devtools_panel.dart';
export 'src/host_integration.dart';
export 'src/snapshot.dart';
export 'src/snapshot_provider.dart';
export 'src/service_extension.dart';
