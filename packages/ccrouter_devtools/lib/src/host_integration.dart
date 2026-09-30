import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';
import 'package:flutter/foundation.dart';

import 'service_extension.dart';
import 'snapshot_provider.dart';

/// Generated Host integration for the read-only CCRouter DevTools endpoint.
///
/// Applications do not construct this object manually. `ccrouter generate`
/// adds it to [CCHostAssembly] only when the Host Package directly
/// depends on `ccrouter_devtools`. Debug builds enable it by default, Profile
/// builds require `--dart-define=CCROUTER_DEVTOOLS=true`, and Release builds
/// always keep it disabled.
final class CCDevToolsHostIntegration implements CCHostToolIntegration {
  /// Creates an integration over one immutable generated [catalog].
  const CCDevToolsHostIntegration({required this.catalog});

  /// Static source and dependency index generated for the owning Host.
  final CCDevToolsStaticCatalogSnapshot catalog;

  @override
  /// Stable identity used by generated Host assembly and diagnostics.
  String get id => 'ccrouter.devtools';

  /// Whether the current build is allowed to expose the VM Service endpoint.
  bool get isEnabled =>
      !kReleaseMode &&
      const bool.fromEnvironment('CCROUTER_DEVTOOLS', defaultValue: kDebugMode);

  @override
  /// Registers or refreshes the endpoint after Runtime installation.
  void onRuntimeReady() {
    if (!isEnabled) {
      CCDevToolsServiceExtension.clear();
      return;
    }
    CCDevToolsServiceExtension.register(
      provider: const CCRouterDevToolsSnapshotProvider(),
      catalog: catalog,
    );
  }

  @override
  /// Clears retained Provider and Catalog state before Runtime disposal.
  void onRuntimeStopping() => CCDevToolsServiceExtension.clear();
}
