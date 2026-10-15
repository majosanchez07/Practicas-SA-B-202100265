/**
 * Registro estructurado en JSON con el identificador de traza.
 *
 * Cada linea es un objeto JSON en stdout. Promtail la recoge del nodo y Loki
 * la indexa; el campo trace_id es el puente entre pilares:
 *   - de un registro a su traza: Grafana convierte trace_id en enlace a Tempo
 *   - de una traza a sus registros: Tempo consulta en Loki {..} |= "<trace_id>"
 *
 * No se usa una libreria de logging: el formato es una linea de JSON y el
 * contexto se toma de la API de OpenTelemetry, que ya esta cargada.
 */
const { trace } = require('@opentelemetry/api');

const SERVICIO = process.env.OTEL_SERVICE_NAME || 'api-gateway';
const NIVELES = { debug: 10, info: 20, warn: 30, warning: 30, error: 40 };
const MINIMO = NIVELES[(process.env.LOG_LEVEL || 'info').toLowerCase()] || 20;

function escribir(nivel, mensaje, campos = {}) {
  if (NIVELES[nivel] < MINIMO) return;

  const linea = {
    timestamp: new Date().toISOString(),
    level: nivel,
    service: SERVICIO,
    message: mensaje,
    ...campos,
  };

  const span = trace.getActiveSpan();
  if (span) {
    const ctx = span.spanContext();
    linea.trace_id = ctx.traceId;
    linea.span_id = ctx.spanId;
  }

  process.stdout.write(`${JSON.stringify(linea)}\n`);
}

module.exports = {
  debug: (m, c) => escribir('debug', m, c),
  info: (m, c) => escribir('info', m, c),
  warn: (m, c) => escribir('warn', m, c),
  error: (m, c) => escribir('error', m, c),
};
