import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';
import 'package:test/test.dart';

CCDevToolsDiagnosticHealth _health() => CCDevToolsDiagnosticHealth(
  runtimeId: 'runtime-1',
  revision: 3,
  sinkConfigured: true,
  queueCapacity: 8,
  queued: 2,
  inFlight: 1,
  peakQueued: 6,
  delivered: 4,
  failed: 1,
  dropped: 2,
  closed: false,
  histories: [
    const CCDevToolsHistoryStatus(
      name: 'failures',
      capacity: 1,
      retainedCount: 1,
      omittedCount: 3,
    ),
  ],
);

void main() {
  test(
    'optional diagnostics round-trip while version 1 remains compatible',
    () {
      final snapshot = CCDevToolsRuntimeSnapshot(
        capturedAt: DateTime.utc(2026),
        runtimeState: 'initialized',
        diagnostics: [
          CCDevToolsDiagnosticRecord(
            kind: 'failure',
            id: 'nav-1',
            status: 'cancelled',
            timestamp: DateTime.utc(2026),
            routeId: 'orders.detail',
            initialRouteId: 'orders.start',
            hostId: 'right',
            outlet: 'detail',
            operation: 'push',
            stage: 'interception',
            reason: 'cancelled',
            attempt: 'pendingResume',
            recoveryDepth: 1,
            recoverySelected: false,
            errorType: 'CCRouteCancelledError',
            dependsOn: ['fixture.prepare'],
          ),
        ],
        diagnosticHealth: _health(),
      );
      final json = snapshot.toJson();
      final decoded = CCDevToolsRuntimeSnapshot.fromJson(json);
      expect(decoded.toJson(), json);
      expect(decoded.protocolVersion, 1);
      expect(decoded.diagnostics!.single.hostId, 'right');
      expect(decoded.diagnosticHealth!.histories.single.omittedCount, 3);
      expect(() => decoded.diagnostics!.clear(), throwsUnsupportedError);
      expect(
        () => decoded.diagnostics!.single.dependsOn.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => decoded.diagnosticHealth!.histories.clear(),
        throwsUnsupportedError,
      );
      final legacy = Map<String, Object?>.of(json)
        ..remove('diagnostics')
        ..remove('diagnosticHealth');
      final oldProducer = CCDevToolsRuntimeSnapshot.fromJson(legacy);
      expect(oldProducer.diagnostics, isNull);
      expect(oldProducer.diagnosticHealth, isNull);
      expect(oldProducer.toJson().containsKey('diagnostics'), isFalse);
      expect(
        CCDevToolsRuntimeSnapshot.fromJson({
          ...legacy,
          'diagnostics': null,
          'diagnosticHealth': null,
        }).diagnostics,
        isNull,
      );
      expect(
        CCDevToolsRuntimeSnapshot.fromJson({
          ...json,
          'futureField': 'ignored',
        }).toJson(),
        json,
      );
    },
  );

  test('present malformed diagnostic extensions fail explicitly', () {
    final json = CCDevToolsRuntimeSnapshot(
      capturedAt: DateTime.utc(2026),
      runtimeState: 'initialized',
    ).toJson();
    for (final invalid in [
      true,
      0,
      'records',
      <Object?>[null],
      <Object?>[{}],
    ]) {
      expect(
        () => CCDevToolsRuntimeSnapshot.fromJson({
          ...json,
          'diagnostics': invalid,
        }),
        throwsFormatException,
      );
    }
    for (final invalid in [
      true,
      [],
      {'runtimeId': 'incomplete'},
    ]) {
      expect(
        () => CCDevToolsRuntimeSnapshot.fromJson({
          ...json,
          'diagnosticHealth': invalid,
        }),
        throwsFormatException,
      );
    }
    final record = CCDevToolsDiagnosticRecord(
      kind: 'failure',
      id: 'nav',
      status: 'failed',
    ).toJson();
    for (final field in ['recoveryDepth', 'durationMicros']) {
      for (final invalid in [-1, '1', true, 0.5]) {
        expect(
          () =>
              CCDevToolsDiagnosticRecord.fromJson({...record, field: invalid}),
          throwsFormatException,
        );
      }
    }
    expect(
      () => CCDevToolsDiagnosticRecord.fromJson({
        ...record,
        'recoverySelected': 'false',
      }),
      throwsFormatException,
    );
    expect(
      () => CCDevToolsDiagnosticRecord.fromJson({
        ...record,
        'dependsOn': [false],
      }),
      throwsFormatException,
    );
    expect(
      () => CCDevToolsDiagnosticHealth.fromJson({
        ..._health().toJson(),
        'sinkConfigured': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => CCDevToolsDiagnosticHealth.fromJson({
        ..._health().toJson(),
        'queueCapacity': 0,
      }),
      throwsFormatException,
    );
  });
}
