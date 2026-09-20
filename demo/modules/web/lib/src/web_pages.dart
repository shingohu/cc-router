import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_web_contracts/demo_web_contracts_owner.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

@CCRouteImplementation(DemoPublicWebRouteContract)
final class DemoPublicWebPage extends StatelessWidget {
  const DemoPublicWebPage({required this.target, super.key});

  final DemoPublicWebTarget target;

  @override
  Widget build(BuildContext context) => _DemoWebContainer(
    initialUri: target.uri,
    title: '公开 Web 页面',
    navigationPolicy: (uri) {
      try {
        DemoPublicWebTarget(uri);
        return true;
      } on ArgumentError {
        return false;
      }
    },
  );
}

@CCRouteImplementation(DemoPrivateWebRouteContract)
final class DemoPrivateWebPage extends StatelessWidget {
  const DemoPrivateWebPage(this.request, {super.key});

  final DemoPrivateWebRequest request;

  @override
  Widget build(BuildContext context) => _DemoWebContainer(
    initialUri: request.uri,
    title: '私密 Web 页面',
    headers: request.headers,
    javaScriptEnabled: request.javaScriptEnabled,
    navigationPolicy: (uri) =>
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.toLowerCase() == request.uri.host.toLowerCase() &&
        uri.userInfo.isEmpty,
  );
}

final class _DemoWebContainer extends StatefulWidget {
  const _DemoWebContainer({
    required this.initialUri,
    required this.title,
    required this.navigationPolicy,
    this.headers = const {},
    this.javaScriptEnabled = true,
  });

  final Uri initialUri;
  final String title;
  final Map<String, String> headers;
  final bool javaScriptEnabled;
  final bool Function(Uri uri) navigationPolicy;

  @override
  State<_DemoWebContainer> createState() => _DemoWebContainerState();
}

final class _DemoWebContainerState extends State<_DemoWebContainer> {
  WebViewController? _controller;
  Object? _platformError;
  int _progress = 0;
  String? _pageTitle;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(
        widget.javaScriptEnabled
            ? JavaScriptMode.unrestricted
            : JavaScriptMode.disabled,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageFinished: (_) => _refreshNavigationState(controller),
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null && widget.navigationPolicy(uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
      await controller.loadRequest(widget.initialUri, headers: widget.headers);
      if (!mounted) return;
      setState(() => _controller = controller);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _platformError = error);
    }
  }

  Future<void> _refreshNavigationState(WebViewController controller) async {
    try {
      final values = await Future.wait<Object?>([
        controller.canGoBack(),
        controller.canGoForward(),
        controller.getTitle(),
      ]);
      if (!mounted) return;
      setState(() {
        _progress = 100;
        _canGoBack = values[0]! as bool;
        _canGoForward = values[1]! as bool;
        _pageTitle = values[2] as String?;
      });
    } on Object catch (_) {
      // The WebView may be disposed while asynchronous state is being read.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: CCRouter.navigator.canPop()
            ? IconButton(
                tooltip: '返回',
                onPressed: CCRouter.navigator.pop,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_pageTitle?.isNotEmpty == true ? _pageTitle! : widget.title),
            Text(
              widget.initialUri.host,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '后退',
            onPressed: controller != null && _canGoBack
                ? () => controller.goBack()
                : null,
            icon: const Icon(Icons.arrow_back),
          ),
          IconButton(
            tooltip: '前进',
            onPressed: controller != null && _canGoForward
                ? () => controller.goForward()
                : null,
            icon: const Icon(Icons.arrow_forward),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: controller?.reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: switch ((controller, _platformError)) {
        (final WebViewController value, _) => WebViewWidget(controller: value),
        (_, final Object error) => _WebViewUnavailable(
          host: widget.initialUri.host,
          headerNames: widget.headers.keys.toList(growable: false),
          errorType: error.runtimeType.toString(),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

final class _WebViewUnavailable extends StatelessWidget {
  const _WebViewUnavailable({
    required this.host,
    required this.headerNames,
    required this.errorType,
  });

  final String host;
  final List<String> headerNames;
  final String errorType;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.web_asset_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'WebView 平台未加载，但路由参数已验证',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('Host: $host'),
            if (headerNames.isNotEmpty)
              Text('Header names: ${headerNames.join(', ')}'),
            const SizedBox(height: 8),
            Text(
              'Platform error: $errorType',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
