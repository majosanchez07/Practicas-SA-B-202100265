# Estrategia de Logging Centralizado

## Descripcion general

Todos los microservicios publican sus logs a RabbitMQ, que los entrega al logging-service. Este servicio los persiste en MongoDB y los expone para consulta y auditoria. El sistema es completamente auditable: cada accion de usuario queda registrada con su trace_id, ip de origen y timestamp.

## Arquitectura del logging

Microservicio → RabbitMQ (cola: logs) → logging-service → MongoDB


## Estructura de un log

```json
{
  "id": "uuid",
  "servicioOrigen": "approval-service",
  "nivel": "INFO",
  "accion": "PASO_APROBACION",
  "mensaje": "Paso 2 aprobado por checker",
  "metadata": {
    "loteId": "uuid-lote",
    "paso": 2,
    "rol": "CHECKER"
  },
  "traceId": "uuid-trace",
  "usuarioId": "uuid-usuario",
  "ipOrigen": "192.168.1.10",
  "creadoEn": "2026-08-13T10:00:00Z"
}
```

## Niveles de log

| Nivel | Uso |
|-------|-----|
| INFO | Operaciones exitosas del flujo normal |
| WARN | Situaciones anomalas no criticas (reintento, dato faltante) |
| ERROR | Fallos que impiden completar una operacion |
| AUDIT | Acciones de usuarios sobre recursos sensibles |

## Trace ID

Cada request que entra por el API Gateway recibe un trace_id unico (UUID v4). Este ID se propaga en los headers de todas las llamadas internas, permitiendo reconstruir el recorrido completo de una operacion a traves de multiples microservicios.

## Consulta de logs

El logging-service expone endpoints para:
- Consultar logs por servicio, nivel, fecha o trace_id.
- Consultar el historial de acciones de un usuario especifico (auditoria).
- Consultar alertas generadas por eventos de nivel ERROR.

## Alertas

Si el logging-service recibe un log de nivel ERROR, genera automaticamente una Alerta en la base de datos, que puede ser consultada y marcada como atendida por un administrador.
