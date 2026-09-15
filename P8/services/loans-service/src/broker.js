/**
 * Productor de eventos hacia RabbitMQ.
 *
 * Decisiones que sostienen el requisito de durabilidad del enunciado:
 *  - El exchange y la cola se declaran durables, de modo que sobreviven al
 *    reinicio del broker.
 *  - Los mensajes se publican con persistent: true; sin eso, una cola durable
 *    seguiria perdiendo su contenido al reiniciarse RabbitMQ.
 *  - La conexion se reintenta con backoff: el pod del broker puede tardar mas
 *    en estar listo que el del microservicio.
 */
const amqp = require('amqplib');

const RABBITMQ_URL = process.env.RABBITMQ_URL;
const EXCHANGE = process.env.BROKER_EXCHANGE || 'biblioteca.events';
const ROUTING_KEY_LOAN = process.env.BROKER_ROUTING_KEY_LOAN || 'loan.created';

let canal = null;
let conexion = null;

/**
 * Conecta al broker reintentando de forma indefinida.
 *
 * Deliberadamente NO lanza si el broker aun no responde. En Kubernetes el pod
 * de RabbitMQ puede tardar bastante mas en estar listo que el del
 * microservicio, y en una version anterior este metodo agotaba diez intentos y
 * propagaba la excepcion: el proceso moria y el pod entraba en
 * CrashLoopBackOff, cuando en realidad solo faltaba esperar. Reintentar en
 * segundo plano deja al servicio atender de inmediato las operaciones que no
 * dependen del broker y engancharse al broker en cuanto aparezca.
 */
async function conectar(reintentos = Infinity, esperaMs = 3000) {
  for (let intento = 1; intento <= reintentos; intento += 1) {
    try {
      conexion = await amqp.connect(RABBITMQ_URL);
      canal = await conexion.createChannel();

      await canal.assertExchange(EXCHANGE, 'topic', { durable: true });

      conexion.on('error', (err) => {
        console.error('[broker] error de conexion:', err.message);
        canal = null;
      });
      conexion.on('close', () => {
        console.warn('[broker] conexion cerrada, se reintentara');
        canal = null;
        setTimeout(() => conectar(), esperaMs);
      });

      console.log(`[broker] conectado, exchange "${EXCHANGE}" listo`);
      return canal;
    } catch (err) {
      // Se informa solo en los primeros intentos y luego cada diez, para no
      // llenar el log mientras el broker termina de arrancar.
      if (intento <= 3 || intento % 10 === 0) {
        console.warn(`[broker] intento ${intento} fallido: ${err.message}`);
      }
      await new Promise((r) => setTimeout(r, esperaMs));
    }
  }
  return null;
}

/**
 * Publica el evento y retorna de inmediato. El llamador no espera a que el
 * consumidor procese nada: ahi esta el desacople que pide el enunciado.
 */
function publicarEvento(routingKey, payload) {
  if (!canal) {
    console.error('[broker] sin canal disponible, evento descartado:', routingKey);
    return false;
  }

  const mensaje = Buffer.from(JSON.stringify({
    evento: routingKey,
    emitidoEn: new Date().toISOString(),
    origen: 'loans-service',
    datos: payload
  }));

  return canal.publish(EXCHANGE, routingKey, mensaje, {
    persistent: true,
    contentType: 'application/json'
  });
}

function publicarPrestamoCreado(prestamo) {
  return publicarEvento(ROUTING_KEY_LOAN, {
    loanId: prestamo.id,
    userId: prestamo.userId,
    bookId: prestamo.bookId,
    loanDate: prestamo.loanDate,
    status: prestamo.status
  });
}

async function cerrar() {
  try {
    if (canal) await canal.close();
    if (conexion) await conexion.close();
  } catch (err) {
    console.warn('[broker] error al cerrar:', err.message);
  }
}

module.exports = { conectar, publicarEvento, publicarPrestamoCreado, cerrar, EXCHANGE };
