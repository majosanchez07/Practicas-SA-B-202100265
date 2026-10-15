/**
 * Arranque de OpenTelemetry en loans-service — Practica 10
 *
 * Se precarga con node -r (ver Dockerfile.prod) por la misma razon que en el
 * gateway: las instrumentaciones parchean los modulos al requerirlos.
 *
 * Instrumentaciones y por que cada una:
 *   http       extrae el traceparent que envia el gateway (continua SU traza)
 *              e inyecta el propio en la llamada a books-service
 *   express    nombra los spans por ruta
 *   graphql    un span por resolver: muestra si el tiempo se va en createLoan
 *              o en la consulta de disponibilidad
 *   pg         cada consulta SQL como span hijo, con su duracion
 *   amqplib    inyecta el contexto en las cabeceras del mensaje publicado
 */
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
const { ExpressInstrumentation } = require('@opentelemetry/instrumentation-express');
const { GraphQLInstrumentation } = require('@opentelemetry/instrumentation-graphql');
const { PgInstrumentation } = require('@opentelemetry/instrumentation-pg');
const { AmqplibInstrumentation } = require('@opentelemetry/instrumentation-amqplib');
const { Resource } = require('@opentelemetry/resources');

const RUTAS_IGNORADAS = ['/health/live', '/health/ready', '/health', '/metrics'];

if (process.env.OTEL_SDK_DISABLED !== 'true') {
  const sdk = new NodeSDK({
    resource: new Resource({
      'service.name': process.env.OTEL_SERVICE_NAME || 'loans-service',
      'service.namespace': 'biblioteca',
      'service.version': process.env.SERVICE_VERSION || 'dev',
      'rollout.hash': process.env.ROLLOUT_HASH || 'none',
      // Una serie por pod: sin esto, las replicas publican contadores con las
      // mismas etiquetas y Prometheus los mezcla en una sola serie que sube y
      // baja, lo que interpreta como reinicios y dispara rate().
      'service.instance.id': process.env.POD_NAME || require('os').hostname(),
    }),
    traceExporter: new OTLPTraceExporter(),
    metricReader: new PeriodicExportingMetricReader({
      exporter: new OTLPMetricExporter(),
      exportIntervalMillis: 10000,
    }),
    instrumentations: [
      new HttpInstrumentation({
        ignoreIncomingRequestHook: (req) => RUTAS_IGNORADAS.some((r) => (req.url || '').startsWith(r)),
      }),
      new ExpressInstrumentation(),
      // mergeItems: sin esto, una lista de 500 prestamos genera 500 spans de
      // resolver identicos que no aportan nada al diagnostico.
      new GraphQLInstrumentation({ mergeItems: true, ignoreTrivialResolveSpans: true }),
      new PgInstrumentation(),
      new AmqplibInstrumentation(),
    ],
  });

  sdk.start();

  const apagar = () => sdk.shutdown().finally(() => process.exit(0));
  process.on('SIGTERM', apagar);
  process.on('SIGINT', apagar);
}
