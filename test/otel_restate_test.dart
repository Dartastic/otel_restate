// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_restate/otel_restate.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_restate-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('invocation.call records service + handler + journal', () async {
    await tracedRestate<String>(
      operation: 'invocation.call',
      invoke: () async => const RestateCallResult(
        value: 'ok',
        result: RestateResult(
          invocationId: 'inv_1',
          serviceName: 'Greeter',
          serviceType: 'virtual_object',
          handler: 'greet',
          virtualObjectKey: 'user-42',
          invocationStatus: 'succeeded',
          journalEntries: 18,
          retries: 0,
          idempotencyKey: 'idem-abc',
          statusCode: 200,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName('restate invocation.call')!);
    expect(a['restate.service.name'], 'Greeter');
    expect(a['restate.service.type'], 'virtual_object');
    expect(a['restate.handler'], 'greet');
    expect(a['restate.virtual_object.key'], 'user-42');
    expect(a['restate.journal.entries'], 18);
    expect(a['restate.idempotency.key'], 'idem-abc');
  });

  test('killed invocation sets span error', () async {
    await tracedRestate<String>(
      operation: 'invocation.get_output',
      invoke: () async => const RestateCallResult(
        value: 'ok',
        result: RestateResult(
          invocationStatus: 'killed',
          retries: 7,
        ),
      ),
    );
    expect(
      spans.findSpanByName('restate invocation.get_output')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutRestateInstrumentationAsync(() async {
      await tracedRestate<String>(
        operation: 'state.get',
        invoke: () async => const RestateCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('restate '), isEmpty);
  });
}
