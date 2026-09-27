import 'package:ccrouter/ccrouter.dart';
import 'package:demo_web_contracts/demo_web_contracts.dart';

export 'package:demo_web_contracts/demo_web_contracts_owner.dart'
    show
        demoWebComponentId,
        DemoPrivateWebRoute,
        DemoPrivateWebRouteContract,
        DemoPublicWebRoute,
        DemoPublicWebRouteContract;

/// Build-time definition of the Web implementation component.
const demoWebComponent = CCComponent(id: demoWebComponentId, version: '0.1.0');
