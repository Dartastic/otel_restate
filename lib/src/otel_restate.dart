// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_restate_suppression.dart';

const _tracerName = 'dartastic_otel_libs_restate';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class RestateResult {
  const RestateResult({
    this.invocationId,
    this.serviceName,
    this.serviceType,
    this.handler,
    this.virtualObjectKey,
    this.workflowKey,
    this.invocationStatus,
    this.journalEntries,
    this.retries,
    this.idempotencyKey,
    this.delaySec,
    this.statusCode,
  });

  final String? invocationId;
  final String? serviceName;

  /// `service` / `virtual_object` / `workflow` — Restate's three
  /// service kinds.
  final String? serviceType;

  final String? handler;

  /// Required for virtual-object handlers. Each key gets its own
  /// in-memory state and ordered execution.
  final String? virtualObjectKey;

  /// Required for workflow handlers (a single run per key).
  final String? workflowKey;

  /// `pending` / `ready` / `running` / `suspended` / `succeeded` /
  /// `failed` / `cancelled` / `killed`.
  final String? invocationStatus;

  /// Number of journal entries replayed/recorded — proxy for durability
  /// work done.
  final int? journalEntries;

  final int? retries;

  /// User-supplied idempotency key.
  final String? idempotencyKey;

  /// Delay before execution (for delayed invocations).
  final int? delaySec;

  final int? statusCode;
}

class RestateCallResult<T> {
  const RestateCallResult({required this.value, this.result});
  final T value;
  final RestateResult? result;
}

/// Wraps a Restate API call in a CLIENT span. [operation] is one of
/// `invocation.call`, `invocation.send`, `invocation.get_output`,
/// `invocation.cancel`, `invocation.kill`, `invocation.purge`,
/// `state.get`, `state.set`, `workflow.attach`.
Future<T> tracedRestate<T>({
  required String operation,
  required Future<RestateCallResult<T>> Function() invoke,
}) async {
  if (restateInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'rpc.system': 'restate',
    'rpc.method': operation,
    'restate.operation': operation,
  };

  final span = _tracer().startSpan(
    'restate $operation',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.invocationId != null) {
        extras.add(OTel.attributeString(
          'restate.invocation.id',
          r.result!.invocationId!,
        ));
      }
      if (r.result!.serviceName != null) {
        extras.add(OTel.attributeString(
          'restate.service.name',
          r.result!.serviceName!,
        ));
      }
      if (r.result!.serviceType != null) {
        extras.add(OTel.attributeString(
          'restate.service.type',
          r.result!.serviceType!,
        ));
      }
      if (r.result!.handler != null) {
        extras.add(OTel.attributeString(
          'restate.handler',
          r.result!.handler!,
        ));
      }
      if (r.result!.virtualObjectKey != null) {
        extras.add(OTel.attributeString(
          'restate.virtual_object.key',
          r.result!.virtualObjectKey!,
        ));
      }
      if (r.result!.workflowKey != null) {
        extras.add(OTel.attributeString(
          'restate.workflow.key',
          r.result!.workflowKey!,
        ));
      }
      if (r.result!.invocationStatus != null) {
        extras.add(OTel.attributeString(
          'restate.invocation.status',
          r.result!.invocationStatus!,
        ));
        if (r.result!.invocationStatus == 'failed' ||
            r.result!.invocationStatus == 'killed') {
          span.setStatus(
            SpanStatusCode.Error,
            'Restate invocation ${r.result!.invocationStatus}',
          );
        }
      }
      if (r.result!.journalEntries != null) {
        extras.add(OTel.attributeInt(
          'restate.journal.entries',
          r.result!.journalEntries!,
        ));
      }
      if (r.result!.retries != null) {
        extras.add(OTel.attributeInt('restate.retries', r.result!.retries!));
      }
      if (r.result!.idempotencyKey != null) {
        extras.add(OTel.attributeString(
          'restate.idempotency.key',
          r.result!.idempotencyKey!,
        ));
      }
      if (r.result!.delaySec != null) {
        extras.add(OTel.attributeInt(
          'restate.delay_sec',
          r.result!.delaySec!,
        ));
      }
      if (r.result!.statusCode != null) {
        extras.add(OTel.attributeInt(
          'http.response.status_code',
          r.result!.statusCode!,
        ));
        if (r.result!.statusCode! >= 400) {
          span.setStatus(
            SpanStatusCode.Error,
            'Restate HTTP ${r.result!.statusCode}',
          );
        }
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
