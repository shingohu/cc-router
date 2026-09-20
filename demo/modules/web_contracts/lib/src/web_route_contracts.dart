import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'package:demo_web_contracts/web_request.dart';

/// Stable component identity shared by Web contracts and implementation.
const demoWebComponent = CCComponentDescriptor(
  id: 'demo_web_component',
  version: '0.1.0',
);

/// Cross-component route for public, shareable Web destinations.
@CCRouteContract<void>(
  component: demoWebComponent,
  id: 'demo_web.public',
  pattern: CCPathPattern('/web'),
  deepLink: CCDeepLinkPolicy.enabled,
  description:
      'Loads one allowlisted public HTTPS URL in the shared Web container.',
)
abstract class DemoPublicWebRouteContract {
  /// Declares a validated URL encoded as the `url` query parameter.
  const DemoPublicWebRouteContract({
    @CCQueryParam(name: 'url', codec: DemoPublicWebTargetCodec)
    required this.target,
  });

  /// Public URL safe to serialize into navigation state.
  final DemoPublicWebTarget target;
}

/// Cross-component route for process-local authenticated Web requests.
@CCRouteContract<void>(
  component: demoWebComponent,
  id: 'demo_web.private',
  pattern: CCPathPattern('/web/private'),
  description:
      'Loads a sensitive process-local request without URI serialization.',
)
abstract class DemoPrivateWebRouteContract {
  /// Declares the required in-memory request payload.
  const DemoPrivateWebRouteContract(@CCExtraParam() this.request);

  /// URL, headers, and JavaScript policy retained outside the route URI.
  final DemoPrivateWebRequest request;
}
