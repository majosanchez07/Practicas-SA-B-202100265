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
| Tablero | [P10/charts/sa-platform/dashboards/operacion.json](charts/sa-platform/dashboards/operacion.json) · captura: ⏱ PENDIENTE (`docs/evidencias/capturas/tablero-operacion.png`) |
| Reversión por métricas | Rollout **`sa-platform-api-gateway`** · AnalysisRun: ⏱ PENDIENTE (lo registra [evidencia-reversion-canary.sh](scripts/evidencia-reversion-canary.sh) en `docs/evidencias/canary/`) |
| Recorrido síntoma a causa | ⏱ PENDIENTE: ruta `docs/evidencias/sintoma-causa/recorrido-<fecha>.log` y tiempo medido (lo genera [evidencia-sintoma-causa.sh](scripts/evidencia-sintoma-causa.sh)) |
| Video demostrativo | ⏱ PENDIENTE: URL. Minutaje en la [sección Video](#video-demostrativo) |

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

URL: ⏱ PENDIENTE

| Minuto | Punto demostrado |
|---|---|
| ⏱ | Stack desplegado por GitOps: aplicaciones `observabilidad-*` en ArgoCD |
| ⏱ | Una petición de préstamo como una sola traza (gateway → loans → books → PostgreSQL) |
| ⏱ | De la traza a sus registros y del registro a su traza |
| ⏱ | Tablero de operación por señales de oro y métricas de negocio |
| ⏱ | AnalysisTemplate por Prometheus y reversión del canary por métricas |
| ⏱ | Fallo en books-service, alerta por consumo del presupuesto y recorrido alerta → traza → registro cronometrado |
| ⏱ | Recuperación y resumen de tiempos medidos |
