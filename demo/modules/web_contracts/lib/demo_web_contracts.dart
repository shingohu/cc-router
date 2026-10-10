/// Business-facing Pure Dart contracts for the shared Web container.
library;

export 'src/ccrouter_generated/demo_web_contracts.contracts.api.g.dart'
    show
        DemoPrivateWebRoute,
        DemoPublicWebRoute;
export 'web_request.dart'
    show
        DemoPrivateWebRequest,
        DemoPublicWebTarget,
        DemoPublicWebTargetCodec,
        demoMapExternalWebUri;
export 'src/web_route_contracts.dart' show demoWebComponentId;
