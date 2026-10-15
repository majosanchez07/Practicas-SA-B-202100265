/**
 * Practica 10: la consulta al catalogo distingue "el libro no existe" de "el
 * catalogo no responde". Esa diferencia decide el motivo de la metrica
 * biblioteca_prestamos_rechazados_total y el nivel del registro.
 */
const { test, before, after } = require('node:test');
const assert = require('node:assert');
const http = require('node:http');

let servidor;
let respuesta;

before(async () => {
  servidor = http.createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(respuesta));
  });
  await new Promise((r) => servidor.listen(0, r));
  process.env.BOOKS_SERVICE_URL = `http://127.0.0.1:${servidor.address().port}`;
});

after(() => servidor.close());

test('devuelve el libro cuando el catalogo responde', async () => {
  respuesta = { data: { book: { id: 1, title: 'X', available: true } } };
  const { consultarLibro } = require('../src/catalogo');
  const libro = await consultarLibro(1);
  assert.strictEqual(libro.available, true);
});

test('devuelve null cuando el libro no existe', async () => {
  respuesta = { data: { book: null } };
  const { consultarLibro } = require('../src/catalogo');
  assert.strictEqual(await consultarLibro(99), null);
});

test('un error GraphQL del catalogo se reporta como catalogo no disponible', async () => {
  respuesta = { errors: [{ message: 'fallo' }] };
  const { consultarLibro, CatalogoNoDisponible } = require('../src/catalogo');
  await assert.rejects(consultarLibro(1), CatalogoNoDisponible);
});
