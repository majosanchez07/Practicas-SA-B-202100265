# Runbook: SLODisponibilidadConsumoSostenido

**Severidad:** warning (se atiende el mismo día) · **SLO:** disponibilidad 99.5 % en 30 días

## Qué significa

Durante 6 horas, y también en los últimos 30 minutos, más del 3 % de las
peticiones de usuario fallaron. Es un fallo parcial: no tan grave como para
disparar la alerta crítica, pero sostenido. A este ritmo (6 veces lo
sostenible) el presupuesto mensual se agota en unos 5 días.

Si la alerta crítica del mismo SLO está activa, Alertmanager silencia esta
(regla de inhibición): no aporta información adicional.

## Por qué hay que intervenir

Un error pequeño y constante no se ve a simple vista en el tablero, pero gasta
el 5 % del presupuesto cada 6 horas. Suele ser un problema que afecta a una
sola ruta o a una fracción de las réplicas.

## Pasos

1. Tablero *Biblioteca: operación* → ajustar el rango a **últimas 6 horas**.
2. Fila **Errores**: ¿el error es constante o aparece por ráfagas?
   - Constante en una ruta → defecto funcional (seguir pasos 3 y 4 del runbook
     de consumo rápido para llegar al registro).
   - Por ráfagas → cruzar con la fila **Saturación**: picos de CPU al límite
     o réplicas en el máximo del HPA indican falta de capacidad.
3. Fila **Tráfico** → *Préstamos rechazados por motivo*: si crece
   `catalogo_no_disponible`, loans-service no logra hablar con books-service.
4. Fila **Entrega progresiva**: dos `rollout_hash` distintos durante horas
   indican un Rollout detenido a mitad de camino (`kubectl argo rollouts get
   rollout sa-platform-api-gateway -n sa-p8`).

## Mitigación

- Defecto funcional: revertir el último cambio en el repositorio GitOps.
- Capacidad: subir `maxReplicas` o los `limits` del servicio en
  `environments/prod/values.yaml` (vía Pull Request).
- Rollout detenido: `kubectl argo rollouts abort` o `promote` según lo que
  muestre el análisis.

## Cómo saber que terminó

La ventana de 30 minutos baja de 3 % y la alerta pasa a *resolved*. La de 6
horas seguirá alta un tiempo: es esperado, y por eso la alerta exige las dos.
