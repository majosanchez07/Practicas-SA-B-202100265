# Evidencia — Comunicación asíncrona en el clúster

## Arquitectura del flujo

```
Cliente → Ingress → API Gateway → loans-service
                                        │
                                        │ publica loan.created  (retorna de inmediato)
                                        ▼
                                   RabbitMQ (cola durable)
                                        │
                                        ▼
                             notifications-service (ack manual)
                                        │
                                        ▼
                                   PostgreSQL
```

El broker está desplegado **como dependencia del chart**, declarada en
`Chart.yaml` y resuelta con `helm dependency update`:

```yaml
dependencies:
  - name: rabbitmq
    version: 16.0.14
    repository: https://charts.bitnami.com/bitnami
    condition: rabbitmq.enabled
```

## 1. El flujo funciona de extremo a extremo

Creación de un préstamo a través del Ingress:

```bash
curl -H "Host: sa-p5.local" -H "Content-Type: application/json" \
  -X POST http://127.0.0.1/loans/graphql \
  -d '{"query":"mutation { createLoan(userId: 202100265, bookId: 42) { id status } }"}'
```

```
{"data":{"createLoan":{"id":1,"userId":202100265,"bookId":42,"status":"active"}}}
real  0m0.169s
```

`loans-service` responde en **169 ms** sin esperar a que la notificación se
genere. El consumidor la procesa por su cuenta:

```
[consumer] notificacion creada para el prestamo #1
```

```
[{"id":1,"userId":202100265,"type":"loan_created",
  "message":"Se registro el prestamo #1 del libro 42.","read":false}]
```

## 2. La cola es durable

```
$ kubectl exec -n sa-p5 sa-platform-rabbitmq-0 -- rabbitmqctl list_queues name messages durable
name                      messages  durable
notifications.queue       0         true
notifications.queue.dlq   0         true
```

## 3. Comportamiento con el consumidor caído

Se detuvo el consumidor y se crearon seis préstamos:

```bash
kubectl scale deployment sa-platform-notifications-service -n sa-p5 --replicas=0
```

```
  prestamo 1 -> HTTP 200 en 0.140130s
  prestamo 2 -> HTTP 200 en 0.013518s
  prestamo 3 -> HTTP 200 en 0.010880s
  prestamo 4 -> HTTP 200 en 0.011167s
  prestamo 5 -> HTTP 200 en 0.017282s
  prestamo 6 -> HTTP 200 en 0.018441s
```

El productor **siguió respondiendo con normalidad** (~13 ms) pese a que el
consumidor no existía: ahí está el desacople. Los mensajes quedaron acumulados:

```
name                      messages  messages_ready  durable
notifications.queue       6         6               true
notifications.queue.dlq   0         0               true
```

## 4. Sin pérdida de información al restaurar

```bash
kubectl scale deployment sa-platform-notifications-service -n sa-p5 --replicas=1
```

```
[consumer] notificacion creada para el prestamo #1
[consumer] notificacion creada para el prestamo #2
[consumer] notificacion creada para el prestamo #3
[consumer] notificacion creada para el prestamo #4
[consumer] notificacion creada para el prestamo #5
[consumer] notificacion creada para el prestamo #6
```

```
name                      messages
notifications.queue       0
notifications.queue.dlq   0
```

Conteo final:

```
         concepto         | count
--------------------------+-------
 prestamos creados        |     6
 notificaciones generadas |     6
```

**Ningún mensaje se perdió.**

## Qué garantiza este comportamiento

**El ack manual.** El consumidor confirma el mensaje con `channel.ack()`
únicamente después de que la fila quedó escrita en PostgreSQL:

```javascript
await canal.consume(QUEUE, async (msg) => {
  try {
    const contenido = JSON.parse(msg.content.toString());
    await procesarMensaje(contenido);   // escribe en la base de datos
    canal.ack(msg);                     // se confirma SOLO tras persistir
  } catch (err) {
    canal.nack(msg, false, false);      // el mensaje irrecuperable va a la DLQ
  }
}, { noAck: false });
```

Si el pod muriera a mitad del procesamiento, RabbitMQ volvería a entregar el
mensaje porque nunca recibió la confirmación. Con `noAck: true` el mensaje se
daría por entregado al salir del broker y se perdería.

**`prefetch(1)`** evita que se acumulen mensajes sin confirmar en la memoria del
pod: si se cae, lo no confirmado sigue en la cola del broker y no en un buffer
que desaparece con el proceso.

**La cola de mensajes muertos.** Un mensaje que falle de forma irrecuperable se
envía a `notifications.queue.dlq` con `nack(requeue: false)`, en lugar de volver
a la cola indefinidamente y bloquear el procesamiento del resto.
