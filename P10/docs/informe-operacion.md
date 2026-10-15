# Informe de operación

Práctica 10 · María José Tebalán Sánchez · 202100265 · Prueba del 15/10/2026 sobre AKS (`centralus`)

Todos los tiempos salen de los registros con marca UTC de
[`evidencias/canary/reversion-20261015T190750Z.log`](evidencias/canary/reversion-20261015T190750Z.log)
y [`evidencias/sintoma-causa/recorrido-20261015T191705Z.log`](evidencias/sintoma-causa/recorrido-20261015T191705Z.log).

## 1. SLO declarados

| SLO | Objetivo | Ventana | Por qué ese número |
|---|---|---|---|
| Disponibilidad | 99.5 % de peticiones de usuario sin 5xx (medidas en el gateway) | 30 días móviles | Con dos nodos y una sola réplica de base de datos, la P9 midió un RTO de 13 a 15 min: 99.9 % (43 min/mes) se agotaría con un incidente. 99 % sería un fallo visible varias veces por semana. |
| Latencia | 95 % de peticiones en menos de 300 ms | 30 días móviles | 300 ms es el límite de lo percibido como inmediato y más del doble del p95 sano (24 a 36 ms medidos en el canary de 1.1.2). El 5 % absorbe arranques en frío. |

## 2. Fallo inducido

Dos fallos, ambos distintos al de la P8 (allí, un 500 inmediato que detectaba una sola petición sintética). Los dos entraron por commit en el repositorio GitOps.

| | A: canary (commit `2e06fdf`) | B: síntoma a causa (commit `d978c11`) |
|---|---|---|
| Qué | El gateway candidato añade 900 ms a `/loans` y `/books` y responde 503 en el 15 % (reintento síncrono mal configurado) | books-service espera 400 ms y responde 503 en el 60 % de `/graphql` (pool de conexiones agotado) |
| Por qué no es obvio | Arranca, pasa sondas y el 85 % responde 200 | books sigue *Ready*: las sondas no tocan `/graphql` |

## 3. Tiempo de detección

| Fallo | Inicio | Primera señal | Tiempo |
|---|---|---|---|
| A | 19:08:16, canary creado | 19:10:15, primera medición fallida del AnalysisRun (error 10.7 %, p95 0.99 s) | **2 min** |
| B | 19:18:13, todas las réplicas con el fallo | 19:18:26, 5xx en el gateway (métrica) · 19:47:21, alerta *firing* | **13 s** (métrica) · **29 min 8 s** (alerta) |

La alerta tardó 29 minutos, cuando el diseño preveía unos 10. La causa está medida: en la ventana de 1 hora seguía la serie del gateway `1.1.1`, anterior a la corrección de `service.instance.id`, con 6 reinicios falsos de contador. Inflaba el denominador (12 peticiones/s aparentes frente a ~1.5 reales por pod) y diluía el 53 % de error real. No se tocaron umbrales ni datos durante la prueba.

## 4. Recorrido hasta la causa (fallo B)

Hecho con las mismas APIs que usa Grafana (Prometheus, Tempo, Loki), desde la alerta abierta y siguiendo el runbook:

| Paso | Señal | Resultado | Marca |
|---|---|---|---|
| 1 | Métricas | El gateway falla en `/books`; el servicio interno con 5xx es books-service | t+1 s |
| 2 | Trazas | Traza `0013d923…` api-gateway → books-service; span de servidor `POST /graphql` en error 503 tras 402 ms, sin spans de base de datos | t+2 s |
| 3 | Registros | `"pool de conexiones agotado…", "causa":"fallo-inducido-p10"`, mismo `trace_id` | t+3 s |

**Alerta → registro: 3 s** (objetivo < 3 min). Fue el tercer intento: los dos primeros se cortaron en el paso 2. Tempo se reiniciaba por OOMKilled con 1 GiB (subido a 2 GiB por GitOps, `e5a3387`), y además un `\r` de `jq.exe` en Windows quedaba pegado al `trace_id`. Las capturas `recorrido-1…3` muestran el mismo camino en Grafana.

## 5. Tiempo de recuperación

| Fallo | Quién o qué lo resolvió | Tiempo |
|---|---|---|
| A | **Argo Rollouts, sin intervención:** abortó a las 19:10:45 (2 mediciones fallidas > `failureLimit` 1) y dejó el 100 % en la estable `695fddc58d` | **2 min 29 s** desde el inicio del canary |
| B | **La operadora, por GitOps** (`c56b28d`, 20:23:30): ArgoCD aplicó a las 20:23:49 y las réplicas quedaron sanas en 16 s | Error de 5 min < 0.5 % a los **5 min 11 s**; alerta resuelta a los 5 min 12 s |

## 6. Alerta faltante o sobrante

**Faltante:** ninguna alerta sonó durante los 29 minutos en que la mitad de las peticiones a `/books` fallaba, aunque la métrica lo mostraba a los 13 s. Un nivel de **consumo muy rápido** (burn rate > 50 en 5 min y en 1 min) lo habría avisado en 2 a 3 minutos sin disparar por picos breves.

**Sobrante:** `SLOLatenciaConsumoRapido` disparó junto con la de disponibilidad por el mismo fallo (la espera de 400 ms). Es ruido para quien atiende: dos alertas críticas, una sola causa. Conviene inhibir la de latencia cuando la de disponibilidad del mismo servicio está activa (hoy solo se inhibe la sostenida del mismo SLO, y funcionó).

**Mejoras concretas a mi instrumentación,** todas descubiertas en esta prueba:
1. **`service.instance.id` por pod** (ya aplicada en 1.1.2). Sin él, las réplicas mezclaban contadores y `rate()` daba 133 peticiones/s donde había 9.
2. **El análisis cuenta desde el inicio del Rollout, no desde que el pod está listo.** Con `initialDelay` de 60 s, la primera promoción de una versión sana se abortó por consultas vacías; se subió a 120 s.
3. **Generador sin keep-alive.** Las conexiones persistentes no llegaban al pod nuevo (39 peticiones en 10 min); el canary nunca habría tenido datos.
4. **Pendiente:** loans-service devuelve los errores del catálogo como GraphQL con HTTP 200, invisibles para el SLO. Hay que contarlos como fallo.
