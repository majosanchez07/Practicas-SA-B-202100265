# Runbook: SLOLatenciaConsumoSostenido

**Severidad:** warning (se atiende el mismo día) · **SLO:** 95 % de las peticiones en menos de 300 ms, 30 días

## Qué significa

Durante 6 horas, y en los últimos 30 minutos, más del 30 % de las peticiones
tardaron más de 300 ms. Es una degradación que ya llegó a todos los usuarios:
el canary no la detuvo (no ocurrió durante una promoción, o la regresión es
menor que el umbral de 500 ms del análisis).

## Por qué hay que intervenir

A este ritmo el presupuesto de latencia se agota en unos 5 días. Las
degradaciones lentas suelen deberse a algo que crece: tablas sin índice que
aumentan con cada préstamo, memoria que se acumula, colas que no se vacían.

## Pasos

1. Tablero con rango de **24 horas**, fila **Latencia**: ¿la curva subió de
   golpe (cambio desplegado) o crece poco a poco (algo que se acumula)?
2. De golpe → ArgoCD *History* de `sa-platform` y fila **Entrega
   progresiva** para identificar la versión; revertir en GitOps.
3. Poco a poco → Tempo, trazas de más de 300 ms: si el span lento es una
   consulta `pg`, revisar el crecimiento de la tabla correspondiente; fila
   **Saturación** para memoria creciente.

## Mitigación

Revertir la versión responsable, o abrir un Pull Request con la corrección
(índice, límite de memoria, réplicas). Ningún cambio se aplica a mano en el
clúster.

## Cómo saber que terminó

La ventana de 30 minutos baja del 30 % de peticiones lentas y la alerta pasa
a *resolved*.
