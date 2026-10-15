# Runbook: SLOLatenciaConsumoRapido

**Severidad:** critical (se atiende de inmediato) · **SLO:** 95 % de las peticiones en menos de 300 ms, 30 días

## Qué significa

En la última hora y en los últimos 5 minutos, más del 72 % de las peticiones
de usuario tardaron más de 300 ms. El sistema puede no estar devolviendo
errores, pero para el usuario es inutilizable.

## Por qué hay que intervenir

La lentitud no la corrige ningún mecanismo automático: el HPA escala por CPU,
y una espera en la base de datos o en otro servicio no consume CPU.

## Pasos (objetivo: menos de 3 minutos)

1. Tablero *Biblioteca: operación* → fila **Latencia** → *p95 por servicio*.
   El servicio interno cuya curva sube junto con la del gateway es el origen.
2. Tempo → *Search*: `service.name = api-gateway`, *Min duration* `300ms`.
   Abrir una traza: la barra más larga indica dónde se va el tiempo
   (consulta SQL lenta en el span `pg`, llamada HTTP a otro servicio, espera
   sin hijos = tiempo dentro del propio código).
3. Desde el span, *Logs for this span*: los registros con el mismo `trace_id`
   explican la espera (timeouts, reintentos, pool agotado).
4. Fila **Saturación**: CPU al límite (throttling) explica una lentitud
   general; si la CPU está baja, el cuello de botella es una dependencia.

## Mitigación

| Causa | Acción |
|---|---|
| Cambio reciente | Revertir en el repositorio GitOps. |
| CPU al límite | Subir `limits.cpu` o `maxReplicas` por Pull Request. |
| Base de datos lenta | `kubectl -n sa-p8 top pod`; revisar el pod de PostgreSQL. |
| Registro con `causa=fallo-inducido-p10` | Desactivar el bloque `fault` del servicio en el repositorio GitOps. |

## Cómo saber que terminó

p95 del gateway por debajo de 300 ms en el tablero y la alerta en *resolved*.
