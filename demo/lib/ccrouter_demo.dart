/// Stable Host-facing entry point for generated CCRouter assembly.
library;

export 'demo_identifiers.dart' show DemoHostIds;
export 'src/ccrouter_generated/host/ccrouter_host.routes.g.dart'
    show
        ccrouterGeneratedComponentManifests,
        ccrouterGeneratedRouteCatalog,
        ccrouterGeneratedHostAssembly;
