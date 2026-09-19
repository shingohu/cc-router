/// Host-only Flutter composition APIs for CCRouter backends.
///
/// Application composition roots and generated host assembly import this
/// library when wiring component page factories to a concrete navigation
/// backend. Feature code should continue to import `ccrouter.dart` and navigate
/// only through `CCRouter.navigator`.
library;

export 'src/route_catalog.dart';
