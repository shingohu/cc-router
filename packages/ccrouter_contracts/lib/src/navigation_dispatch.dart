import 'navigation.dart';

/// Host-only receipt for a navigation transaction already committed by a backend.
///
/// Returning this value confirms synchronous acceptance; rejection must throw
/// before returning, without changing the backend stack. [result] is the later
/// Pop result for Push/Replace and must not represent a delayed acceptance.
/// Keeping these two phases separate lets Runtime reconcile Entries without
/// guessing whether an unfinished result Future means rejection or an open page.
final class CCNavigationDispatch {
  /// Creates a receipt after the backend transaction has committed.
  const CCNavigationDispatch({required this.result});

  /// Eventual navigation result, independent of the already-confirmed commit.
  final Future<Object?> result;
}

/// Optional Host/Adapter SPI proving synchronous navigation acceptance.
///
/// Identity-sensitive revalidation Replace requires this capability. Legacy
/// [CCNavigationAdapter.navigate] remains available for ordinary navigation.
/// An asynchronous backend must prepare resources before dispatch and cannot
/// opt in by simply wrapping an acceptance Future in [CCNavigationDispatch].
abstract interface class CCNavigationDispatchAdapter {
  /// Commits [request] atomically and returns its receipt, or throws on rejection.
  ///
  /// A multiplexer may return null when its selected child lacks this capability;
  /// null must leave backend state unchanged. Implementations must not dispatch
  /// twice, and must release pending result channels when disposed.
  CCNavigationDispatch? dispatchNavigation(CCNavigationRequest request);
}

/// Optional Host SPI opting into Runtime-validated declarative parent plans.
///
/// Opted-in Backends must validate and install `request.parentStack` and the
/// leaf in one synchronous transaction, rejecting before any mutation. Legacy
/// routers that construct their own hierarchy must not implement this SPI.
abstract interface class CCNavigationParentStackAdapter {
  /// Whether this exact Host supports plans for Go, Reset and Open in Go mode.
  ///
  /// A multiplexer queries its selected child without changing active focus.
  bool supportsParentStack(CCNavigationRequest request);
}
