# Índice de evidencias

Práctica 10 · María José Tebalán Sánchez · 202100265

Cada evidencia de esta carpeta proviene de una ejecución real sobre el clúster
y la genera un script con marcas de tiempo UTC. Ninguna se redacta a mano.

| Evidencia | Archivo | Generada por | Estado |
|---|---|---|---|
| Reversión del canary: registro cronometrado | `canary/reversion-<fecha>.log` | `scripts/evidencia-reversion-canary.sh` | ⏱ PENDIENTE de ejecutar |
| AnalysisRun fallido con sus mediciones | `canary/analysisrun-<nombre>.yaml` | mismo script | ⏱ PENDIENTE |
| Estado final del Rollout | `canary/rollout-final-<fecha>.txt` | mismo script | ⏱ PENDIENTE |
| Recorrido síntoma → causa cronometrado | `sintoma-causa/recorrido-<fecha>.log` | `scripts/evidencia-sintoma-causa.sh` | ⏱ PENDIENTE |
| Alerta disparada (API de Alertmanager) | `sintoma-causa/alerta-<fecha>.json` | mismo script | ⏱ PENDIENTE |
| Captura del tablero en operación | `capturas/tablero-operacion.png` | captura de Grafana | ⏱ PENDIENTE |
| Capturas del recorrido (alerta, traza, registro) | `capturas/recorrido-*.png` | captura de Grafana | ⏱ PENDIENTE |

## Evidencia verificable sin clúster

| Qué | Cómo |
|---|---|
| Las reglas de SLO son PromQL válido | `promtool check rules` en el pipeline (22 reglas) |
| Las alertas disparan ante el fallo y no ante un pico breve | `promtool test rules P10/tests/slo/alertas.test.yaml` en el pipeline |
| Los registros del gateway son JSON y la propagación funciona | `npm test` en `P10/services/api-gateway`; además se comprobó en local que el `traceparent` recibido por un servicio simulado y el `trace_id` del registro de error del gateway coinciden |
| Los registros de books-service son JSON con `trace_id` | `pytest tests/test_observabilidad.py` |
