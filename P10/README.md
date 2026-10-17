# Práctica 10: observabilidad y operación (del síntoma a la causa)

María José Tebalán Sánchez · 202100265 · Software Avanzado, sección B

El sistema de las prácticas 8 y 9 se construía, desplegaba, protegía y
recuperaba solo, pero era una caja negra. Esta práctica lo instrumenta con
trazas, métricas y registros correlacionados para responder tres preguntas:
**qué** está fallando, **por qué**, y **si vale la pena intervenir**. Además
cierra el pendiente de la P8: el canary deja de decidirse con pruebas
sintéticas y pasa a decidirse con métricas reales de la versión candidata.

## Tabla de enlaces obligatoria

| Ítem | Enlace o dato requerido |
|---|---|
| Repositorio de código | https://github.com/majosanchez07/Practicas-SA-B-202100265 |
| Repositorio GitOps | https://github.com/majosanchez07/Practicas-SA-B-202100265-gitops |
| Servicios instrumentados | **`api-gateway`**, **`loans-service`**, **`books-service`** · namespace **`sa-p8`** (código: [api-gateway](services/api-gateway/src/telemetria.js), [loans-service](services/loans-service/src/telemetria.js), [books-service](services/books-service/src/observabilidad.py)) |
| AnalysisTemplate por métricas | **`sa-platform-api-gateway-analisis-metricas`** · [P10/charts/sa-platform/templates/analysistemplates.yaml](charts/sa-platform/templates/analysistemplates.yaml) |
| Consultas del análisis | Tasa de error (éxito si `< 0.01`): `(sum(rate(sa_http_requests_total{service_name="api-gateway",rollout_hash="{{args.canary-hash}}",status_code=~"5.."}[1m])) or vector(0)) / sum(rate(sa_http_requests_total{service_name="api-gateway",rollout_hash="{{args.canary-hash}}"}[1m]))` · p95 (éxito si `< 0.5` s): `histogram_quantile(0.95, sum by (le) (rate(sa_http_request_duration_seconds_bucket{service_name="api-gateway",rollout_hash="{{args.canary-hash}}"}[1m])))` |
| SLO declarados | **Disponibilidad:** 99.5 % de peticiones de usuario sin 5xx, ventana móvil de 30 días · **Latencia:** 95 % de peticiones en menos de 300 ms, ventana móvil de 30 días ([justificación](docs/slo.md)) |
| Reglas de alerta | [P10/charts/sa-platform/templates/prometheusrules.yaml](charts/sa-platform/templates/prometheusrules.yaml) (PrometheusRule `sa-platform-slo`) · pruebas: [P10/tests/slo/alertas.test.yaml](tests/slo/alertas.test.yaml) |
| Tablero | [P10/charts/sa-platform/dashboards/operacion.json](charts/sa-platform/dashboards/operacion.json) · captura en operación: [docs/evidencias/capturas/tablero-operacion.png](docs/evidencias/capturas/tablero-operacion.png) |
| Reversión por métricas | AnalysisRun fallido **`sa-platform-api-gateway-5b97d8df46-3`** · Rollout **`sa-platform-api-gateway`** (namespace `sa-p8`). Error de la candidata 10.7 % y 12.1 %, p95 0.99 s; abortado a los 2 min 29 s sin intervención · [AnalysisRun](docs/evidencias/canary/analysisrun-sa-platform-api-gateway-5b97d8df46-3.yaml) · [registro](docs/evidencias/canary/reversion-20261015T190750Z.log) · [Rollout final](docs/evidencias/canary/rollout-final-20261015T190750Z.txt) |
| Recorrido síntoma a causa | [docs/evidencias/sintoma-causa/recorrido-20261015T191705Z.log](docs/evidencias/sintoma-causa/recorrido-20261015T191705Z.log) · **alerta → registro: 3 s** (métricas t+1 s, traza t+2 s, registro t+3 s) · detección: primera señal en 13 s, alerta en 29 min 8 s · capturas [alerta](docs/evidencias/capturas/recorrido-1-alerta-alertmanager.png), [traza](docs/evidencias/capturas/recorrido-2-traza-tempo.png), [registro](docs/evidencias/capturas/recorrido-3-registro-loki.png) |
| Video demostrativo | [Carpeta de grabaciones](https://drive.google.com/drive/folders/1kOchO-0QgwzYgSWx3mVyXL2yfm4uJ3GY?usp=sharing). Minutaje en la [sección Video](#video-demostrativo) |

## Documentos

| Documento | Contenido |
|---|---|
| [docs/slo.md](docs/slo.md) | Los dos SLO, su justificación, las alertas y las alertas eliminadas |
| [docs/informe-operacion.md](docs/informe-operacion.md) | Informe de operación (los seis campos de la plantilla 4.2) |
| [docs/diagrama-telemetria.md](docs/diagrama-telemetria.md) | Recorrido de la señal desde el servicio hasta el tablero, la alerta y el canary |
| [docs/runbooks/](docs/runbooks/) | Un runbook por alerta |
| [docs/preguntas-teoricas.md](docs/preguntas-teoricas.md) | Comportamiento y límites de esta instrumentación |
| [docs/guia-despliegue-y-demostraciones.md](docs/guia-despliegue-y-demostraciones.md) | Despliegue por GitOps y procedimiento de las dos demostraciones |
| [docs/evidencias/INDICE.md](docs/evidencias/INDICE.md) | Evidencias y cómo se generan |
| [docs/guia-grabacion-video.md](docs/guia-grabacion-video.md) | Guía paso a paso para grabar el video demostrativo |

## Qué cambió respecto de las prácticas 8 y 9

| Carencia del enunciado | Solución | Dónde |
|---|---|---|
| Ante una queja de lentitud nadie sabe qué servicio la provoca | OpenTelemetry en tres servicios con propagación W3C `traceparent`: una petición gateway → loans-service → books-service es una sola traza en Tempo. Registros JSON con `trace_id` en Loki, enlazados en ambos sentidos | `services/*/src/telemetria.js`, `logger.js`, `books-service/src/observabilidad.py` |
| El canary se decidía con pruebas que yo misma escribí | El AnalysisTemplate consulta Prometheus por la tasa de error y el p95 de la versión candidata, filtrada por `rollout_hash`, sobre el tráfico real. Ya no hay ningún Job | `charts/sa-platform/templates/analysistemplates.yaml` |
| No se sabe si el sistema cumple lo prometido | Dos SLO con reglas de registro del indicador y del presupuesto consumido, y cuatro alertas por consumo multiventana, cada una con runbook | `prometheusrules.yaml`, `docs/slo.md`, `docs/runbooks/` |
| — | Métricas de negocio: `biblioteca_prestamos_creados_total`, `biblioteca_prestamos_rechazados_total{motivo}`, `biblioteca_libros_consultados_total{resultado}` | `loans-service/src/metricas.js`, `books-service/src/observabilidad.py` |
| — | Stack de observabilidad desplegado por la aplicación raíz de ArgoCD, nunca a mano | repositorio GitOps, `apps/observabilidad-*.yaml` |

**Se conserva sin degradarse:** el pipeline sigue cambiando solo `imageTag`
en el repositorio GitOps (ahora con tags `p10-vX.Y.Z` y el workflow
[p10-gitops.yml](../.github/workflows/p10-gitops.yml)), con Trivy, SBOM y
Cosign; ArgoCD sincroniza; Argo Rollouts promueve con canary; Kyverno admite o
rechaza (el generador de tráfico y todos los pods nuevos cumplen las tres
políticas). El pipeline agrega `promtool check rules` y `promtool test rules`.

## Estructura

```
P10/
├── services/        Los cinco servicios; api-gateway, loans-service y books-service instrumentados
├── cronjobs/        Sin cambios respecto de la P8
├── charts/
│   └── sa-platform/
│       ├── templates/analysistemplates.yaml       Canary por Prometheus
│       ├── templates/prometheusrules.yaml         SLO y alertas
│       ├── templates/dashboard.yaml               Tablero como ConfigMap
│       ├── templates/generador-trafico.yaml       Tráfico permanente para el canary
│       ├── templates/networkpolicies-observabilidad.yaml
│       └── dashboards/operacion.json              Tablero exportado
├── tests/slo/       Pruebas unitarias de las alertas (promtool)
├── scripts/         Evidencia cronometrada de las demostraciones
├── policies/        Políticas de admisión (sin cambios)
└── docs/            Documentación, runbooks y evidencias
```

## Video demostrativo

URL: [https://drive.google.com/drive/folders/1kOchO-0QgwzYgSWx3mVyXL2yfm4uJ3GY?usp=sharing](https://drive.google.com/drive/folders/1kOchO-0QgwzYgSWx3mVyXL2yfm4uJ3GY?usp=sharing)

Minutaje propuesto (5 a 8 minutos). Los minutos se ajustan al grabar:

| Minuto | Punto demostrado | Qué mostrar |
|---|---|---|
| 0:00 | Stack desplegado por GitOps | ArgoCD: las seis aplicaciones `observabilidad-*` y `sa-platform` en Synced/Healthy |
| 0:45 | Una petición, una traza | Tempo: un préstamo como traza única api-gateway → loans-service → books-service → PostgreSQL |
| 1:45 | Traza ↔ registro | Desde el span, *Logs for this span*; desde el registro, el `trace_id` abre la traza |
| 2:30 | Tablero de operación | Las filas por señal de oro y las métricas de negocio (préstamos creados y rechazados) |
| 3:30 | Canary por métricas | El AnalysisTemplate (proveedor prometheus, sin Jobs) y el AnalysisRun `…-5b97d8df46-3` fallido con sus mediciones |
| 4:45 | Del síntoma a la causa | La alerta con su runbook → fila Errores → traza en error → registro "pool de conexiones agotado" |
| 6:15 | Recuperación y tiempos | Los registros de evidencia: reversión en 2 min 29 s, alerta → registro en 3 s, recuperación en 5 min 11 s |
