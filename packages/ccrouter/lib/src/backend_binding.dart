part of 'facade.dart';

/// Provisional or committed ownership shared by every default Host entry point.
/// Registered before external callbacks so shutdown can claim cleanup even if
/// attachment is interrupted. Never exported to application or component code.
final class _CCNavigationAdapterAttachment {
  /// Captures exact identities and optional Backend cleanup for this attempt.
  _CCNavigationAdapterAttachment({
    required this.adapter,
    this.backend,
    this.disposeBackend,
  });

  /// Adapter exclusively reserved for this Runtime generation.
  final CCNavigationAdapter adapter;

  /// Managed Backend identity, absent for a direct HostBinding attachment.
  final CCRouterAppBackend? backend;

  /// Releases Backend resources after Runtime-owned Adapter cleanup.
  final Future<void> Function()? disposeBackend;

  /// Whether shutdown has taken responsibility for this attempt's resources.
  bool claimedByShutdown = false;

  /// Whether Runtime has provisionally adopted the Adapter for attachment.
  bool enteredRuntime = false;

  /// Releases reserved resources after Runtime cleanup, including an Adapter
  /// interrupted during catalog validation before Runtime could adopt it.
  Future<void> disposeAfterRuntime() async {
    Object? adapterError;
    StackTrace? adapterStack;
    if (!enteredRuntime) {
      try {
        adapter.dispose();
      } catch (error, stack) {
        adapterError = error;
        adapterStack = stack;
      }
    }
    try {
      await disposeBackend?.call();
    } catch (_) {
      if (adapterError == null) rethrow;
    }
    if (adapterError != null) {
      Error.throwWithStackTrace(adapterError, adapterStack!);
    }
  }
}

/// Reserves cleanup before validation/Adapter callbacks and commits only while
/// the original Runtime is active. Ordinary failures return ownership to the
/// caller; shutdown interruptions retain ownership in that cleanup generation.
void _attachNavigationAdapter(
  _CCNavigationAdapterAttachment attachment, {
  void Function()? beforeAttach,
}) {
  if (_runtimeResolver.hasOverlayRuntime) {
    throw const CCNavigationAdapterError(
      'A test Runtime receives its Adapter from CCRouterTestHost.',
    );
  }
  if (_CCRouterBackendBinding._rejectedAttachments.any(
        (reserved) => identical(reserved.adapter, attachment.adapter),
      ) ||
      CCRouterHost._navigationAttachment != null) {
    throw const CCNavigationAdapterError(
      'A navigation Backend is already bound to CCRouter.',
    );
  }
  final runtime = CCRouter._runtime;
  CCRouterHost._navigationAttachment = attachment;
  try {
    beforeAttach?.call();
    if (!runtime.isInitialized ||
        !identical(_runtimeResolver.defaultRuntime, runtime)) {
      throw const CCNavigationAdapterError(
        'Navigation attachment was interrupted.',
      );
    }
    attachment.enteredRuntime = true;
    runtime.attachNavigationAdapter(attachment.adapter);
    if (!runtime.isInitialized ||
        !identical(_runtimeResolver.defaultRuntime, runtime)) {
      throw const CCNavigationAdapterError(
        'Navigation attachment was interrupted.',
      );
    }
  } catch (_) {
    if (!attachment.claimedByShutdown &&
        identical(CCRouterHost._navigationAttachment, attachment)) {
      CCRouterHost._navigationAttachment = null;
    }
    rethrow;
  }
}

/// Internal coordinator that transfers one Backend into an initialized Runtime.
///
/// [CCRouterApp.managed] is the only public managed-binding entry. Keeping this
/// coordinator private prevents Hosts from attaching a Backend without mounting
/// its lifecycle scope, while preserving catalog validation and ordered cleanup.
abstract final class _CCRouterBackendBinding {
  /// Keeps rejected identities reserved through synchronous and async cleanup.
  /// Independent resources may attach while an old rejection finishes cleanup.
  static final Set<_CCNavigationAdapterAttachment> _rejectedAttachments = {};

  /// Attaches [backend] to the explicitly initialized default Runtime.
  ///
  /// The application must call `CCRouterHost.initialize` with its component
  /// manifests first. On success the Runtime owns the Adapter, and
  /// `CCRouterHost.shutdown` later disposes the Adapter before invoking
  /// [CCRouterAppBackend.dispose]. A rejected Adapter is disposed synchronously
  /// before the error is rethrown; asynchronous Backend resource cleanup is
  /// scheduled separately and reports failures through Flutter diagnostics.
  /// Active or still-cleaning Backend/Adapter aliases never transfer ownership
  /// to this call and are rejected without cleanup, preserving their owner.
  /// TestHost overlays are rejected before ownership transfer; even independent
  /// supplied Backend resources remain with the caller in that unsupported path.
  /// If shutdown interrupts attachment, that shutdown keeps cleanup ownership
  /// instead of taking the ordinary rejected-Backend disposal path.
  /// [mountHost] participates after ownership reservation and before catalog
  /// validation; its caller rolls back any partially acquired mount on failure.
  static void attach({
    required CCRouterAppBackend backend,
    required void Function() mountHost,
  }) {
    // An overlay owns its Adapter independently of the default Host ledger.
    // Reject before adopting any resources; the caller retains this Backend.
    if (_runtimeResolver.hasOverlayRuntime) {
      throw const CCNavigationAdapterError(
        'A test Runtime receives its Adapter from CCRouterTestHost.',
      );
    }
    // Read external SPI once, then inspect ownership: the getter may reenter.
    final adapter = backend.navigationAdapter;
    if (_rejectedAttachments.any(
      (reserved) =>
          identical(reserved.backend, backend) ||
          identical(reserved.adapter, adapter),
    )) {
      throw const CCNavigationAdapterError(
        'The navigation Backend is still being disposed.',
      );
    }
    final active = CCRouterHost._navigationAttachment;
    if (active != null) {
      if (!identical(active.backend, backend) &&
          !identical(active.adapter, adapter)) {
        _disposeRejectedBackend(backend, adapter);
      }
      throw const CCNavigationAdapterError(
        'A navigation Backend is already attached to CCRouter.',
      );
    }
    _attachAndOwn(backend, adapter, mountHost);
  }

  /// Transfers the captured Adapter and registers Backend cleanup with shutdown.
  static void _attachAndOwn(
    CCRouterAppBackend backend,
    CCNavigationAdapter adapter,
    void Function() mountHost,
  ) {
    final attachment = _CCNavigationAdapterAttachment(
      adapter: adapter,
      backend: backend,
      disposeBackend: backend.dispose,
    );
    try {
      _attachNavigationAdapter(
        attachment,
        beforeAttach: () {
          // Reserve Adapter ownership before mounting so mount rejection and
          // validation failures share the same alias-safe cleanup transaction.
          mountHost();
          final catalog = backend.routeCatalog;
          if (attachment.claimedByShutdown) {
            throw const CCNavigationAdapterError(
              'Navigation attachment was interrupted.',
            );
          }
          _validateRouteCatalog(catalog);
        },
      );
    } catch (error, stackTrace) {
      if (!attachment.claimedByShutdown)
        _disposeRejectedBackend(backend, adapter);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Rejects a Backend assembled from a different component catalog.
  static void _validateRouteCatalog(CCFlutterRouteCatalog routeCatalog) {
    final registered = <String, String>{
      for (final component in CCRouter.registeredComponents)
        component.id: component.version,
    };
    final generated = routeCatalog.componentVersions;
    if (registered.length != generated.length ||
        registered.entries.any(
          (entry) => generated[entry.key] != entry.value,
        )) {
      throw const CCRegistrationError(
        'The navigation Backend component catalog does not match the '
        'registered Runtime components.',
      );
    }
  }

  /// Releases a rejected Backend using the same Adapter identity as preflight.
  static void _disposeRejectedBackend(
    CCRouterAppBackend backend,
    CCNavigationAdapter adapter,
  ) {
    final reservation = _CCNavigationAdapterAttachment(
      adapter: adapter,
      backend: backend,
    );
    _rejectedAttachments.add(reservation);
    try {
      reservation.adapter.dispose();
    } catch (error, stackTrace) {
      _reportDisposalError(
        error,
        stackTrace,
        'while disposing a rejected CCRouter navigation Adapter',
      );
    }
    unawaited(_disposeRejectedBackendResources(backend, reservation));
  }

  /// Releases asynchronous Backend resources after synchronous rejection.
  static Future<void> _disposeRejectedBackendResources(
    CCRouterAppBackend backend,
    _CCNavigationAdapterAttachment reservation,
  ) async {
    try {
      await backend.dispose();
    } catch (error, stackTrace) {
      _reportDisposalError(
        error,
        stackTrace,
        'while disposing a rejected CCRouter application backend',
      );
    } finally {
      _rejectedAttachments.remove(reservation);
    }
  }

  /// Reports a cleanup failure without replacing the attachment failure.
  static void _reportDisposalError(
    Object error,
    StackTrace stackTrace,
    String context,
  ) {
    try {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'ccrouter',
          context: ErrorDescription(context),
        ),
      );
    } catch (_) {
      // An external diagnostics handler cannot interrupt owned cleanup.
    }
  }
}
