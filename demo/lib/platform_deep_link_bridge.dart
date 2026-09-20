import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:ccrouter/ccrouter.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:flutter/widgets.dart';

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
      demoNavigationLabStore.record(
        'Platform Deep Link received · scheme=${uri.scheme} · '
        'host=${uri.host.isEmpty ? '-' : uri.host}',
      );
      try {
        await CCDeepLinkIngress.fromPlatform(
          uri,
          source: const CCNavigationSource.deepLink('platform.app_link'),
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
