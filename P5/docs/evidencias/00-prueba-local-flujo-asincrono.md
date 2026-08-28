# Evidencia preliminar — Flujo asíncrono validado en local

> Prueba realizada **antes** del despliegue en Kubernetes, para validar el
> código del productor y del consumidor de forma aislada. La evidencia
> definitiva sobre el clúster se documenta más adelante.

Infraestructura temporal: Postgres 16 y RabbitMQ 3.13 en contenedores Docker.

## 1. Probes diferenciadas

```
loans /health/live   -> 200 {"status":"alive","service":"loans-service"}
loans /health/ready  -> 200 {"status":"ready","service":"loans-service","database":"up"}
notif /health/live   -> 200 {"status":"alive","service":"notifications-service"}
notif /health/ready  -> 200 {"status":"ready","service":"notifications-service","database":"up"}
```

## 2. Aislamiento por schema en una sola instancia de Postgres

```
 Schema        |     Name      | Type
 loans         | loans         | table
 notifications | notifications | table
 notifications | resumenes     | table
```

## 3. El productor no espera al consumidor

`createLoan` retorna en **56 ms** en la primera llamada y ~6 ms en las siguientes,
sin importar el estado de notifications-service.

## 4. Comportamiento con el consumidor caído

Tras detener notifications-service se crearon 5 préstamos:

```
  prestamo 1 -> HTTP 200 en 0.017888s
  prestamo 2 -> HTTP 200 en 0.005713s
  prestamo 3 -> HTTP 200 en 0.005689s
  prestamo 4 -> HTTP 200 en 0.005532s
  prestamo 5 -> HTTP 200 en 0.006000s
```

El productor siguió respondiendo con normalidad. Los mensajes quedaron
acumulados en la cola **durable**:

```
name                      messages  messages_ready  durable
notifications.queue.dlq   0         0               true
notifications.queue       5         5               true
```

## 5. Sin pérdida de información al restaurar

Al levantar de nuevo notifications-service, los 5 mensajes pendientes se
procesaron y la cola volvió a 0:

```
[consumer] notificacion creada para el prestamo #7
[consumer] notificacion creada para el prestamo #8
[consumer] notificacion creada para el prestamo #9
[consumer] notificacion creada para el prestamo #10
[consumer] notificacion creada para el prestamo #11

name                      messages
notifications.queue.dlq   0
notifications.queue       0
```

Conteo final: **11 préstamos creados → 11 notificaciones almacenadas.**
No se perdió ningún mensaje.

El ack manual (`channel.ack()` ejecutado únicamente después de que la fila
quedó escrita en Postgres) es lo que garantiza este comportamiento: si el pod
muere a mitad del procesamiento, RabbitMQ vuelve a entregar el mensaje.
