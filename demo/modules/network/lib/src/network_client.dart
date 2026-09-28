import 'dart:async';

import 'package:ccrouter/ccrouter.dart';

/// HTTP methods supported by the Demo network pipeline.
enum CCNetworkMethod { get, post, put, patch, delete, head }

/// Immutable request passed through the backend-neutral pipeline.
final class CCNetworkRequest {
  /// Creates a request with a relative endpoint path.
  const CCNetworkRequest({
    required this.method,
    required this.path,
    this.query = const <String, String>{},
    this.headers = const <String, String>{},
    this.body,
    this.requiresAuthorization = true,
  }) : _resolvedUri = null;

  /// HTTP method.
  final CCNetworkMethod method;

  /// Relative endpoint path, such as `/anything`.
  final String path;

  /// Query values encoded by the backend.
  final Map<String, String> query;

  /// Per-request headers overriding environment defaults.
  final Map<String, String> headers;

  /// Optional JSON-compatible request body.
  final Object? body;

  /// Whether the authorization interceptor should attach a token.
  final bool requiresAuthorization;

  /// URI resolved by [CCNetworkClient] before backend dispatch.
  Uri? get resolvedUri => _resolvedUri;

  /// Returns a request with updated headers or URI.
  CCNetworkRequest copyWith({Map<String, String>? headers, Uri? resolvedUri}) =>
      CCNetworkRequest._resolved(
        method: method,
        path: path,
        query: query,
        headers: headers ?? this.headers,
        body: body,
        requiresAuthorization: requiresAuthorization,
        uri: resolvedUri ?? _resolvedUri,
      );

  /// Marks the request as ready for a backend.
  CCNetworkRequest resolve(Uri uri) => CCNetworkRequest._resolved(
    method: method,
    path: path,
    query: query,
    headers: headers,
    body: body,
    requiresAuthorization: requiresAuthorization,
    uri: uri,
  );

  const CCNetworkRequest._resolved({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.body,
    required this.requiresAuthorization,
    required Uri? uri,
  }) : _resolvedUri = uri;

  final Uri? _resolvedUri;
}

/// Immutable response produced by a backend.
final class CCNetworkResponse<T> {
  /// Creates a network response.
  const CCNetworkResponse({
    required this.statusCode,
    required this.data,
    required this.request,
    this.headers = const <String, List<String>>{},
    this.duration = Duration.zero,
  });

  /// HTTP status code.
  final int statusCode;

  /// Decoded response data.
  final T data;

  /// Response headers.
  final Map<String, List<String>> headers;

  /// Request that produced this response.
  final CCNetworkRequest request;

  /// Backend duration.
  final Duration duration;

  /// Whether this is a 2xx response.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// One named API environment.
final class CCNetworkEnvironment {
  /// Creates an environment with an absolute [baseUrl].
  const CCNetworkEnvironment({required this.id, required this.baseUrl});

  /// Stable environment identifier.
  final String id;

  /// Absolute API base URL.
  final String baseUrl;
}

/// Mutable configuration snapshot owned by one client.
final class CCNetworkConfigurationStore {
  /// Creates a configuration store.
  CCNetworkConfigurationStore({
    required CCNetworkEnvironment environment,
    Map<String, String> headers = const <String, String>{},
  }) : _environment = environment,
       _headers = Map.unmodifiable(headers);

  CCNetworkEnvironment _environment;
  Map<String, String> _headers;

  /// Current environment.
  CCNetworkEnvironment get environment => _environment;

  /// Current default headers.
  Map<String, String> get headers => _headers;

  /// Switches the active environment for future requests.
  void switchEnvironment(CCNetworkEnvironment environment) {
    _environment = environment;
  }

  /// Replaces or adds one default header.
  void setHeader(String name, String value) {
    _headers = Map.unmodifiable({..._headers, name: value});
  }

  /// Removes a default header.
  void removeHeader(String name) {
    final headers = {..._headers}..remove(name);
    _headers = Map.unmodifiable(headers);
  }
}

/// Network failure categories exposed to application policy.
enum CCNetworkFailureKind {
  configuration,
  transport,
  timeout,
  httpStatus,
  interceptor,
}

/// Sanitized network failure that excludes payloads and credentials.
final class CCNetworkException implements Exception {
  /// Creates a classified network failure.
  const CCNetworkException({
    required this.kind,
    required this.request,
    this.statusCode,
    this.causeType,
  });

  /// Failure category.
  final CCNetworkFailureKind kind;

  /// Request associated with the failure.
  final CCNetworkRequest request;

  /// HTTP status, when a response exists.
  final int? statusCode;

  /// Safe backend error type.
  final String? causeType;

  @override
  String toString() =>
      'CCNetworkException(${kind.name}, ${request.method.name} '
      '${request.path}, status=$statusCode, cause=$causeType)';
}

/// Context shared by one interceptor chain.
final class CCNetworkInterceptorContext {
  /// Creates an interceptor context.
  const CCNetworkInterceptorContext({
    required this.requestId,
    required this.startedAt,
    required this.environmentId,
  });

  /// Stable request attempt ID.
  final String requestId;

  /// Pipeline start time.
  final DateTime startedAt;

  /// Environment selected for this request.
  final String environmentId;
}

/// Intercepts request, response, and error stages independently of Dio.
abstract interface class CCNetworkInterceptor {
  /// Transforms a request before backend dispatch.
  FutureOr<CCNetworkRequest> onRequest(
    CCNetworkRequest request,
    CCNetworkInterceptorContext context,
  ) => request;

  /// Observes or transforms a response.
  FutureOr<CCNetworkResponse<Object?>> onResponse(
    CCNetworkResponse<Object?> response,
    CCNetworkInterceptorContext context,
  ) => response;

  /// Observes a failed request without replacing its original error.
  FutureOr<void> onError(
    CCNetworkException error,
    CCNetworkInterceptorContext context,
  ) {}
}

/// Reads the access token at request time.
typedef CCNetworkTokenReader = FutureOr<String?> Function();

/// Adds the latest login token to authorized requests.
final class CCNetworkAuthorizationInterceptor implements CCNetworkInterceptor {
  /// Creates an authorization interceptor.
  const CCNetworkAuthorizationInterceptor(
    this.tokenReader, {
    this.headerName = 'Authorization',
    this.scheme = 'Bearer',
  });

  /// Dynamic token reader used after login/logout changes.
  final CCNetworkTokenReader tokenReader;

  /// Header receiving the token.
  final String headerName;

  /// Authorization scheme.
  final String scheme;

  @override
  FutureOr<CCNetworkRequest> onRequest(
    CCNetworkRequest request,
    CCNetworkInterceptorContext context,
  ) async {
    if (!request.requiresAuthorization ||
        request.headers.keys.any(
          (key) => key.toLowerCase() == headerName.toLowerCase(),
        )) {
      return request;
    }
    final token = await tokenReader();
    if (token == null || token.isEmpty) return request;
    return request.copyWith(
      headers: {...request.headers, headerName: '$scheme $token'},
    );
  }

  @override
  FutureOr<CCNetworkResponse<Object?>> onResponse(
    CCNetworkResponse<Object?> response,
    CCNetworkInterceptorContext context,
  ) => response;

  @override
  FutureOr<void> onError(
    CCNetworkException error,
    CCNetworkInterceptorContext context,
  ) {}
}

/// Stages emitted by the logging interceptor.
enum CCNetworkLogStage { request, response, error }

/// Safe network log record without URI query, headers, payload, or token.
final class CCNetworkLogRecord {
  /// Creates a network log record.
  const CCNetworkLogRecord({
    required this.stage,
    required this.requestId,
    required this.method,
    required this.path,
    required this.environmentId,
    required this.occurredAt,
    this.statusCode,
    this.duration = Duration.zero,
    this.errorKind,
  });

  /// Log stage.
  final CCNetworkLogStage stage;

  /// Request ID.
  final String requestId;

  /// HTTP method.
  final CCNetworkMethod method;

  /// Relative path only.
  final String path;

  /// Environment identity.
  final String environmentId;

  /// Log timestamp.
  final DateTime occurredAt;

  /// HTTP status, when available.
  final int? statusCode;

  /// Backend duration.
  final Duration duration;

  /// Classified error, when [stage] is error.
  final CCNetworkFailureKind? errorKind;
}

/// Emits safe request timing records to an application-owned sink.
final class CCNetworkLoggingInterceptor implements CCNetworkInterceptor {
  /// Creates a logging interceptor.
  const CCNetworkLoggingInterceptor({required this.sink});

  /// Receives sanitized records.
  final void Function(CCNetworkLogRecord record) sink;

  @override
  FutureOr<CCNetworkRequest> onRequest(
    CCNetworkRequest request,
    CCNetworkInterceptorContext context,
  ) {
    sink(
      CCNetworkLogRecord(
        stage: CCNetworkLogStage.request,
        requestId: context.requestId,
        method: request.method,
        path: request.path,
        environmentId: context.environmentId,
        occurredAt: context.startedAt,
      ),
    );
    return request;
  }

  @override
  FutureOr<CCNetworkResponse<Object?>> onResponse(
    CCNetworkResponse<Object?> response,
    CCNetworkInterceptorContext context,
  ) {
    sink(
      CCNetworkLogRecord(
        stage: CCNetworkLogStage.response,
        requestId: context.requestId,
        method: response.request.method,
        path: response.request.path,
        environmentId: context.environmentId,
        occurredAt: DateTime.now(),
        statusCode: response.statusCode,
        duration: response.duration,
      ),
    );
    return response;
  }

  @override
  FutureOr<void> onError(
    CCNetworkException error,
    CCNetworkInterceptorContext context,
  ) {
    sink(
      CCNetworkLogRecord(
        stage: CCNetworkLogStage.error,
        requestId: context.requestId,
        method: error.request.method,
        path: error.request.path,
        environmentId: context.environmentId,
        occurredAt: DateTime.now(),
        statusCode: error.statusCode,
        errorKind: error.kind,
      ),
    );
  }
}

/// Backend-neutral request client shared by Demo business components.
final class CCNetworkClient implements CCDisposable {
  /// Creates a client with one backend and ordered interceptors.
  CCNetworkClient({
    required CCNetworkBackend backend,
    required this.configuration,
    Iterable<CCNetworkInterceptor> interceptors = const [],
  }) : _backend = backend,
       _interceptors = List.unmodifiable(interceptors);

  final CCNetworkBackend _backend;
  final List<CCNetworkInterceptor> _interceptors;
  int _sequence = 0;
  bool _closed = false;

  /// Mutable environment and header store.
  final CCNetworkConfigurationStore configuration;

  /// Sends one request through the interceptor pipeline.
  Future<CCNetworkResponse<Object?>> request(CCNetworkRequest request) async {
    if (_closed) throw StateError('CCNetworkClient is closed.');
    final environment = configuration.environment;
    final parsedBase = Uri.tryParse(environment.baseUrl);
    final parsedPath = Uri.tryParse(request.path);
    if (parsedBase == null ||
        !parsedBase.hasScheme ||
        parsedBase.host.isEmpty) {
      throw CCNetworkException(
        kind: CCNetworkFailureKind.configuration,
        request: request,
        causeType: 'invalid_base_url',
      );
    }
    if (parsedPath == null ||
        parsedPath.hasScheme ||
        parsedPath.host.isNotEmpty) {
      throw CCNetworkException(
        kind: CCNetworkFailureKind.configuration,
        request: request,
        causeType: 'invalid_relative_path',
      );
    }
    final relative = request.path.startsWith('/')
        ? request.path.substring(1)
        : request.path;
    final uri = parsedBase
        .resolve(relative)
        .replace(queryParameters: request.query);
    final prepared = request
        .resolve(uri)
        .copyWith(headers: {...configuration.headers, ...request.headers});
    final context = CCNetworkInterceptorContext(
      requestId: 'network-${++_sequence}',
      startedAt: DateTime.now(),
      environmentId: environment.id,
    );
    var current = prepared;
    final applied = <CCNetworkInterceptor>[];
    try {
      for (final interceptor in _interceptors) {
        current = await interceptor.onRequest(current, context);
        applied.add(interceptor);
      }
      var response = await _backend.send(current);
      for (final interceptor in applied.reversed) {
        response = await interceptor.onResponse(response, context);
      }
      if (!response.isSuccess) {
        throw CCNetworkException(
          kind: CCNetworkFailureKind.httpStatus,
          request: response.request,
          statusCode: response.statusCode,
        );
      }
      return response;
    } on CCNetworkException catch (error) {
      await _notifyError(error, applied, context);
      rethrow;
    } on Object catch (error, stackTrace) {
      final wrapped = CCNetworkException(
        kind: CCNetworkFailureKind.interceptor,
        request: current,
        causeType: error.runtimeType.toString(),
      );
      await _notifyError(wrapped, applied, context);
      Error.throwWithStackTrace(wrapped, stackTrace);
    }
  }

  /// Closes the backend when the owning App Scope closes.
  @override
  FutureOr<void> dispose() {
    if (_closed) return Future<void>.value();
    _closed = true;
    return _backend.close();
  }

  Future<void> _notifyError(
    CCNetworkException error,
    List<CCNetworkInterceptor> applied,
    CCNetworkInterceptorContext context,
  ) async {
    for (final interceptor in applied.reversed) {
      try {
        await interceptor.onError(error, context);
      } catch (_) {
        // Logging/policy failures never replace the request failure.
      }
    }
  }
}

/// Transport contract implemented by Dio and test fakes.
abstract interface class CCNetworkBackend {
  /// Sends a prepared request.
  Future<CCNetworkResponse<Object?>> send(CCNetworkRequest request);

  /// Closes backend-owned resources.
  FutureOr<void> close();
}
