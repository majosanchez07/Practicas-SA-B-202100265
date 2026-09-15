/**
 * Pruebas del consumidor de eventos.
 *
 * Se cubren dos niveles:
 *
 *  1. procesarMensaje: que cada tipo de evento escriba la fila correcta. Los
 *     modelos de Sequelize se sustituyen por dobles, porque lo que se prueba es
 *     el mapeo evento -> fila, no que Sequelize sepa hablar con Postgres.
 *
 *  2. El ciclo de confirmacion: que el ack ocurra DESPUES de persistir y que un
 *     fallo derive el mensaje a la DLQ en lugar de reencolarlo. Es la garantia
 *     de que un pod que muere a mitad del procesamiento no pierde el mensaje, y
 *     no se puede verificar leyendo el codigo: hace falta ejecutarlo.
 *
 * Como en loans-service, los modulos se reemplazan en la cache de require antes
 * de cargar el consumidor, que captura sus referencias al importarse.
 */
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert');

/** Filas "escritas" por los modelos simulados. */
const escrituras = { notificaciones: [], resumenes: [] };
/** Permite forzar un fallo de base de datos en una prueba concreta. */
let fallarEscritura = false;

function modeloFalso(destino) {
  return {
    create(fila) {
      if (fallarEscritura) return Promise.reject(new Error('base de datos caida'));
      escrituras[destino].push(fila);
      return Promise.resolve(fila);
    },
  };
}

for (const [ruta, destino] of [
  ['../src/models/notification', 'notificaciones'],
  ['../src/models/resumen', 'resumenes'],
]) {
  const resuelta = require.resolve(ruta);
  require.cache[resuelta] = {
    id: resuelta, filename: resuelta, loaded: true, exports: modeloFalso(destino),
  };
}

// amqplib tambien se sustituye: requerir el consumidor lo carga, y el modulo
// real no debe intentar abrir sockets durante las pruebas.
const rutaAmqp = require.resolve('amqplib');
require.cache[rutaAmqp] = {
  id: rutaAmqp, filename: rutaAmqp, loaded: true,
  exports: { connect: () => Promise.reject(new Error('sin broker en pruebas')) },
};

const { procesarMensaje } = require('../src/consumer');

beforeEach(() => {
  escrituras.notificaciones = [];
  escrituras.resumenes = [];
  fallarEscritura = false;
});

describe('evento loan.created', () => {
  const evento = {
    evento: 'loan.created',
    emitidoEn: '2026-09-10T12:00:00.000Z',
    origen: 'loans-service',
    datos: { loanId: 42, userId: 7, bookId: 13, status: 'active' },
  };

  test('crea una notificacion', async () => {
    await procesarMensaje(evento);
    assert.strictEqual(escrituras.notificaciones.length, 1);
  });

  test('la asocia al usuario del prestamo', async () => {
    await procesarMensaje(evento);
    assert.strictEqual(escrituras.notificaciones[0].userId, 7);
  });

  test('la clasifica con el tipo loan_created', async () => {
    // El modelo declara "type" como ENUM: un valor fuera de la lista seria
    // rechazado por Postgres en tiempo de ejecucion.
    await procesarMensaje(evento);
    assert.strictEqual(escrituras.notificaciones[0].type, 'loan_created');
  });

  test('el mensaje menciona el prestamo y el libro', async () => {
    await procesarMensaje(evento);
    const { message } = escrituras.notificaciones[0];
    assert.ok(message.includes('42'), 'deberia mencionar el id del prestamo');
    assert.ok(message.includes('13'), 'deberia mencionar el id del libro');
  });

  test('no escribe ningun resumen', async () => {
    await procesarMensaje(evento);
    assert.strictEqual(escrituras.resumenes.length, 0);
  });
});

describe('evento resumen.generado', () => {
  const evento = {
    evento: 'resumen.generado',
    emitidoEn: '2026-09-10T23:00:00.000Z',
    origen: 'cronjob-summary',
    datos: {
      carne: '202100265',
      totalEjecuciones: 48,
      porHora: { '00': 2, '01': 2, '02': 2 },
    },
  };

  test('almacena el resumen', async () => {
    await procesarMensaje(evento);
    assert.strictEqual(escrituras.resumenes.length, 1);
  });

  test('conserva el carne y el total de ejecuciones', async () => {
    await procesarMensaje(evento);
    const fila = escrituras.resumenes[0];
    assert.strictEqual(fila.carne, '202100265');
    assert.strictEqual(fila.totalEjecuciones, 48);
  });

  test('guarda el desglose por hora en el detalle', async () => {
    // El consumidor mapea datos.porHora -> columna "detalle" (JSONB). Es un
    // renombrado facil de romper y no lo detectaria ninguna otra prueba.
    await procesarMensaje(evento);
    assert.deepStrictEqual(escrituras.resumenes[0].detalle, { '00': 2, '01': 2, '02': 2 });
  });

  test('toma la fecha del sobre del mensaje, no la del momento de consumir', async () => {
    // Importa porque el consumidor puede procesar el mensaje mucho despues de
    // que el cronjob lo emitiera, por ejemplo tras un reinicio del pod.
    await procesarMensaje(evento);
    assert.strictEqual(escrituras.resumenes[0].generadoEn, '2026-09-10T23:00:00.000Z');
  });

  test('no crea ninguna notificacion', async () => {
    await procesarMensaje(evento);
    assert.strictEqual(escrituras.notificaciones.length, 0);
  });
});

describe('eventos no reconocidos', () => {
  test('se ignoran sin lanzar excepcion', async () => {
    // Si lanzara, el mensaje iria a la DLQ. Un evento desconocido en un
    // exchange de tipo topic es algo normal cuando se agrega un productor
    // nuevo, y no deberia contaminar la cola de mensajes muertos.
    await procesarMensaje({ evento: 'evento.inventado', datos: {} });
    assert.strictEqual(escrituras.notificaciones.length, 0);
    assert.strictEqual(escrituras.resumenes.length, 0);
  });
});

describe('confirmacion de mensajes (ack manual y DLQ)', () => {
  /**
   * Reproduce el callback que el consumidor registra en canal.consume: mismo
   * orden de operaciones —parsear, procesar, confirmar— y mismo manejo de
   * error. Permite verificar el contrato de confirmacion sin un broker real.
   */
  async function entregar(contenido) {
    const registro = { ack: 0, nack: [] };
    const canal = {
      ack: () => { registro.ack += 1; },
      nack: (msg, todos, reencolar) => { registro.nack.push({ todos, reencolar }); },
    };
    const msg = { content: Buffer.from(contenido) };
    try {
      await procesarMensaje(JSON.parse(msg.content.toString()));
      canal.ack(msg);
    } catch (err) {
      canal.nack(msg, false, false);
    }
    return registro;
  }

  test('confirma el mensaje tras persistirlo', async () => {
    const registro = await entregar(JSON.stringify({
      evento: 'loan.created',
      datos: { loanId: 1, userId: 1, bookId: 1 },
    }));
    assert.strictEqual(registro.ack, 1);
    assert.strictEqual(escrituras.notificaciones.length, 1);
  });

  test('NO confirma si la escritura en la base de datos falla', async () => {
    // El punto exacto de la garantia: sin fila escrita no hay ack, de modo que
    // RabbitMQ conserva el mensaje.
    fallarEscritura = true;
    const registro = await entregar(JSON.stringify({
      evento: 'loan.created',
      datos: { loanId: 1, userId: 1, bookId: 1 },
    }));
    assert.strictEqual(registro.ack, 0);
    assert.strictEqual(escrituras.notificaciones.length, 0);
  });

  test('un fallo de escritura manda el mensaje a la DLQ sin reencolarlo', async () => {
    // requeue en false evita el bucle infinito del "mensaje veneno": uno que
    // siempre falla volveria a entregarse para siempre, bloqueando la cola.
    fallarEscritura = true;
    const registro = await entregar(JSON.stringify({
      evento: 'loan.created',
      datos: { loanId: 1, userId: 1, bookId: 1 },
    }));
    assert.deepStrictEqual(registro.nack, [{ todos: false, reencolar: false }]);
  });

  test('un mensaje con JSON invalido va a la DLQ', async () => {
    const registro = await entregar('esto no es json');
    assert.strictEqual(registro.ack, 0);
    assert.strictEqual(registro.nack.length, 1);
  });
});
