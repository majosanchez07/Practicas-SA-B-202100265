/**
 * Reenvio de peticiones hacia los microservicios.
 *
 * Se implementa sobre el modulo http de Node en lugar de usar
 * http-proxy-middleware. El motivo es concreto: con esa libreria las peticiones
 * GET se reenviaban correctamente, pero cualquier POST quedaba colgado hasta
 * agotar el tiempo de espera del cliente, tanto con la version 2 como con la 3,
 * y sin que el microservicio destino llegara a recibir nada. Se comprobo que la
 * red no era la causa lanzando la misma peticion con el modulo http desde el
 * propio pod del gateway: respondio en 99 ms.
 *
 * El gateway solo necesita elegir un destino y encadenar dos flujos, de modo
 * que la dependencia no aportaba nada que justificara arrastrar ese fallo.
 */
const http = require('http');
const { URL } = require('url');

/**
 * Crea un middleware que reenvia todo lo que reciba hacia destino, quitando el
 * prefijo indicado de la ruta.
 *
 * @param {string} destino  URL base del microservicio, p. ej. http://svc:8002
 * @param {string} prefijo  Segmento a eliminar de la ruta, p. ej. /loans
 * @param {string} nombre   Nombre del servicio, para los mensajes de error
 */
function crearProxy(destino, prefijo, nombre) {
  const base = new URL(destino);

  return function reenviar(req, res) {
    // El path que llega ya viene sin el prefijo cuando se monta con app.use,
    // pero se normaliza para que la raiz del microservicio sea "/".
    const ruta = req.url.startsWith('/') ? req.url : `/${req.url}`;

    const cabeceras = { ...req.headers };
    // El destino tiene su propio host; conservar el original confunde a
    // algunos frameworks al construir URLs absolutas.
    cabeceras.host = base.host;

    const peticion = http.request(
      {
        hostname: base.hostname,
        port: base.port,
        path: ruta,
        method: req.method,
        headers: cabeceras,
        timeout: 30000,
      },
      (respuesta) => {
        res.writeHead(respuesta.statusCode, respuesta.headers);
        respuesta.pipe(res);
      }
    );

    peticion.on('timeout', () => {
      peticion.destroy();
      if (!res.headersSent) {
        res.status(504).json({
          error: `${nombre} no respondio a tiempo`,
          servicio: nombre,
        });
      }
    });

    peticion.on('error', (err) => {
      if (!res.headersSent) {
        res.status(502).json({
          error: `${nombre} no disponible`,
          servicio: nombre,
          detalle: err.message,
        });
      }
    });

    // El cuerpo se encadena tal cual, sin interpretarlo. Por eso el gateway no
    // registra express.json() de forma global: si algo consumiera el stream
    // antes de este punto, aqui no quedaria nada que reenviar.
    req.pipe(peticion);
  };
}

module.exports = { crearProxy };
