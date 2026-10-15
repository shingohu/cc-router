import 'main.dart' show runDemo;

/// Opt-in verification launch; the ordinary Demo entry retains bridge=false.
Future<void> main() => runDemo(enablePredictiveBack: true);
