/**
 * Pruebas de la instrumentacion de la Practica 10.
 *
 * No necesitan Collector: sin SDK registrado, la API de OpenTelemetry entrega
 * implementaciones vacias, de modo que lo que se verifica aqui es la logica
 * propia (agrupacion de rutas, formato del registro, fallo apagado).
 */
const { test, describe } = require('node:test');
const assert = require('node:assert');

const { rutaDe } = require('../src/metricas');

describe('rutaDe agrupa por prefijo para acotar la cardinalidad', () => {
  test('una ruta con id queda en su prefijo', () => {
    assert.strictEqual(rutaDe('/books/graphql?x=1'), '/books');
    assert.strictEqual(rutaDe('/loans/123/detalle'), '/loans');
  });
  test('la raiz se conserva', () => {
    assert.strictEqual(rutaDe('/'), '/');
  });
});

describe('logger', () => {
  test('escribe una linea JSON con servicio, nivel y mensaje', () => {
    const original = process.stdout.write;
    let salida = '';
    process.stdout.write = (t) => { salida += t; return true; };
    try {
      require('../src/logger').error('prueba', { status_code: 503 });
    } finally {
      process.stdout.write = original;
    }
    const linea = JSON.parse(salida);
    assert.strictEqual(linea.level, 'error');
    assert.strictEqual(linea.message, 'prueba');
    assert.strictEqual(linea.status_code, 503);
    assert.ok(linea.service);
  });
});

describe('fallo inducido', () => {
  test('sin variables de entorno queda apagado', () => {
    const { falloActivo } = require('../src/fallo');
    assert.strictEqual(falloActivo, false);
  });
});
