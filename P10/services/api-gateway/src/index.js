require('dotenv').config();
const express = require('express');
const { crearProxy } = require('./proxy');
const axios = require('axios');

const app = express();

// No se registra express.json() de forma global a proposito.
//
// http-proxy-middleware reenvia el cuerpo de la peticion leyendo el stream
// original. Si un middleware de parseo lo consume antes, el stream queda vacio
// y el proxy se queda esperando indefinidamente un cuerpo que ya fue leido: las
// peticiones POST y PUT terminan en timeout mientras las GET siguen
// funcionando. El gateway solo enruta, de modo que no necesita interpretar el
// cuerpo; se deja pasar tal cual hacia el microservicio correspondiente.

const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || 'http://auth-service:8000';
const BOOKS_SERVICE_URL = process.env.BOOKS_SERVICE_URL || 'http://books-service:8001';
const LOANS_SERVICE_URL = process.env.LOANS_SERVICE_URL || 'http://loans-service:8002';
const NOTIFICATIONS_SERVICE_URL = process.env.NOTIFICATIONS_SERVICE_URL || 'http://notifications-service:8003';

app.get('/', (req, res) => {
  res.json({
    mensaje: 'API Gateway - Biblioteca',
    version: '1.1.0',
    servicios: {
      auth: '/auth',
      books: '/books',
      loans: '/loans',
      notifications: '/notifications'
    }
  });
});

/**
 * Probes diferenciadas.
 * liveness  -> el proceso responde; no consulta a los microservicios porque
 *              que auth este caido no es razon para reiniciar el gateway.
 * readiness -> el gateway solo se declara listo si al menos puede resolver a
 *              los servicios aguas abajo.
 */
app.get('/health/live', (req, res) => {
  res.json({ status: 'alive', service: 'api-gateway' });
});

app.get('/health/ready', async (req, res) => {
  const destinos = {
    auth: AUTH_SERVICE_URL,
    books: BOOKS_SERVICE_URL,
    loans: LOANS_SERVICE_URL,
    notifications: NOTIFICATIONS_SERVICE_URL
  };

  const resultados = await Promise.all(
    Object.entries(destinos).map(async ([nombre, url]) => {
      try {
        await axios.get(`${url}/health/live`, { timeout: 2000 });
        return [nombre, 'up'];
      } catch (err) {
        return [nombre, 'down'];
      }
    })
  );

  const estado = Object.fromEntries(resultados);
  const algunoArriba = resultados.some(([, v]) => v === 'up');

  res.status(algunoArriba ? 200 : 503).json({
    status: algunoArriba ? 'ready' : 'not-ready',
    service: 'api-gateway',
    dependencias: estado
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'api-gateway' });
});

app.use('/auth', crearProxy(AUTH_SERVICE_URL, '/auth', 'Auth service'));

app.use('/books', crearProxy(BOOKS_SERVICE_URL, '/books', 'Books service'));

app.use('/loans', crearProxy(LOANS_SERVICE_URL, '/loans', 'Loans service'));

app.use('/notifications', crearProxy(NOTIFICATIONS_SERVICE_URL, '/notifications', 'Notifications service'));

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`API Gateway corriendo en puerto ${PORT}`);
  console.log(`Auth Service     -> ${AUTH_SERVICE_URL}`);
  console.log(`Books Service    -> ${BOOKS_SERVICE_URL}`);
  console.log(`Loans Service    -> ${LOANS_SERVICE_URL}`);
  console.log(`Notifications    -> ${NOTIFICATIONS_SERVICE_URL}`);
});
