/// Business-facing Pure Dart contracts for the shared Web container.
library;

export 'src/ccrouter_generated/contract/web_route_contracts.route.contract.g.dart'
    show
        DemoPrivateWebRoute,
        DemoPrivateWebRouteArguments,
        DemoPublicWebRoute,
        DemoPublicWebRouteArguments;
export 'web_request.dart'
    show
        DemoPrivateWebRequest,
        DemoPublicWebTarget,
        DemoPublicWebTargetCodec,
        demoMapExternalWebUri;
