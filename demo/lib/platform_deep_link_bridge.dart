import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:ccrouter/ccrouter.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:demo_web_contracts/demo_web_contracts.dart';
import 'package:flutter/widgets.dart';

/// Host-owned external URI namespaces accepted by the demonstration app.
///
/// Relative Paths are enabled because the platform mapper converts validated
/// public Web URLs into `/web` and notifications may provide normalized paths.
final demoDeepLinkIngressPolicy = CCDeepLinkIngressPolicy(
  allowedAuthorities: [
    CCDeepLinkAuthorityRule(scheme: 'ccrouter', host: 'lab'),
    CCDeepLinkAuthorityRule(scheme: 'https', host: 'ccrouter.example'),
  ],
  allowRelativePaths: true,
);

final class DemoPlatformDeepLinkBridge extends StatefulWidget {
  const DemoPlatformDeepLinkBridge({
    required this.child,
    this.linkStream,
    super.key,
  });

  final Widget child;
  final Stream<Uri>? linkStream;

  @override
  State<DemoPlatformDeepLinkBridge> createState() =>
      _DemoPlatformDeepLinkBridgeState();
}

final class _DemoPlatformDeepLinkBridgeState
    extends State<DemoPlatformDeepLinkBridge> {
  final List<Uri> _pendingLinks = <Uri>[];
  Future<void> _dispatchQueue = Future<void>.value();
  StreamSubscription<Uri>? _subscription;
  bool _backendReady = false;

  @override
  void initState() {
    super.initState();
    _subscription = (widget.linkStream ?? AppLinks().uriLinkStream).listen(
      _receive,
      onError: (Object error, StackTrace stackTrace) {
        demoNavigationLabStore.record(
          'Platform Deep Link stream failed · ${error.runtimeType}',
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _backendReady = true;
      final queued = List<Uri>.of(_pendingLinks);
      _pendingLinks.clear();
      for (final uri in queued) {
        _dispatch(uri);
      }
    });
  }

  void _receive(Uri uri) {
    if (!_backendReady) {
      _pendingLinks.add(uri);
      return;
    }
    _dispatch(uri);
  }

  void _dispatch(Uri uri) {
    _dispatchQueue = _dispatchQueue.then((_) async {
      final mappedWebUri = demoMapExternalWebUri(uri);
      final ingressUri = mappedWebUri ?? uri;
      demoNavigationLabStore.record(
        'Platform Deep Link received · scheme=${uri.scheme} · '
        'host=${uri.host.isEmpty ? '-' : uri.host}',
      );
      try {
        await CCDeepLinkIngress.fromPlatform(
          ingressUri,
          source: CCNavigationSource.deepLink(
            mappedWebUri == null ? 'platform.app_link' : 'platform.web_link',
          ),
        );
        demoNavigationLabStore.record('Platform Deep Link dispatch complete');
      } on Object catch (error) {
        demoNavigationLabStore.record(
          'Platform Deep Link rejected · ${error.runtimeType}',
        );
      }
    });
  }

  @override
  void dispose() {
    _pendingLinks.clear();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
