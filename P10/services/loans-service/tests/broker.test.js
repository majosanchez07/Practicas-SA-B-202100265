/**
 * Pruebas del productor de eventos hacia RabbitMQ.
 *
 * No se levanta un broker real: lo que interesa verificar son las decisiones
 * del modulo —el sobre del mensaje, la durabilidad, la ruta y el
 * comportamiento cuando no hay canal—, no que amqplib hable AMQP. Para eso se
 * sustituye el modulo amqplib en la cache de require por un doble que registra
 * todo lo que el broker le pide.
 *
 * El reemplazo debe hacerse ANTES de requerir src/broker, porque ese modulo
 * captura la referencia a amqplib al importarse.
 */
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

/** Registro de lo que el broker publica y declara. */
const registro = { publicados: [], exchanges: [], cerrado: false };

const canalFalso = {
  assertExchange(nombre, tipo, opciones) {
    registro.exchanges.push({ nombre, tipo, opciones });
    return Promise.resolve();
  },
  publish(exchange, routingKey, contenido, opciones) {
    registro.publicados.push({ exchange, routingKey, contenido, opciones });
    return true;
  },
  close() { registro.cerrado = true; return Promise.resolve(); },
};

const conexionFalsa = {
  createChannel: () => Promise.resolve(canalFalso),
  on() {},
  close: () => Promise.resolve(),
};

// Se inyecta el doble en la cache de modulos de Node antes de cargar el broker.
const rutaAmqp = require.resolve('amqplib');
require.cache[rutaAmqp] = {
  id: rutaAmqp,
  filename: rutaAmqp,
  loaded: true,
  exports: { connect: () => Promise.resolve(conexionFalsa) },
};

const broker = require('../src/broker');

/** Devuelve el ultimo mensaje publicado, ya decodificado desde el Buffer. */
function ultimoMensaje() {
  const ultimo = registro.publicados[registro.publicados.length - 1];
  return { ...ultimo, datos: JSON.parse(ultimo.contenido.toString()) };
}

beforeEach(() => {
  registro.publicados = [];
  registro.exchanges = [];
});

describe('conexion con el broker', () => {
  test('declara el exchange al conectar', async () => {
    await broker.conectar(1, 10);
    assert.strictEqual(registro.exchanges.length, 1);
  });

  test('el exchange es de tipo topic', async () => {
    // topic es lo que permite que notifications-service se suscriba con
    // patrones a varias claves de enrutado a la vez.
    await broker.conectar(1, 10);
    assert.strictEqual(registro.exchanges[0].tipo, 'topic');
  });

  test('el exchange es durable', async () => {
    // Sin durable, el exchange desaparece al reiniciarse RabbitMQ y los
    // eventos publicados despues se perderian silenciosamente.
    await broker.conectar(1, 10);
    assert.strictEqual(registro.exchanges[0].opciones.durable, true);
  });
});

describe('publicacion de eventos', () => {
  test('publica en el exchange configurado', async () => {
    await broker.conectar(1, 10);
    broker.publicarEvento('prueba.evento', { a: 1 });
    assert.strictEqual(ultimoMensaje().exchange, broker.EXCHANGE);
  });

  test('usa la clave de enrutado indicada', async () => {
    await broker.conectar(1, 10);
    broker.publicarEvento('prueba.evento', { a: 1 });
    assert.strictEqual(ultimoMensaje().routingKey, 'prueba.evento');
  });

  test('el mensaje se marca como persistente', async () => {
    // Una cola durable con mensajes no persistentes sigue perdiendo su
    // contenido al reiniciarse el broker: hacen falta las dos cosas.
    await broker.conectar(1, 10);
    broker.publicarEvento('prueba.evento', { a: 1 });
    assert.strictEqual(ultimoMensaje().opciones.persistent, true);
  });

  test('el mensaje declara content-type JSON', async () => {
    await broker.conectar(1, 10);
    broker.publicarEvento('prueba.evento', { a: 1 });
    assert.strictEqual(ultimoMensaje().opciones.contentType, 'application/json');
  });

  test('el sobre del mensaje lleva evento, origen y fecha', async () => {
    // Este sobre es el contrato con el consumidor: procesarMensaje() en
    // notifications-service decide que hacer leyendo "evento".
    await broker.conectar(1, 10);
    broker.publicarEvento('prueba.evento', { a: 1 });
    const { datos } = ultimoMensaje();
    assert.strictEqual(datos.evento, 'prueba.evento');
    assert.strictEqual(datos.origen, 'loans-service');
    assert.ok(datos.emitidoEn);
    assert.deepStrictEqual(datos.datos, { a: 1 });
  });

  test('la fecha de emision es un ISO 8601 valido', async () => {
    await broker.conectar(1, 10);
    broker.publicarEvento('prueba.evento', {});
    const { datos } = ultimoMensaje();
    assert.ok(!Number.isNaN(Date.parse(datos.emitidoEn)));
  });
});

describe('evento de prestamo creado', () => {
  const prestamo = {
    id: 42,
    userId: 7,
    bookId: 13,
    loanDate: '2026-09-10T12:00:00.000Z',
    status: 'active',
    campoInterno: 'no debe viajar',
  };

  test('se publica con la clave loan.created', async () => {
    await broker.conectar(1, 10);
    broker.publicarPrestamoCreado(prestamo);
    assert.strictEqual(ultimoMensaje().routingKey, 'loan.created');
  });

  test('incluye los datos que el consumidor necesita', async () => {
    // notifications-service arma el texto de la notificacion con loanId y
    // bookId, y asocia la fila al usuario con userId.
    await broker.conectar(1, 10);
    broker.publicarPrestamoCreado(prestamo);
    const { datos } = ultimoMensaje();
    assert.strictEqual(datos.datos.loanId, 42);
    assert.strictEqual(datos.datos.userId, 7);
    assert.strictEqual(datos.datos.bookId, 13);
    assert.strictEqual(datos.datos.status, 'active');
  });

  test('no expone campos internos del modelo', async () => {
    // El evento se construye campo por campo en lugar de serializar la
    // instancia completa: asi un campo nuevo en la tabla no se filtra solo.
    await broker.conectar(1, 10);
    broker.publicarPrestamoCreado(prestamo);
    assert.strictEqual(ultimoMensaje().datos.datos.campoInterno, undefined);
  });
});

describe('comportamiento sin canal disponible', () => {
  test('no lanza y devuelve false si aun no hay conexion', async (t) => {
    /*
     * Es el comportamiento que evita el CrashLoopBackOff descrito en el modulo:
     * si RabbitMQ todavia no esta listo, publicar no debe derribar el proceso.
     * El precio es que ese evento se pierde, y por eso se registra en el log.
     *
     * Para llegar a este estado se recarga el modulo con un amqplib que nunca
     * conecta, de modo que "canal" queda en null.
     */
    const rutaBroker = require.resolve('../src/broker');
    delete require.cache[rutaBroker];
    require.cache[rutaAmqp].exports = {
      connect: () => Promise.reject(new Error('ECONNREFUSED')),
    };

    const brokerSinCanal = require(rutaBroker);
    await brokerSinCanal.conectar(1, 10);   // un solo intento, que falla

    assert.strictEqual(brokerSinCanal.publicarEvento('prueba', {}), false);
  });
});
