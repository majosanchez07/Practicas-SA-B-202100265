# Comunicacion entre Servicios

## Patron general

El sistema usa dos mecanismos de comunicacion segun la naturaleza de cada interaccion:

| Mecanismo | Cuando se usa |
|-----------|--------------|
| REST sincrono | El cliente necesita una respuesta inmediata (validaciones, consultas, operaciones CRUD) |
| Mensajeria asincrona (RabbitMQ) | El evento no requiere respuesta inmediata y puede ser consumido por multiples servicios (lote aprobado, logs) |

## Comunicacion sincrona - REST

Todas las peticiones del cliente pasan por el API Gateway, que las enruta al microservicio correspondiente via HTTP REST. Cada microservicio expone su propia API REST documentada con OpenAPI / Swagger.

### Headers obligatorios en cada request

Authorization: Bearer {JWT}
X-Trace-Id: {uuid-trace}
Content-Type: application/json


### Ejemplo de flujo REST

Cliente → API Gateway → transaction-service → respuesta al cliente


## Comunicacion asincrona - RabbitMQ

Los eventos de negocio se publican en RabbitMQ y son consumidos por los servicios interesados. Esto desacopla los microservicios y permite que fallen de forma independiente.

### Colas definidas

| Cola | Productor | Consumidor | Descripcion |
|------|-----------|------------|-------------|
| lote.aprobado | approval-service | notification-service, core-banking-connector | Lote aprobado en paso 3 |
| logs.eventos | Todos los servicios | logging-service | Logs centralizados |

### Ejemplo de mensaje en cola lote.aprobado

```json
{
  "evento": "LoteAprobado",
  "loteId": "uuid-lote",
  "aprobadoPor": "uuid-usuario",
  "timestamp": "2026-08-13T10:00:00Z"
}
```

## Integracion con Auth Service P2

El API Gateway consulta al Auth Service de la Practica 2 para verificar el JWT en cada request. El Authorization Service de P2 valida el rol del usuario antes de permitir el acceso al recurso solicitado.

API Gateway → Auth Service P2 (verifica JWT)
→ Authorization Service P2 (verifica rol)
→ Microservicio destino


## Manejo de fallos

- Si un microservicio falla, el API Gateway retorna 503 al cliente.
- Si RabbitMQ no esta disponible, los microservicios reintentaran la publicacion con backoff exponencial.
- Si el core bancario externo falla, el core-banking-connector reintentara segun la configuracion (max_reintentos, backoff_ms).
