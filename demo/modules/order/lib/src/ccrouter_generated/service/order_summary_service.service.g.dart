// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _ServiceGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order/src/order_summary_service.dart' as service_source;
import 'package:demo_order_contracts/src/order_summary_service.dart'
    as service_type_0;

/// Registers generated Service `demo_order.summary` for its component.
void ccrouterRegisterDemoOrderSummaryServiceService(CCRegistry registry) {
  registry.registerService<service_type_0.OrderSummaryService>(
    CCServiceProvider<service_type_0.OrderSummaryService>(
      factory: (_) => const service_source.DemoOrderSummaryService(),
      contract: const CCServiceToken<service_type_0.OrderSummaryService>(
        "demo_order.summary",
      ),
      scope: CCServiceScope.app,
      creationPolicy: CCServiceCreationPolicy.singleton,
      isDefault: false,
    ),
  );
}
