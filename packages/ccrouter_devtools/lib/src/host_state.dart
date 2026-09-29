import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';

/// Process-local state owned by the generated DevTools Host integration.
///
/// The type is intentionally not exported. It holds only an immutable static
/// Catalog and is cleared before the default Runtime starts disposing.
final class CCDevToolsHostState {
  /// Prevents construction of the process-local state namespace.
  CCDevToolsHostState._();

  /// Static Catalog associated with the active default Runtime.
  static CCDevToolsStaticCatalogSnapshot? catalog;
}
