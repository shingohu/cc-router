// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _ServiceProxyGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter_generated.dart';
import 'dart:async' as service_type_0;
import 'package:demo_network/demo_network.dart' as service_type_1;
import 'package:demo_order_contracts/demo_order_contracts.dart'
    as service_type_2;

/// Generated typed Service entry points for component `demo_navigation_lab_component`.
abstract final class DemoNavigationLabServices {
  /// Calls `demo.network.client` as `demo_navigation_lab_component`.
  static const service_type_1.DemoNetworkService demoNetwork =
      _DemoNetworkServiceProxy();

  /// Calls `demo_order.summary` as `demo_navigation_lab_component`.
  static const service_type_2.OrderSummaryService orderSummary =
      _OrderSummaryServiceProxy();
}

/// Stateless generated Proxy for `demo.network.client`.
final class _DemoNetworkServiceProxy
    implements service_type_1.DemoNetworkService {
  /// Creates the generated caller without resolving a Service.
  const _DemoNetworkServiceProxy();

  /// Invokes `demo.network.client.environmentId`.
  @override
  String get environmentId =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.DemoNetworkService,
        String
      >(
        methodId: "environmentId",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.environmentId,
      );

  /// Invokes `demo.network.client.isAuthenticated`.
  @override
  bool get isAuthenticated =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.DemoNetworkService,
        bool
      >(
        methodId: "isAuthenticated",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.isAuthenticated,
      );

  /// Invokes `demo.network.client.logs`.
  @override
  List<service_type_1.CCNetworkLogRecord> get logs =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.DemoNetworkService,
        List<service_type_1.CCNetworkLogRecord>
      >(
        methodId: "logs",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.logs,
      );

  /// Invokes `demo.network.client.removeDefaultHeader`.
  @override
  void removeDefaultHeader(String name) =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.DemoNetworkService,
        void
      >(
        methodId: "removeDefaultHeader",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.removeDefaultHeader(name),
      );

  /// Invokes `demo.network.client.request`.
  @override
  service_type_0.Future<service_type_1.CCNetworkResponse<Object?>> request(
    service_type_1.CCNetworkRequest request,
  ) =>
      CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoNetworkService,
        service_type_1.CCNetworkResponse<Object?>
      >(
        methodId: "request",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.request(request),
      );

  /// Invokes `demo.network.client.setAccessToken`.
  @override
  void setAccessToken(String? token) =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.DemoNetworkService,
        void
      >(
        methodId: "setAccessToken",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setAccessToken(token),
      );

  /// Invokes `demo.network.client.setDefaultHeader`.
  @override
  void setDefaultHeader(String name, String value) =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.DemoNetworkService,
        void
      >(
        methodId: "setDefaultHeader",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setDefaultHeader(name, value),
      );

  /// Invokes `demo.network.client.switchEnvironment`.
  @override
  void switchEnvironment(service_type_1.CCNetworkEnvironment environment) =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_1.DemoNetworkService,
        void
      >(
        methodId: "switchEnvironment",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.switchEnvironment(environment),
      );
}

/// Stateless generated Proxy for `demo_order.summary`.
final class _OrderSummaryServiceProxy
    implements service_type_2.OrderSummaryService {
  /// Creates the generated caller without resolving a Service.
  const _OrderSummaryServiceProxy();

  /// Invokes `demo_order.summary.invocationCount`.
  @override
  int get invocationCount =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.OrderSummaryService,
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
        service_type_2.OrderSummaryService,
        String
      >(
        methodId: "loadSummary",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.loadSummary(orderId),
      );

  /// Invokes `demo_order.summary.loadValue`.
  @override
  service_type_0.Future<T> loadValue<T extends Object>(
    service_type_2.OrderSummaryValue<T> value,
  ) =>
      CCRouterGeneratedServiceBinding.invoke<
        service_type_2.OrderSummaryService,
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
        service_type_2.OrderSummaryService,
        String
      >(
        methodId: "summaryFor",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.summaryFor(orderId),
      );

  /// Invokes `demo_order.summary.unwrap`.
  @override
  T unwrap<T extends Object>(service_type_2.OrderSummaryValue<T> value) =>
      CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.OrderSummaryService,
        T
      >(
        methodId: "unwrap",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.unwrap<T>(value),
      );
}
