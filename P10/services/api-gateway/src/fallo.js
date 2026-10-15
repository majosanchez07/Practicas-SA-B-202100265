/**
 * Fallo inducido de la Practica 10.
 *
 * En la P8 el defecto fue un error 500 en el catalogo, que cualquier prueba
 * sintetica detectaba con una sola peticion. Aqui el defecto es otro y mas
 * dificil de ver: una REGRESION DE LATENCIA con errores intermitentes, como
 * la que produciria un reintento sincrono mal configurado hacia un servicio
 * lento. El servicio arranca, responde las sondas y la mayoria de peticiones
 * terminan bien; solo las metricas del trafico real (p95 y tasa de error de
 * la version candidata) lo delatan.
 *
 * Se activa unicamente por variables de entorno, que el chart toma de values:
 *   FALLO_RUTAS       prefijos afectados, separados por coma (/loans,/books)
 *   FALLO_LATENCIA_MS retardo anadido a cada peticion afectada
 *   FALLO_TASA_ERROR  fraccion (0..1) de peticiones afectadas que devuelven 503
 *
 * Sin esas variables el middleware no hace nada.
 */
const log = require('./logger');

const RUTAS = (process.env.FALLO_RUTAS || '').split(',').map((r) => r.trim()).filter(Boolean);
const LATENCIA_MS = Number(process.env.FALLO_LATENCIA_MS || 0);
const TASA_ERROR = Number(process.env.FALLO_TASA_ERROR || 0);

const activo = RUTAS.length > 0 && (LATENCIA_MS > 0 || TASA_ERROR > 0);

function middlewareFallo(req, res, next) {
  if (!activo || !RUTAS.some((r) => req.originalUrl.startsWith(r))) return next();

  setTimeout(() => {
    if (Math.random() < TASA_ERROR) {
      log.error('reintento agotado hacia el servicio aguas abajo', {
        route: req.originalUrl.split('?')[0],
        method: req.method,
        status_code: 503,
        latencia_inducida_ms: LATENCIA_MS,
        causa: 'fallo-inducido-p10',
      });
      return res.status(503).json({ error: 'Servicio no disponible temporalmente' });
    }
    return next();
  }, LATENCIA_MS);
}

module.exports = { middlewareFallo, falloActivo: activo };
