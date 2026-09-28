import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';

import 'snapshot_provider.dart';

/// VM Service method used by the official DevTools extension.
const ccRouterDevToolsSnapshotExtension = 'ext.ccrouter.snapshot';

/// Registers a read-only VM Service snapshot endpoint for DevTools.
///
/// The registration is application-owned and optional. Calling [register]
/// more than once updates the provider and Catalog used by the existing
/// handler; it never creates a second endpoint. The endpoint only returns a
/// sanitized [CCDevToolsSnapshotEnvelope]. It cannot navigate, retry work,
/// dispose scopes, or mutate an Adapter. The VM Service registration itself
/// cannot be removed, so [clear] only makes later calls return an uninitialized
/// envelope and should be used when the owning debug Host is torn down.
final class CCDevToolsServiceExtension {
  CCDevToolsServiceExtension._();

  static CCDevToolsSnapshotProvider? _provider;
  static CCDevToolsStaticCatalogSnapshot? _catalog;
  static bool _registered = false;
  static bool _enabled = true;

  /// Installs or updates the read-only snapshot provider.
  ///
  /// Call this from a debug-only Host composition root after Runtime and
  /// generated Catalog setup. Release builds may omit the call entirely.
  static void register({
    required CCDevToolsSnapshotProvider provider,
    CCDevToolsStaticCatalogSnapshot? catalog,
  }) {
    _provider = provider;
    _catalog = catalog;
    _enabled = true;
    if (_registered) return;
    developer.registerExtension(
      ccRouterDevToolsSnapshotExtension,
      (method, _) async =>
          developer.ServiceExtensionResponse.result(_encodeCurrentSnapshot()),
    );
    _registered = true;
  }

  /// Disables payload delivery after the owning debug Host is torn down.
  ///
  /// Dart's VM Service API does not support unregistering a service extension,
  /// so the endpoint remains present but returns an uninitialized snapshot.
  static void clear() {
    _enabled = false;
    _provider = null;
    _catalog = null;
  }

  static String _encodeCurrentSnapshot() {
    final provider = _provider;
    final runtime = _enabled && provider != null
        ? provider.snapshot().toProtocolRuntimeSnapshot()
        : CCDevToolsRuntimeSnapshot(
            capturedAt: DateTime.now().toUtc(),
            runtimeState: 'uninitialized',
          );
    return jsonEncode(
      CCDevToolsSnapshotEnvelope(
        capturedAt: DateTime.now().toUtc(),
        catalog: _enabled ? _catalog : null,
        runtime: runtime,
      ).toJson(),
    );
  }
}
