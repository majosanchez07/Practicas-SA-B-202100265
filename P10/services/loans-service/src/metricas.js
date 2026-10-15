/**
 * Metricas de negocio de loans-service.
 *
 * Responden preguntas que haria alguien que no es ingeniero:
 *   biblioteca_prestamos_creados_total            ¿cuantos prestamos se hacen?
 *   biblioteca_prestamos_rechazados_total{motivo} ¿cuantos usuarios se fueron
 *                                                  sin su libro, y por que?
 *
 * motivo tiene un conjunto cerrado de valores (libro_no_existe,
 * libro_no_disponible, catalogo_no_disponible): nunca se usa el mensaje de
 * error crudo como etiqueta, porque cada texto distinto seria una serie nueva.
 */
const { metrics } = require('@opentelemetry/api');

const medidor = metrics.getMeter('loans-service');

const creados = medidor.createCounter('biblioteca_prestamos_creados', {
  description: 'Prestamos registrados con exito',
});

const rechazados = medidor.createCounter('biblioteca_prestamos_rechazados', {
  description: 'Solicitudes de prestamo que no terminaron en prestamo',
});

// Senales de oro: mismos nombres y cubos que el gateway y books-service, de
// modo que una sola consulta del tablero cubre a los tres servicios.
const peticiones = medidor.createCounter('sa_http_requests', {
  description: 'Peticiones HTTP atendidas',
});
const duracion = medidor.createHistogram('sa_http_request_duration_seconds', {
  description: 'Duracion de las peticiones HTTP en segundos',
  advice: { explicitBucketBoundaries: [0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 5] },
});

function middlewareMetricas(req, res, next) {
  if (req.url.startsWith('/health') || req.url.startsWith('/metrics')) return next();
  const inicio = process.hrtime.bigint();
  res.on('finish', () => {
    const segmento = req.originalUrl.split('?')[0].split('/')[1] || '';
    const atributos = { route: `/${segmento}`, method: req.method, status_code: String(res.statusCode) };
    peticiones.add(1, atributos);
    duracion.record(Number(process.hrtime.bigint() - inicio) / 1e9, atributos);
  });
  next();
}

module.exports = {
  prestamoCreado: () => creados.add(1),
  prestamoRechazado: (motivo) => rechazados.add(1, { motivo }),
  middlewareMetricas,
};
