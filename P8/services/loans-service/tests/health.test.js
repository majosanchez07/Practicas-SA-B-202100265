/**
 * Pruebas de las probes de salud.
 *
 * Lo que se verifica es la distincion entre liveness y readiness, que es una
 * decision de diseno con consecuencias reales en el clus'ter: si ambas
 * consultaran la base de datos, una caida temporal de Postgres haria que
 * Kubernetes reiniciara los pods en lugar de solo sacarlos del balanceo, y el
 * reinicio no arregla una base caida.
 */
const { test, describe } = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const express = require('express');

const { registrarHealth } = require('../src/health');

/** Sequelize simulado: se controla si authenticate() responde o falla. */
function sequelizeFalso({ disponible }) {
  return {
    authenticate: () => (disponible
      ? Promise.resolve()
      : Promise.reject(new Error('connection refused'))),
  };
}

/** Levanta una app con las rutas de salud y hace una peticion contra ella. */
async function consultar(ruta, { disponible }) {
  const app = express();
  registrarHealth(app, sequelizeFalso({ disponible }), 'loans-service');
  const servidor = http.createServer(app);

  await new Promise((r) => servidor.listen(0, '127.0.0.1', r));
  const puerto = servidor.address().port;

  try {
    return await new Promise((resolve, reject) => {
      http.get({ hostname: '127.0.0.1', port: puerto, path: ruta }, (res) => {
        let cuerpo = '';
        res.on('data', (t) => { cuerpo += t; });
        res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(cuerpo) }));
      }).on('error', reject);
    });
  } finally {
    servidor.close();
  }
}

describe('liveness', () => {
  test('responde 200 con la base de datos disponible', async () => {
    const r = await consultar('/health/live', { disponible: true });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.status, 'alive');
  });

  test('responde 200 AUNQUE la base de datos este caida', async () => {
    // El caso central: la liveness no debe depender de Postgres, porque un
    // fallo aqui provoca el reinicio del pod.
    const r = await consultar('/health/live', { disponible: false });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.status, 'alive');
  });

  test('identifica al servicio', async () => {
    const r = await consultar('/health/live', { disponible: true });
    assert.strictEqual(r.body.service, 'loans-service');
  });
});

describe('readiness', () => {
  test('responde 200 cuando la base de datos responde', async () => {
    const r = await consultar('/health/ready', { disponible: true });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.status, 'ready');
    assert.strictEqual(r.body.database, 'up');
  });

  test('responde 503 cuando la base de datos falla', async () => {
    // 503 es lo que hace que Kubernetes retire el pod del Service sin
    // reiniciarlo: deja de recibir trafico y se recupera solo al volver la BD.
    const r = await consultar('/health/ready', { disponible: false });
    assert.strictEqual(r.status, 503);
    assert.strictEqual(r.body.status, 'not-ready');
    assert.strictEqual(r.body.database, 'down');
  });

  test('informa el detalle del fallo', async () => {
    const r = await consultar('/health/ready', { disponible: false });
    assert.ok(r.body.detalle.includes('connection refused'));
  });
});

describe('alias /health de la Practica 4', () => {
  test('sigue respondiendo 200', async () => {
    const r = await consultar('/health', { disponible: true });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.status, 'ok');
  });
});
