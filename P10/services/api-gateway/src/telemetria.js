/**
 * Arranque de OpenTelemetry — Practica 10
 *
 * Se carga ANTES que la aplicacion (node -r ./src/telemetria.js src/index.js).
 * El orden no es opcional: las instrumentaciones de http y express parchean
 * los modulos al momento de requerirlos, de modo que si express se carga
 * primero, el parche llega tarde y no se genera ningun span.
 *
 * Tres decisiones que conviene dejar escritas:
 *
 *  1. Todo sale por OTLP hacia el Collector, nunca directo a Tempo o a
 *     Prometheus. El servicio no conoce los backends: si manana se cambia
 *     Tempo por Jaeger, solo cambia la configuracion del Collector.
 *
 *  2. Las metricas HTTP se definen a mano (ver metricas.js) en lugar de usar
 *     las que emite la instrumentacion automatica. El nombre y la unidad de
 *     esas metricas cambian entre versiones de la convencion semantica, y el
 *     AnalysisTemplate del canary depende de un nombre estable.
 *
 *  3. El identificador del ReplicaSet (rollouts-pod-template-hash) viaja como
 *     atributo de recurso. Es lo que permite al analisis del canary medir SOLO
 *     la version candidata y no el promedio de ambas.
 */
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
const { ExpressInstrumentation } = require('@opentelemetry/instrumentation-express');
const { Resource } = require('@opentelemetry/resources');

const habilitado = process.env.OTEL_SDK_DISABLED !== 'true';

// Las sondas de Kubernetes llegan cada pocos segundos: trazarlas llenaria el
// backend de spans sin valor y ocultaria las peticiones de usuarios.
const RUTAS_IGNORADAS = ['/health/live', '/health/ready', '/health', '/metrics'];

if (habilitado) {
  const sdk = new NodeSDK({
    resource: new Resource({
      'service.name': process.env.OTEL_SERVICE_NAME || 'api-gateway',
      'service.namespace': 'biblioteca',
      'service.version': process.env.SERVICE_VERSION || 'dev',
      'rollout.hash': process.env.ROLLOUT_HASH || 'none',
      // Una serie por pod: sin esto, las replicas publican contadores con las
      // mismas etiquetas y Prometheus los mezcla en una sola serie que sube y
      // baja, lo que interpreta como reinicios y dispara rate().
      'service.instance.id': process.env.POD_NAME || require('os').hostname(),
    }),
    // OTEL_EXPORTER_OTLP_ENDPOINT lo inyecta el chart (http://otel-collector:4318).
    traceExporter: new OTLPTraceExporter(),
    metricReader: new PeriodicExportingMetricReader({
      exporter: new OTLPMetricExporter(),
      // 10 s: el analisis del canary consulta ventanas de 1 minuto; con el
      // valor por defecto (60 s) cada ventana tendria una sola muestra.
      exportIntervalMillis: 10000,
    }),
    instrumentations: [
      new HttpInstrumentation({
        ignoreIncomingRequestHook: (req) => RUTAS_IGNORADAS.some((r) => (req.url || '').startsWith(r)),
      }),
      new ExpressInstrumentation(),
    ],
  });

  sdk.start();

  const apagar = () => sdk.shutdown().finally(() => process.exit(0));
  process.on('SIGTERM', apagar);
  process.on('SIGINT', apagar);
}
