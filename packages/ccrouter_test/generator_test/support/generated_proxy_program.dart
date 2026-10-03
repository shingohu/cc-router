import 'dart:io';

import 'package:test/test.dart';

/// Compiles and executes emitted Proxy code with a small recording SPI.
/// Runtime routing is tested separately; this checks generated Dart binding and
/// forwarding semantics without requiring Flutter in a Pure Dart subprocess.
Future<ProcessResult> runGeneratedProxyProgram({
  required String output,
  required String contract,
  required String program,
}) async {
  final root = Directory.systemTemp.createTempSync('ccrouter-proxy-program-');
  addTearDown(() => root.deleteSync(recursive: true));
  void write(String name, String source) =>
      File('${root.path}/$name').writeAsStringSync(source);
  write(
    'proxy.dart',
    output
        .replaceAll('package:ccrouter/ccrouter_generated.dart', 'runtime.dart')
        .replaceAll(
          'package:ccrouter_test/audit_contract.dart',
          'contract.dart',
        ),
  );
  write('contract.dart', contract);
  write('main.dart', program);
  write('runtime.dart', '''
Object? currentService;
final class CCServiceKey<T> { const CCServiceKey(this.name); final String name; }
abstract final class CCRouterGeneratedServiceBinding {
  static R invokeSync<S, R>({CCServiceKey<S>? key, required String methodId,
    required String callerComponentId, required R Function(S, Object?) call}) =>
      call(currentService as S, null);
  static Future<R> invoke<S, R>({CCServiceKey<S>? key, required String methodId,
    required String callerComponentId, required Future<R> Function(S, Object?) call}) =>
      call(currentService as S, null);
}
''');
  return Process.run(Platform.resolvedExecutable, ['${root.path}/main.dart']);
}
