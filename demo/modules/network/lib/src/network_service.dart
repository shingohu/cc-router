import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:dio/dio.dart';

import 'demo_network_component.dart';
import 'network_client.dart';

/// Public Service used by Demo business components for HTTP requests.
@CCServiceContract(
  componentId: demoNetworkComponentId,
  id: 'demo.network.client',
  alias: 'network',
  description:
      'Provides environment-aware HTTP requests with safe interceptors.',
)
abstract interface class DemoNetworkService {
  /// Current API environment ID.
  String get environmentId;

  /// Whether an access token is currently configured.
  bool get isAuthenticated;

  /// Recent safe request logs for the Demo diagnostics page.
  List<CCNetworkLogRecord> get logs;

  /// Sends one typed request through the shared pipeline.
  Future<CCNetworkResponse<Object?>> request(CCNetworkRequest request);

  /// Changes the API environment for future requests.
  void switchEnvironment(CCNetworkEnvironment environment);

  /// Changes the login token used by the authorization interceptor.
  void setAccessToken(String? token);

  /// Adds or replaces one environment default header.
  void setDefaultHeader(String name, String value);

  /// Removes one environment default header.
  void removeDefaultHeader(String name);
}

/// Dio-backed implementation used by the Demo shared network component.
@CCService()
final class DemoNetworkServiceImpl implements DemoNetworkService, CCDisposable {
  /// Creates an app-scoped network client with the Demo environments.
  DemoNetworkServiceImpl() {
    _initializeClient(_DioNetworkBackend(Dio()));
  }

  /// Injects an owned transport for deterministic lifecycle tests.
  DemoNetworkServiceImpl.withBackend(CCNetworkBackend backend) {
    _initializeClient(backend);
  }

  void _initializeClient(CCNetworkBackend backend) {
    _client = CCNetworkClient(
      backend: backend,
      configuration: CCNetworkConfigurationStore(
        environment: demoNetworkEnvironments.first,
        headers: const {'X-Demo-Client': 'ccrouter-network-demo'},
      ),
      interceptors: [
        CCNetworkAuthorizationInterceptor(() => _accessToken),
        CCNetworkLoggingInterceptor(sink: _addLog),
      ],
    );
  }

  late final CCNetworkClient _client;
  String? _accessToken;
  final List<CCNetworkLogRecord> _logs = <CCNetworkLogRecord>[];
  bool _disposed = false;
  Future<void>? _disposal;

  @override
  String get environmentId => _client.configuration.environment.id;

  @override
  bool get isAuthenticated => _accessToken != null;

  @override
  List<CCNetworkLogRecord> get logs => List.unmodifiable(_logs.reversed);

  @override
  Future<CCNetworkResponse<Object?>> request(CCNetworkRequest request) =>
      _client.request(request);

  @override
  void switchEnvironment(CCNetworkEnvironment environment) {
    _ensureActive();
    _client.configuration.switchEnvironment(environment);
  }

  @override
  void setAccessToken(String? token) {
    _ensureActive();
    _accessToken = token;
  }

  @override
  void setDefaultHeader(String name, String value) {
    _ensureActive();
    _client.configuration.setHeader(name, value);
  }

  @override
  void removeDefaultHeader(String name) {
    _ensureActive();
    _client.configuration.removeHeader(name);
  }

  void _addLog(CCNetworkLogRecord record) {
    if (_disposed) return;
    _logs.add(record);
    if (_logs.length > 80) _logs.removeAt(0);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('DemoNetworkService is disposed.');
  }

  /// App Scope owns cleanup; business consumers must not dispose this Service.
  /// Concurrent calls share transport closure, including its failure result.
  @override
  Future<void> dispose() {
    if (_disposal case final pending?) return pending;
    final completion = Completer<void>();
    _disposal = completion.future;
    _disposed = true;
    _accessToken = null;
    _logs.clear();
    completion.complete(Future<void>.sync(_client.dispose));
    return completion.future;
  }
}

/// API environments used by the network lab.
const demoNetworkEnvironments = <CCNetworkEnvironment>[
  CCNetworkEnvironment(id: 'development', baseUrl: 'https://httpbin.org/'),
  CCNetworkEnvironment(id: 'staging', baseUrl: 'https://postman-echo.com/'),
  CCNetworkEnvironment(id: 'production', baseUrl: 'https://httpbin.org/'),
];

/// Dio backend kept private to the Demo module.
final class _DioNetworkBackend implements CCNetworkBackend {
  _DioNetworkBackend(this._dio);

  final Dio _dio;

  @override
  Future<CCNetworkResponse<Object?>> send(CCNetworkRequest request) async {
    final uri = request.resolvedUri;
    if (uri == null) {
      throw CCNetworkException(
        kind: CCNetworkFailureKind.configuration,
        request: request,
        causeType: 'unresolved_uri',
      );
    }
    try {
      final response = await _dio.request<Object?>(
        uri.toString(),
        data: request.body,
        options: Options(
          method: request.method.name.toUpperCase(),
          headers: request.headers,
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      return CCNetworkResponse<Object?>(
        statusCode: response.statusCode ?? 0,
        data: response.data,
        request: request,
        headers: response.headers.map.map(
          (key, values) => MapEntry(key, List.unmodifiable(values)),
        ),
      );
    } on DioException catch (error) {
      throw CCNetworkException(
        kind:
            error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.connectionTimeout
            ? CCNetworkFailureKind.timeout
            : CCNetworkFailureKind.transport,
        request: request,
        statusCode: error.response?.statusCode,
        causeType: error.type.name,
      );
    }
  }

  @override
  Future<void> close() async {
    _dio.close(force: true);
  }
}
