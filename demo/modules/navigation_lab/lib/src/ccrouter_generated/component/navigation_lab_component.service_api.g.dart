// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _ServiceProxyGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter_generated.dart';
import 'dart:async' as service_type_0;
import 'package:demo_order_contracts/demo_order_contracts.dart'
    as service_type_1;

/// Generated typed Service entry points for component `demo_navigation_lab_component`.
abstract final class DemoNavigationLabServices {
  /// Calls `demo_order.summary` as `demo_navigation_lab_component`.
  static const service_type_1.OrderSummaryService orderSummary =
      _OrderSummaryServiceProxy();
}

/// Stateless generated Proxy for `demo_order.summary`.
final class _OrderSummaryServiceProxy
    implements service_type_1.OrderSummaryService {
  /// Creates the generated caller without resolving a Service.
  const _OrderSummaryServiceProxy();

  /// Invokes `demo_order.summary.invocationCount`.
  @override
  int get invocationCount =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.OrderSummaryService,
        int
      >(
        methodId: "invocationCount",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.invocationCount,
      );

  /// Invokes `demo_order.summary.loadSummary`.
  @override
  service_type_0.Future<String> loadSummary(int orderId) =>
      CCRouterGeneratedServiceBinding.invoke<
        service_type_1.OrderSummaryService,
        String
      >(
        methodId: "loadSummary",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.loadSummary(orderId),
      );

  /// Invokes `demo_order.summary.loadValue`.
  @override
  service_type_0.Future<T> loadValue<T extends Object>(
    service_type_1.OrderSummaryValue<T> value,
  ) =>
      CCRouterGeneratedServiceBinding.invoke<
        service_type_1.OrderSummaryService,
        T
      >(
        methodId: "loadValue",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.loadValue<T>(value),
      );

  /// Invokes `demo_order.summary.summaryFor`.
  @override
  String summaryFor(int orderId) =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.OrderSummaryService,
        String
      >(
        methodId: "summaryFor",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.summaryFor(orderId),
      );

  /// Invokes `demo_order.summary.unwrap`.
  @override
  T unwrap<T extends Object>(service_type_1.OrderSummaryValue<T> value) =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.OrderSummaryService,
        T
      >(
        methodId: "unwrap",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.unwrap<T>(value),
      );
}
