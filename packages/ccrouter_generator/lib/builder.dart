/// Build-runner integration for typed component route generation.
///
/// This is tooling API, not a business navigation API. Applications add the
/// package as a dev dependency and use the automatically applied builder.
library;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/route_generator.dart';

/// Creates one library-local generated part without coupling to a backend.
///
/// Annotated libraries must declare `part '<name>.ccroute.g.dart'`. Keeping
/// generated code in the same library preserves private page constructors
/// and component-only route contracts.
Builder ccRouteBuilder(BuilderOptions options) => PartBuilder(
  [ccRouteGenerator()],
  '.ccroute.g.dart',
  header:
      '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
      '// ignore_for_file: type=lint, unused_element',
);
