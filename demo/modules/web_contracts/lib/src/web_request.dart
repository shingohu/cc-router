import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Hosts accepted by the public Web container demonstration.
const _demoPublicWebHosts = <String>{'docs.flutter.dev', 'example.com'};

/// Validated public HTTPS destination safe to serialize into a route URI.
final class DemoPublicWebTarget {
  /// Creates a target after validating its scheme, authority, and credentials.
  factory DemoPublicWebTarget(Uri uri) {
    if (!_isAllowedPublicUri(uri)) {
      throw ArgumentError.value(uri, 'uri', 'Unsupported public Web target.');
    }
    return DemoPublicWebTarget._(uri);
  }

  /// Retains the validated immutable URI.
  const DemoPublicWebTarget._(this.uri);

  /// HTTPS destination loaded by the Web container.
  final Uri uri;
}

/// Stable Query representation for [DemoPublicWebTarget].
final class DemoPublicWebTargetCodec
    implements CCRouteQueryCodec<DemoPublicWebTarget> {
  /// Creates the stateless URL codec used by generated route code.
  const DemoPublicWebTargetCodec();

  /// Decodes exactly one allowlisted HTTPS URL.
  @override
  DemoPublicWebTarget decode(List<String> values) {
    if (values.length != 1) throw const FormatException('Expected one URL.');
    final uri = Uri.tryParse(values.single);
    if (uri == null) throw const FormatException('Invalid URL.');
    return DemoPublicWebTarget(uri);
  }

  /// Encodes the validated URL; Runtime owns outer query escaping.
  @override
  List<String> encode(DemoPublicWebTarget value) => [value.uri.toString()];
}

/// Process-local request for authenticated or otherwise sensitive Web pages.
final class DemoPrivateWebRequest {
  /// Creates a request whose URL and headers never enter the route URI.
  DemoPrivateWebRequest({
    required this.uri,
    Map<String, String> headers = const {},
    this.javaScriptEnabled = true,
  }) : headers = Map.unmodifiable(headers) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Expected a credential-free HTTPS URL.',
      );
    }
  }

  /// HTTPS destination loaded only inside the current process.
  final Uri uri;

  /// Immutable request headers omitted from route diagnostics.
  final Map<String, String> headers;

  /// Whether this trusted request enables JavaScript in the WebView.
  final bool javaScriptEnabled;
}

/// Maps an allowlisted standard Web URL to the public container route.
///
/// Platform ingress uses this before calling `CCDeepLinkIngress`. A null
/// result means the URL is not owned by the Web component and must continue
/// through normal native-route resolution or an external-browser fallback.
Uri? demoMapExternalWebUri(Uri incoming) {
  if (!_isAllowedPublicUri(incoming)) return null;
  return Uri(
    path: '/web',
    queryParameters: <String, String>{'url': incoming.toString()},
  );
}

/// Applies the public Web security boundary without logging URI contents.
bool _isAllowedPublicUri(Uri uri) =>
    uri.scheme.toLowerCase() == 'https' &&
    uri.hasAuthority &&
    uri.userInfo.isEmpty &&
    !uri.hasPort &&
    _demoPublicWebHosts.contains(uri.host.toLowerCase());
