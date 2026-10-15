/**
 * Pruebas del reenvio de peticiones del API Gateway.
 *
 * Se usa el runner nativo de Node (node --test) en lugar de Jest o Mocha: el
 * proyecto no tenia dependencias de prueba y el runner integrado evita agregar
 * un arbol de paquetes completo solo para ejecutar estos casos.
 *
 * La estrategia es levantar un microservicio de mentira —un servidor http real
 * en un puerto efimero— y comprobar que el proxy le entrega exactamente lo que
 * recibio. Asi se ejercita el codigo real, incluido el encadenado de flujos,
 * que es justamente la parte que fallaba con http-proxy-middleware y motivo
 * que este modulo se escribiera a mano.
 */
const { test, describe, before, after, beforeEach } = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const express = require('express');

const { crearProxy } = require('../src/proxy');

/** Ultima peticion que recibio el servicio destino, para poder inspeccionarla. */
let ultimaPeticion = null;
let destino;
let puertoDestino;
let gateway;
let puertoGateway;

/** Envuelve server.listen en una promesa para poder usar await en los hooks. */
function escuchar(servidor) {
  return new Promise((resolve) => {
    servidor.listen(0, '127.0.0.1', () => resolve(servidor.address().port));
  });
}

/** Cliente http minimo: evita agregar una dependencia solo para hacer peticiones. */
function pedir(puerto, ruta, opciones = {}) {
  return new Promise((resolve, reject) => {
    const peticion = http.request(
      {
        hostname: '127.0.0.1',
        port: puerto,
        path: ruta,
        method: opciones.method || 'GET',
        headers: opciones.headers || {},
      },
      (respuesta) => {
        let cuerpo = '';
        respuesta.on('data', (trozo) => { cuerpo += trozo; });
        respuesta.on('end', () => resolve({
          status: respuesta.statusCode,
          headers: respuesta.headers,
          body: cuerpo,
        }));
      }
    );
    peticion.on('error', reject);
    if (opciones.body) peticion.write(opciones.body);
    peticion.end();
  });
}

before(async () => {
  // Microservicio destino simulado: guarda lo que recibe y responde en JSON.
  destino = http.createServer((req, res) => {
    let cuerpo = '';
    req.on('data', (trozo) => { cuerpo += trozo; });
    req.on('end', () => {
      ultimaPeticion = {
        metodo: req.method,
        ruta: req.url,
        cabeceras: req.headers,
        cuerpo,
      };
      if (req.url === '/lento') return;          // nunca responde: prueba el timeout
      if (req.url === '/error-500') {
        res.writeHead(500, { 'content-type': 'application/json' });
        return res.end(JSON.stringify({ error: 'fallo interno del servicio' }));
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, recibido: req.url, metodo: req.method }));
    });
  });
  puertoDestino = await escuchar(destino);

  const app = express();
  app.use('/libros', crearProxy(`http://127.0.0.1:${puertoDestino}`, '/libros', 'Books service'));
  // Un puerto donde no hay nadie escuchando: ECONNREFUSED al primer intento.
  app.use('/caido', crearProxy('http://127.0.0.1:1', '/caido', 'Servicio caido'));
  gateway = http.createServer(app);
  puertoGateway = await escuchar(gateway);
});

after(() => {
  destino.close();
  gateway.close();
});

beforeEach(() => { ultimaPeticion = null; });

describe('reenvio de peticiones', () => {
  test('entrega la peticion al servicio destino', async () => {
    const respuesta = await pedir(puertoGateway, '/libros/catalogo');
    assert.strictEqual(respuesta.status, 200);
    assert.strictEqual(ultimaPeticion.ruta, '/catalogo');
  });

  test('quita el prefijo de la ruta', async () => {
    // El destino no conoce el prefijo /libros: espera /catalogo, no
    // /libros/catalogo. Si el prefijo se colara, todas las rutas darian 404.
    await pedir(puertoGateway, '/libros/catalogo');
    assert.strictEqual(ultimaPeticion.ruta, '/catalogo');
  });

  test('la raiz del prefijo se traduce a "/"', async () => {
    await pedir(puertoGateway, '/libros');
    assert.strictEqual(ultimaPeticion.ruta, '/');
  });

  test('conserva la cadena de consulta', async () => {
    await pedir(puertoGateway, '/libros/buscar?autor=Cortazar&pagina=2');
    assert.strictEqual(ultimaPeticion.ruta, '/buscar?autor=Cortazar&pagina=2');
  });

  test('devuelve el cuerpo de la respuesta del destino', async () => {
    const respuesta = await pedir(puertoGateway, '/libros/catalogo');
    assert.deepStrictEqual(JSON.parse(respuesta.body), {
      ok: true, recibido: '/catalogo', metodo: 'GET',
    });
  });

  test('propaga el codigo de estado del destino', async () => {
    const respuesta = await pedir(puertoGateway, '/libros/error-500');
    assert.strictEqual(respuesta.status, 500);
  });
});

describe('metodos y cuerpo', () => {
  for (const metodo of ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']) {
    test(`reenvia el metodo ${metodo}`, async () => {
      await pedir(puertoGateway, '/libros/recurso', { method: metodo });
      assert.strictEqual(ultimaPeticion.metodo, metodo);
    });
  }

  test('reenvia el cuerpo de un POST', async () => {
    // Este es EL caso que motivo escribir el proxy a mano: con
    // http-proxy-middleware el cuerpo se perdia y la peticion quedaba colgada.
    const cuerpo = JSON.stringify({ title: 'Rayuela', author: 'Julio Cortazar' });
    await pedir(puertoGateway, '/libros/crear', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(cuerpo) },
      body: cuerpo,
    });
    assert.strictEqual(ultimaPeticion.cuerpo, cuerpo);
  });

  test('reenvia un cuerpo grande completo', async () => {
    const cuerpo = JSON.stringify({ datos: 'x'.repeat(50000) });
    await pedir(puertoGateway, '/libros/crear', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(cuerpo) },
      body: cuerpo,
    });
    assert.strictEqual(ultimaPeticion.cuerpo.length, cuerpo.length);
  });
});

describe('cabeceras', () => {
  test('propaga el encabezado Authorization', async () => {
    // Sin esto la autenticacion no funcionaria a traves del gateway: el JWT
    // viaja en esta cabecera hacia cada microservicio.
    await pedir(puertoGateway, '/libros/privado', {
      headers: { authorization: 'Bearer token-de-prueba' },
    });
    assert.strictEqual(ultimaPeticion.cabeceras.authorization, 'Bearer token-de-prueba');
  });

  test('reescribe el Host con el del destino', async () => {
    // El proxy reemplaza Host a proposito: conservar el original hace que
    // algunos frameworks construyan URLs absolutas hacia el gateway.
    await pedir(puertoGateway, '/libros/catalogo');
    assert.strictEqual(ultimaPeticion.cabeceras.host, `127.0.0.1:${puertoDestino}`);
  });

  test('propaga cabeceras personalizadas', async () => {
    await pedir(puertoGateway, '/libros/catalogo', {
      headers: { 'x-carne': '202100265' },
    });
    assert.strictEqual(ultimaPeticion.cabeceras['x-carne'], '202100265');
  });
});

describe('manejo de fallos del servicio destino', () => {
  test('responde 502 cuando el servicio no esta disponible', async () => {
    // Sin este manejo, el error del socket derribaria el proceso del gateway y
    // la caida de un microservicio se llevaria consigo a toda la plataforma.
    const respuesta = await pedir(puertoGateway, '/caido/algo');
    assert.strictEqual(respuesta.status, 502);
  });

  test('el 502 identifica al servicio que fallo', async () => {
    const respuesta = await pedir(puertoGateway, '/caido/algo');
    const cuerpo = JSON.parse(respuesta.body);
    assert.strictEqual(cuerpo.servicio, 'Servicio caido');
    assert.ok(cuerpo.error.includes('no disponible'));
  });

  test('el 502 incluye el detalle tecnico del fallo', async () => {
    const respuesta = await pedir(puertoGateway, '/caido/algo');
    assert.ok(JSON.parse(respuesta.body).detalle);
  });
});
