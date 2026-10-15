# Informe de operación

Práctica 10 · María José Tebalán Sánchez · 202100265

> **Estado del documento:** los tiempos marcados como `⏱ PENDIENTE` se
> completan con los valores del registro que generan los scripts de evidencia
> (`docs/evidencias/canary/` y `docs/evidencias/sintoma-causa/`). No se
> escriben estimaciones: si un tiempo medido incumple el objetivo, se reporta
> tal cual.

## 1. SLO declarados

| SLO | Objetivo | Ventana | Por qué ese número |
|---|---|---|---|
| Disponibilidad | 99.5 % de peticiones de usuario sin 5xx, medidas en el gateway | 30 días móviles | El clúster de dos nodos con una sola réplica de base de datos tuvo un RTO medido de 13 a 15 min en la P9: 99.9 % (43 min/mes) quedaría agotado con un solo incidente. 99 % sería un fallo visible varias veces por semana. |
| Latencia | 95 % de peticiones de usuario en menos de 300 ms | 30 días móviles | 300 ms es el límite de respuesta percibida como inmediata y más del doble del p95 medido en la P8 (122 ms): solo una regresión real lo incumple. El 5 % restante absorbe arranques en frío del HPA. |

Justificación completa en [slo.md](slo.md).

## 2. Fallo inducido

Se indujeron dos fallos, ambos distintos del de la Práctica 8 (allí, un error
500 inmediato en el catálogo que cualquier prueba sintética detectaba con una
sola petición):

| | Fallo A: canary | Fallo B: síntoma a causa |
|---|---|---|
| Qué se rompió | El api-gateway candidato añade 900 ms a `/loans` y `/books` y devuelve 503 en el 15 % de esas peticiones (simula un reintento síncrono mal configurado) | books-service espera 400 ms y devuelve 503 en el 60 % de las consultas a `/graphql`, registrando `pool de conexiones agotado` (simula el agotamiento del pool de la base) |
| Por qué es difícil de ver | Arranca, responde las sondas y el 85 % de las peticiones terminan en 200 | books-service sigue *Ready*: las sondas no tocan `/graphql` |
| Cómo se provocó | `services.api-gateway.fault.enabled: true` en `environments/prod/values.yaml` del repositorio GitOps (commit ⏱ PENDIENTE) | `services.books-service.fault.enabled: true` en el mismo archivo (commit ⏱ PENDIENTE) |

Ambos entran por GitOps: ningún `kubectl` modificó el clúster.

## 3. Tiempo de detección

| Fallo | Inicio del fallo | Primera señal | Tiempo | Respaldo |
|---|---|---|---|---|
| A (canary) | ⏱ PENDIENTE (línea `INICIO del canary`) | Primera medición fallida del AnalysisRun ⏱ PENDIENTE | ⏱ PENDIENTE | `evidencias/canary/reversion-*.log`, `analysisrun-*.yaml` |
| B (alerta) | ⏱ PENDIENTE (línea `INICIO DEL FALLO`) | 5xx en el gateway ⏱ PENDIENTE · alerta *firing* ⏱ PENDIENTE | ⏱ PENDIENTE | `evidencias/sintoma-causa/recorrido-*.log`, `alerta-*.json` |

Lo esperado por diseño, para contrastar con lo medido: el canary necesita
`initialDelay` de 60 s más dos mediciones fallidas cada 30 s (unos 90 a 120 s).
La alerta de consumo rápido, partiendo de una hora sana, necesita que el error
promedio de la última hora supere 7.2 %; con ~50 % de error en el gateway eso
ocurre hacia los 9 minutos, más 1 minuto de `for`. Las pruebas de
[alertas.test.yaml](../tests/slo/alertas.test.yaml) verifican este retraso.

## 4. Recorrido hasta la causa (fallo B)

| Paso | Herramienta | Qué se vio | Marca |
|---|---|---|---|
| 0 | Alertmanager / Grafana | `SLODisponibilidadConsumoRapido` firing, con enlace al runbook | ⏱ PENDIENTE |
| 1 | Tablero, fila Errores | Solo `/books` falla en el gateway; books-service tiene la misma curva → origen en books-service | ⏱ PENDIENTE |
| 2 | Tempo | Traza `api-gateway → books-service` con el span de `POST /graphql` en error 503 tras ~400 ms y sin spans de SQLAlchemy hijos (nunca llegó a la base) | ⏱ PENDIENTE |
| 3 | Loki (desde el span) | `{"level":"error","service":"books-service","message":"pool de conexiones agotado...","causa":"fallo-inducido-p10","trace_id":"…"}` | ⏱ PENDIENTE |

**Tiempo total alerta → registro:** ⏱ PENDIENTE (objetivo: < 3 min).

## 5. Tiempo de recuperación

| Fallo | Qué lo resolvió | Tiempo hasta estado estable | Respaldo |
|---|---|---|---|
| A | Argo Rollouts, sin intervención: abortó y devolvió el 100 % a la versión estable | ⏱ PENDIENTE (línea `Trafico del canary en 0%`) | `evidencias/canary/` |
| B | La operadora, por GitOps: `fault.enabled: false`, ArgoCD sincronizó | ⏱ PENDIENTE (línea `ESTADO ESTABLE`) | `evidencias/sintoma-causa/` |

## 6. Alerta faltante o sobrante

**Faltante: una señal del propio servicio interno.** La alerta de consumo
rápido se calcula en el gateway con una ventana larga de 1 hora: tarda unos 10
minutos en dispararse aunque la mitad de las peticiones ya fallen desde el
primer minuto. Durante ese tiempo los usuarios ya veían errores. Una alerta
de burn rate por servicio interno (books-service) no acortaría esa ventana,
pero un **tercer nivel de consumo muy rápido** (burn rate > 50 en 5 min y en
1 min, que solo se alcanza con más del 25 % de error) habría detectado este
fallo en 2 a 3 minutos sin disparar por picos breves.

**Mejora concreta a la instrumentación:** el loans-service convierte los
errores del catálogo en errores GraphQL con código HTTP 200. Para el SLO del
gateway, un préstamo rechazado por `catalogo_no_disponible` cuenta como
**éxito**. Hoy solo se ve en la métrica de negocio
`biblioteca_prestamos_rechazados_total`. La mejora es registrar en
`sa_http_requests_total` un `status_code` derivado (`graphql_error`) cuando la
respuesta contiene `errors`, e incluirlo como fallo en el indicador de
disponibilidad.

**Sobrante:** ninguna de las cuatro alertas disparó sin motivo durante las
pruebas ⏱ PENDIENTE (confirmar con el historial de Alertmanager). Las ~150
reglas por defecto de kube-prometheus-stack se eliminaron antes de empezar.
