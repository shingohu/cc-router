// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _InitTaskGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_navigation_lab/src/navigation_lab_component_registrar.dart'
    as init_source;

/// Registers generated InitTask `demo.startup.analytics`.
void ccrouterRegisterInitializeDemoAnalyticsInitTask(CCRegistry registry) {
  registry.registerInitTask(
    CCInitTaskDefinition(
      id: "demo.startup.analytics",
      dependsOn: const ["demo.startup.foundation"],
      gate: CCInitTaskGate("privacyGranted"),
      failurePolicy: CCInitTaskFailurePolicy.critical,
      run: (_) => init_source.initializeDemoAnalytics(),
    ),
  );
}

/// Registers generated InitTask `demo.startup.foundation`.
void ccrouterRegisterInitializeDemoFoundationInitTask(CCRegistry registry) {
  registry.registerInitTask(
    CCInitTaskDefinition(
      id: "demo.startup.foundation",
      dependsOn: const ["demo_order.startup.foundation"],
      gate: CCInitTaskGate("appStarted"),
      failurePolicy: CCInitTaskFailurePolicy.critical,
      run: (_) => init_source.initializeDemoFoundation(),
    ),
  );
}

/// Registers generated InitTask `demo.startup.optional-dependent`.
void ccrouterRegisterInitializeDemoOptionalDependentInitTask(
  CCRegistry registry,
) {
  registry.registerInitTask(
    CCInitTaskDefinition(
      id: "demo.startup.optional-dependent",
      dependsOn: const ["demo.startup.optional-sdk"],
      gate: CCInitTaskGate("appStarted"),
      failurePolicy: CCInitTaskFailurePolicy.critical,
      run: (_) => init_source.initializeDemoOptionalDependent(),
    ),
  );
}

/// Registers generated InitTask `demo.startup.optional-sdk`.
void ccrouterRegisterInitializeDemoOptionalSdkInitTask(CCRegistry registry) {
  registry.registerInitTask(
    CCInitTaskDefinition(
      id: "demo.startup.optional-sdk",
      dependsOn: const [],
      gate: CCInitTaskGate("appStarted"),
      failurePolicy: CCInitTaskFailurePolicy.optional,
      run: (_) => init_source.initializeDemoOptionalSdk(),
    ),
  );
}

/// Registers generated InitTask `demo.startup.parallel-primary`.
void ccrouterRegisterInitializeDemoParallelPrimaryInitTask(
  CCRegistry registry,
) {
  registry.registerInitTask(
    CCInitTaskDefinition(
      id: "demo.startup.parallel-primary",
      dependsOn: const ["demo.startup.foundation"],
      gate: CCInitTaskGate("appStarted"),
      failurePolicy: CCInitTaskFailurePolicy.critical,
      run: (_) => init_source.initializeDemoParallelPrimary(),
    ),
  );
}

/// Registers generated InitTask `demo.startup.parallel-secondary`.
void ccrouterRegisterInitializeDemoParallelSecondaryInitTask(
  CCRegistry registry,
) {
  registry.registerInitTask(
    CCInitTaskDefinition(
      id: "demo.startup.parallel-secondary",
      dependsOn: const ["demo.startup.foundation"],
      gate: CCInitTaskGate("appStarted"),
      failurePolicy: CCInitTaskFailurePolicy.critical,
      run: (_) => init_source.initializeDemoParallelSecondary(),
    ),
  );
}

/// Registers generated InitTask `demo.startup.timeout`.
void ccrouterRegisterInitializeDemoTimeoutInitTask(CCRegistry registry) {
  registry.registerInitTask(
    CCInitTaskDefinition(
      id: "demo.startup.timeout",
      dependsOn: const [],
      gate: CCInitTaskGate("demo.timeoutLab"),
      failurePolicy: CCInitTaskFailurePolicy.optional,
      timeout: Duration(microseconds: 60000),
      run: init_source.initializeDemoTimeout,
    ),
  );
}
