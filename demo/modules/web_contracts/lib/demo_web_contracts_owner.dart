/// Component-author surface used only by the Web implementation package.
library;

export 'src/ccrouter_generated/demo_web_contracts.contracts.api.g.dart'
    show
        DemoPrivateWebRoute,
        DemoPrivateWebRouteArguments,
        DemoPublicWebRoute,
        DemoPublicWebRouteArguments;
export 'web_request.dart'
    show DemoPrivateWebRequest, DemoPublicWebTarget, DemoPublicWebTargetCodec;
export 'src/web_route_contracts.dart'
    show
        demoWebComponentId,
        DemoPrivateWebRouteContract,
        DemoPublicWebRouteContract;
