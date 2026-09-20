/// Component-author surface used only by the Web implementation package.
library;

export 'src/ccrouter_generated/web_route_contracts.route.contract.g.dart'
    show
        DemoPrivateWebRoute,
        DemoPrivateWebRouteArguments,
        DemoPublicWebRoute,
        DemoPublicWebRouteArguments;
export 'web_request.dart'
    show DemoPrivateWebRequest, DemoPublicWebTarget, DemoPublicWebTargetCodec;
export 'src/web_route_contracts.dart'
    show
        demoWebComponent,
        DemoPrivateWebRouteContract,
        DemoPublicWebRouteContract;
