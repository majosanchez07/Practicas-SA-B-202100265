# Índice de evidencias

Práctica 10 · María José Tebalán Sánchez · 202100265 · Prueba del 15/10/2026 sobre AKS (`centralus`)

Cada evidencia proviene de una ejecución real sobre el clúster. Los registros
`.log` los generan los scripts de `P10/scripts/` con marcas de tiempo UTC.

## Canary gobernado por métricas

| Evidencia | Archivo |
|---|---|
| Promoción exitosa de 1.1.2: 6 de 6 mediciones aprobadas (error 0, p95 24 a 36 ms) | [promocion-exitosa-analysisrun-…-695fddc58d-2.5.yaml](canary/promocion-exitosa-analysisrun-sa-platform-api-gateway-695fddc58d-2.5.yaml) · [Rollout](canary/promocion-exitosa-rollout-1.1.2.txt) |
| Reversión por métricas: registro cronometrado | [reversion-20261015T190750Z.log](canary/reversion-20261015T190750Z.log) |
| AnalysisRun fallido que la originó | [analysisrun-sa-platform-api-gateway-5b97d8df46-3.yaml](canary/analysisrun-sa-platform-api-gateway-5b97d8df46-3.yaml) |
| Estado del Rollout tras la reversión | [rollout-final-20261015T190750Z.txt](canary/rollout-final-20261015T190750Z.txt) |

## Del síntoma a la causa

| Evidencia | Archivo |
|---|---|
| Registro cronometrado: detección, recorrido y recuperación | [recorrido-20261015T191705Z.log](sintoma-causa/recorrido-20261015T191705Z.log) |
| Alerta disparada (API de Alertmanager, con `runbook_url`) | [alerta-20261015T191705Z.json](sintoma-causa/alerta-20261015T191705Z.json) |
| Traza completa del error (api-gateway → books-service) | [traza-0013d923c9c1a44cd97c4a21c59615aa.json](sintoma-causa/traza-0013d923c9c1a44cd97c4a21c59615aa.json) |
| Registro JSON del error con el mismo `trace_id` | [registro-0013d923c9c1a44cd97c4a21c59615aa.json](sintoma-causa/registro-0013d923c9c1a44cd97c4a21c59615aa.json) |

## Capturas

| Captura | Qué muestra |
|---|---|
| [tablero-operacion.png](capturas/tablero-operacion.png) | El tablero en operación durante la prueba: la reversión del canary (~13:10, hora local) y el fallo de books-service (13:18 a 14:24), con las alertas como anotaciones |
| [recorrido-1-alerta-alertmanager.png](capturas/recorrido-1-alerta-alertmanager.png) | Alertas en Alertmanager; la sostenida aparece inhibida por la crítica del mismo SLO |
| [recorrido-1b-alerta-prometheus.png](capturas/recorrido-1b-alerta-prometheus.png) | Las cuatro reglas de alerta en Prometheus, tres disparadas |
| [recorrido-2-traza-tempo.png](capturas/recorrido-2-traza-tempo.png) | La traza en Tempo: `POST /books` → books-service `POST /graphql` en error tras 402 ms |
| [recorrido-3-registro-loki.png](capturas/recorrido-3-registro-loki.png) | El registro en Loki, consultado por campo `trace_id` |

## Verificable sin clúster

| Qué | Cómo |
|---|---|
| Las reglas de SLO son PromQL válido | `promtool check rules` en el pipeline (22 reglas) |
| Las alertas disparan ante el fallo y no ante un pico breve | `promtool test rules P10/tests/slo/alertas.test.yaml` en el pipeline |
| Registros JSON con `trace_id` y propagación de contexto | Pruebas de los tres servicios en el pipeline `p10-gitops.yml` |
