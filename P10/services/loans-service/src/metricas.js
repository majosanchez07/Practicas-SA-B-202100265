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

module.exports = {
  prestamoCreado: () => creados.add(1),
  prestamoRechazado: (motivo) => rechazados.add(1, { motivo }),
};
