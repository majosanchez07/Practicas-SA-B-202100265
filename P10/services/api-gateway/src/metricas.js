/**
 * Metricas HTTP del gateway (latencia, trafico y errores).
 *
 * Nombres al llegar a Prometheus (el exportador del Collector agrega _total a
 * los contadores):
 *   sa_http_requests_total{service_name, rollout_hash, route, method, status_code}
 *   sa_http_request_duration_seconds_bucket{...}
 *
 * route es el PREFIJO montado (/books, /loans...), nunca la URL completa: con
 * la URL cruda cada id de libro generaria una serie nueva y Prometheus se
 * llenaria de series que nadie consulta (explosion de cardinalidad).
 */
const { metrics } = require('@opentelemetry/api');

const medidor = metrics.getMeter('api-gateway');

const peticiones = medidor.createCounter('sa_http_requests', {
  description: 'Peticiones HTTP atendidas por el gateway',
});

const duracion = medidor.createHistogram('sa_http_request_duration_seconds', {
  description: 'Duracion de las peticiones HTTP en segundos',
  advice: {
    // Cubos alineados con los umbrales que importan: 300 ms (SLO de
    // latencia) y 500 ms (corte del canary).
    explicitBucketBoundaries: [0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 5],
  },
});

const IGNORADAS = ['/health', '/metrics'];

function rutaDe(url) {
  const segmento = (url || '/').split('?')[0].split('/')[1] || '';
  return segmento ? `/${segmento}` : '/';
}

function middlewareMetricas(req, res, next) {
  if (IGNORADAS.some((r) => req.url.startsWith(r))) return next();

  const inicio = process.hrtime.bigint();
  res.on('finish', () => {
    const segundos = Number(process.hrtime.bigint() - inicio) / 1e9;
    const atributos = {
      route: rutaDe(req.originalUrl),
      method: req.method,
      status_code: String(res.statusCode),
    };
    peticiones.add(1, atributos);
    duracion.record(segundos, atributos);
  });
  next();
}

module.exports = { middlewareMetricas, rutaDe };
