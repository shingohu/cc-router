// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _ServiceProxyGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter_generated.dart' as ccrouter_service_runtime;
import 'dart:async' as service_type_0;
import 'package:demo_kv_storage/demo_kv_storage.dart' as service_type_1;
import 'package:demo_network/demo_network.dart' as service_type_2;
import 'package:demo_order_contracts/demo_order_contracts.dart'
    as service_type_3;

/// Generated typed Service entry points for component `demo_navigation_lab_component`.
abstract final class DemoNavigationLabServices {
  /// Calls `demo.kv_storage` as `demo_navigation_lab_component`.
  static const service_type_1.DemoKeyValueStorageService demoKeyValueStorage =
      _DemoKeyValueStorageServiceProxy();

  /// Calls `demo.network.client` as `demo_navigation_lab_component`.
  static const service_type_2.DemoNetworkService network =
      _NetworkServiceProxy();

  /// Calls `demo_order.summary` as `demo_navigation_lab_component`.
  static const service_type_3.OrderSummaryService orderSummary =
      _OrderSummaryServiceProxy();
}

/// Stateless generated Proxy for `demo.kv_storage`.
final class _DemoKeyValueStorageServiceProxy
    implements service_type_1.DemoKeyValueStorageService {
  /// Creates the generated caller without resolving a Service.
  const _DemoKeyValueStorageServiceProxy();

  /// Invokes `demo.kv_storage.clear`.
  @override
  service_type_0.Future<void> clear(
    service_type_1.DemoStorageNamespace namespace,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        void
      >(
        methodId: "clear",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.clear(namespace),
      );

  /// Invokes `demo.kv_storage.getBool`.
  @override
  service_type_0.Future<bool?> getBool(
    service_type_1.DemoStorageNamespace namespace,
    String key,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        bool?
      >(
        methodId: "getBool",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.getBool(namespace, key),
      );

  /// Invokes `demo.kv_storage.getDouble`.
  @override
  service_type_0.Future<double?> getDouble(
    service_type_1.DemoStorageNamespace namespace,
    String key,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        double?
      >(
        methodId: "getDouble",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.getDouble(namespace, key),
      );

  /// Invokes `demo.kv_storage.getInt`.
  @override
  service_type_0.Future<int?> getInt(
    service_type_1.DemoStorageNamespace namespace,
    String key,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        int?
      >(
        methodId: "getInt",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.getInt(namespace, key),
      );

  /// Invokes `demo.kv_storage.getJson`.
  @override
  service_type_0.Future<Map<String, Object?>?> getJson(
    service_type_1.DemoStorageNamespace namespace,
    String key,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        Map<String, Object?>?
      >(
        methodId: "getJson",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.getJson(namespace, key),
      );

  /// Invokes `demo.kv_storage.getString`.
  @override
  service_type_0.Future<String?> getString(
    service_type_1.DemoStorageNamespace namespace,
    String key,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        String?
      >(
        methodId: "getString",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.getString(namespace, key),
      );

  /// Invokes `demo.kv_storage.keys`.
  @override
  service_type_0.Future<List<String>> keys(
    service_type_1.DemoStorageNamespace namespace,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        List<String>
      >(
        methodId: "keys",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.keys(namespace),
      );

  /// Invokes `demo.kv_storage.remove`.
  @override
  service_type_0.Future<void> remove(
    service_type_1.DemoStorageNamespace namespace,
    String key,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        void
      >(
        methodId: "remove",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.remove(namespace, key),
      );

  /// Invokes `demo.kv_storage.setBool`.
  @override
  service_type_0.Future<void> setBool(
    service_type_1.DemoStorageNamespace namespace,
    String key,
    bool value,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        void
      >(
        methodId: "setBool",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setBool(namespace, key, value),
      );

  /// Invokes `demo.kv_storage.setDouble`.
  @override
  service_type_0.Future<void> setDouble(
    service_type_1.DemoStorageNamespace namespace,
    String key,
    double value,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        void
      >(
        methodId: "setDouble",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setDouble(namespace, key, value),
      );

  /// Invokes `demo.kv_storage.setInt`.
  @override
  service_type_0.Future<void> setInt(
    service_type_1.DemoStorageNamespace namespace,
    String key,
    int value,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        void
      >(
        methodId: "setInt",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setInt(namespace, key, value),
      );

  /// Invokes `demo.kv_storage.setJson`.
  @override
  service_type_0.Future<void> setJson(
    service_type_1.DemoStorageNamespace namespace,
    String key,
    Map<String, Object?> value,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        void
      >(
        methodId: "setJson",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setJson(namespace, key, value),
      );

  /// Invokes `demo.kv_storage.setString`.
  @override
  service_type_0.Future<void> setString(
    service_type_1.DemoStorageNamespace namespace,
    String key,
    String value,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_1.DemoKeyValueStorageService,
        void
      >(
        methodId: "setString",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setString(namespace, key, value),
      );
}

/// Stateless generated Proxy for `demo.network.client`.
final class _NetworkServiceProxy implements service_type_2.DemoNetworkService {
  /// Creates the generated caller without resolving a Service.
  const _NetworkServiceProxy();

  /// Invokes `demo.network.client.environmentId`.
  @override
  String get environmentId =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.DemoNetworkService,
        String
      >(
        methodId: "environmentId",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.environmentId,
      );

  /// Invokes `demo.network.client.isAuthenticated`.
  @override
  bool get isAuthenticated =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.DemoNetworkService,
        bool
      >(
        methodId: "isAuthenticated",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.isAuthenticated,
      );

  /// Invokes `demo.network.client.logs`.
  @override
  List<service_type_2.CCNetworkLogRecord> get logs =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.DemoNetworkService,
        List<service_type_2.CCNetworkLogRecord>
      >(
        methodId: "logs",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.logs,
      );

  /// Invokes `demo.network.client.removeDefaultHeader`.
  @override
  void removeDefaultHeader(String name) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.DemoNetworkService,
        void
      >(
        methodId: "removeDefaultHeader",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.removeDefaultHeader(name),
      );

  /// Invokes `demo.network.client.request`.
  @override
  service_type_0.Future<service_type_2.CCNetworkResponse<Object?>> request(
    service_type_2.CCNetworkRequest request,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_2.DemoNetworkService,
        service_type_2.CCNetworkResponse<Object?>
      >(
        methodId: "request",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.request(request),
      );

  /// Invokes `demo.network.client.setAccessToken`.
  @override
  void setAccessToken(String? token) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.DemoNetworkService,
        void
      >(
        methodId: "setAccessToken",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setAccessToken(token),
      );

  /// Invokes `demo.network.client.setDefaultHeader`.
  @override
  void setDefaultHeader(String name, String value) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.DemoNetworkService,
        void
      >(
        methodId: "setDefaultHeader",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.setDefaultHeader(name, value),
      );

  /// Invokes `demo.network.client.switchEnvironment`.
  @override
  void switchEnvironment(service_type_2.CCNetworkEnvironment environment) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_2.DemoNetworkService,
        void
      >(
        methodId: "switchEnvironment",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.switchEnvironment(environment),
      );
}

/// Stateless generated Proxy for `demo_order.summary`.
final class _OrderSummaryServiceProxy
    implements service_type_3.OrderSummaryService {
  /// Creates the generated caller without resolving a Service.
  const _OrderSummaryServiceProxy();

  /// Invokes `demo_order.summary.invocationCount`.
  @override
  int get invocationCount =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_3.OrderSummaryService,
        int
      >(
        methodId: "invocationCount",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.invocationCount,
      );

  /// Invokes `demo_order.summary.loadSummary`.
  @override
  service_type_0.Future<String> loadSummary(int orderId) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_3.OrderSummaryService,
        String
      >(
        methodId: "loadSummary",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.loadSummary(orderId),
      );

  /// Invokes `demo_order.summary.loadValue`.
  @override
  service_type_0.Future<T> loadValue<T extends Object>(
    service_type_3.OrderSummaryValue<T> value,
  ) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invoke<
        service_type_3.OrderSummaryService,
        T
      >(
        methodId: "loadValue",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.loadValue<T>(value),
      );

  /// Invokes `demo_order.summary.summaryFor`.
  @override
  String summaryFor(int orderId) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_3.OrderSummaryService,
        String
      >(
        methodId: "summaryFor",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.summaryFor(orderId),
      );

  /// Invokes `demo_order.summary.unwrap`.
  @override
  T unwrap<T extends Object>(service_type_3.OrderSummaryValue<T> value) =>
      ccrouter_service_runtime.CCRouterGeneratedServiceBinding.invokeSync<
        service_type_3.OrderSummaryService,
        T
      >(
        methodId: "unwrap",
        callerComponentId: "demo_navigation_lab_component",
        call: (service, _) => service.unwrap<T>(value),
      );
}
