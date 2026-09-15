/**
 * Consumidor de eventos de RabbitMQ.
 *
 * Puntos que sostienen los requisitos del enunciado:
 *  - Cola DURABLE ligada a un exchange durable: los mensajes sobreviven tanto
 *    al reinicio del broker como a la caida de este consumidor.
 *  - ACK MANUAL: el mensaje se confirma con channel.ack() solo despues de que
 *    la fila quedo escrita en Postgres. Si el pod muere a mitad del proceso,
 *    RabbitMQ vuelve a entregar el mensaje y no se pierde informacion.
 *  - prefetch(1): no se acumulan mensajes sin confirmar en memoria del pod,
 *    de modo que si se cae, lo no confirmado sigue en la cola del broker.
 *  - Un fallo de procesamiento hace nack(requeue: false) hacia la DLQ en lugar
 *    de reencolar infinitamente un mensaje veneno.
 */
const amqp = require('amqplib');
const Notification = require('./models/notification');
const Resumen = require('./models/resumen');

const RABBITMQ_URL = process.env.RABBITMQ_URL;
const EXCHANGE = process.env.BROKER_EXCHANGE || 'biblioteca.events';
const QUEUE = process.env.BROKER_QUEUE || 'notifications.queue';
const DLQ = `${QUEUE}.dlq`;
const ROUTING_KEYS = (process.env.BROKER_ROUTING_KEYS || 'loan.created,resumen.generado')
  .split(',')
  .map((k) => k.trim())
  .filter(Boolean);

let canal = null;
let conexion = null;

async function procesarMensaje(contenido) {
  const { evento, datos, emitidoEn } = contenido;

  if (evento === 'loan.created') {
    await Notification.create({
      userId: datos.userId,
      type: 'loan_created',
      message: `Se registro el prestamo #${datos.loanId} del libro ${datos.bookId}.`
    });
    console.log(`[consumer] notificacion creada para el prestamo #${datos.loanId}`);
    return;
  }

  if (evento === 'resumen.generado') {
    // Resumen publicado por el Cronjob 2: se almacena tal como pide el enunciado.
    await Resumen.create({
      generadoEn: emitidoEn,
      carne: datos.carne,
      totalEjecuciones: datos.totalEjecuciones,
      detalle: datos.porHora
    });
    console.log(`[consumer] resumen almacenado (${datos.totalEjecuciones} ejecuciones)`);
    return;
  }

  console.warn(`[consumer] evento no reconocido: ${evento}`);
}

/**
 * Igual que el productor: reintenta de forma indefinida en lugar de propagar
 * la excepcion, para que un arranque lento del broker no derive en
 * CrashLoopBackOff.
 */
async function iniciar(reintentos = Infinity, esperaMs = 3000) {
  for (let intento = 1; intento <= reintentos; intento += 1) {
    try {
      conexion = await amqp.connect(RABBITMQ_URL);
      canal = await conexion.createChannel();

      await canal.assertExchange(EXCHANGE, 'topic', { durable: true });

      // Cola de mensajes muertos para lo que falle de forma irrecuperable.
      await canal.assertQueue(DLQ, { durable: true });

      await canal.assertQueue(QUEUE, {
        durable: true,
        arguments: {
          'x-dead-letter-exchange': '',
          'x-dead-letter-routing-key': DLQ
        }
      });

      for (const rk of ROUTING_KEYS) {
        await canal.bindQueue(QUEUE, EXCHANGE, rk);
        console.log(`[consumer] cola "${QUEUE}" ligada a "${rk}"`);
      }

      await canal.prefetch(1);

      await canal.consume(QUEUE, async (msg) => {
        if (!msg) return;
        try {
          const contenido = JSON.parse(msg.content.toString());
          await procesarMensaje(contenido);
          canal.ack(msg);            // <- confirmacion SOLO tras persistir
        } catch (err) {
          console.error('[consumer] fallo al procesar, va a DLQ:', err.message);
          canal.nack(msg, false, false);
        }
      }, { noAck: false });          // <- ack manual explicito

      conexion.on('close', () => {
        console.warn('[consumer] conexion cerrada, se reintentara');
        canal = null;
        setTimeout(() => iniciar(), esperaMs);
      });

      console.log(`[consumer] escuchando la cola "${QUEUE}"`);
      return;
    } catch (err) {
      if (intento <= 3 || intento % 10 === 0) {
        console.warn(`[consumer] intento ${intento} fallido: ${err.message}`);
      }
      await new Promise((r) => setTimeout(r, esperaMs));
    }
  }
}

// procesarMensaje se exporta ademas de iniciar: es la logica que decide que
// hacer con cada evento y conviene poder ejercitarla en las pruebas sin
// levantar un RabbitMQ real.
module.exports = { iniciar, procesarMensaje };
