# Objetivos de nivel de servicio (SLO)

Práctica 10 · María José Tebalán Sánchez · 202100265

Ambos SLO se miden **en el api-gateway**, que es por donde pasa todo lo que
pide un usuario. Lo que importa es lo que el usuario recibe, no lo que cada
microservicio dice de sí mismo: books-service puede estar sano y el usuario
recibir un 502 porque el gateway no lo alcanza.

Las peticiones de las sondas de Kubernetes (`/health/*`) se excluyen en el
código: no las hace ningún usuario y, como siempre responden rápido,
inflarían el indicador.

## SLO-1: disponibilidad

| | |
|---|---|
| **Enunciado para el usuario** | 995 de cada 1000 acciones (consultar el catálogo, pedir un préstamo) terminan sin un error del sistema. |
| **Indicador (SLI)** | Peticiones del gateway con código distinto de 5xx ÷ peticiones totales del gateway |
| **Objetivo** | 99.5 % |
| **Ventana** | Móvil de 30 días |
| **Presupuesto de error** | 0.5 % de las peticiones del mes; equivale a 3.6 horas de caída total en 30 días |
| **Reglas** | `slo:sli_errores:ratio_rate{5m,30m,1h,6h,1d,30d}`, `slo:presupuesto_consumido:ratio{slo="disponibilidad"}` |

**Por qué 99.5 % y no otro número**

- **No 99.9 %.** El sistema corre en un clúster de dos nodos, con una sola
  réplica de PostgreSQL y de RabbitMQ (Práctica 9). La prueba de desastre de la
  P9 midió un RTO de 13 a 15 minutos; con un solo incidente así al mes, 99.9 %
  (43 minutos de presupuesto) quedaría casi agotado. Prometer lo que la
  arquitectura no puede sostener convierte el SLO en una alerta permanente.
- **No 99 %.** Un 1 % de fallos es una de cada cien acciones: un usuario que
  usa el sistema a diario lo vería varias veces por semana. Para una
  biblioteca, donde el usuario puede reintentar sin perder nada, 0.5 % es el
  punto en el que el fallo sigue siendo raro sin exigir alta disponibilidad
  multi-zona.
- **Los 5xx y no los 4xx.** Un 404 por un libro que no existe o un 401 por
  una contraseña incorrecta es el sistema funcionando bien.

## SLO-2: latencia

| | |
|---|---|
| **Enunciado para el usuario** | 95 de cada 100 acciones responden en menos de 0.3 segundos. |
| **Indicador (SLI)** | Peticiones del gateway con duración ≤ 300 ms ÷ peticiones totales del gateway (cubo `le="0.3"` del histograma) |
| **Objetivo** | 95 % |
| **Ventana** | Móvil de 30 días |
| **Presupuesto de error** | 5 % de las peticiones pueden superar 300 ms |
| **Reglas** | `slo:sli_lentas:ratio_rate{5m,30m,1h,6h,1d,30d}`, `slo:presupuesto_consumido:ratio{slo="latencia"}` |

**Por qué 300 ms y 95 %**

- **300 ms.** Es el tiempo por debajo del cual una acción en una página web se
  percibe como inmediata. En la Práctica 8 la prueba de carga midió un p95 de
  122 ms en el gateway: 300 ms deja margen de más del doble sobre lo medido,
  de modo que el SLO no se incumple por variación normal, pero sí cuando una
  regresión duplica o triplica los tiempos.
- **95 % y no 99 %.** Crear un préstamo atraviesa tres servicios, PostgreSQL y
  RabbitMQ; el p99 incluye arranques en frío de pods recién escalados por el
  HPA y las primeras consultas tras un reinicio. Exigir el 99 % obligaría a
  atender alertas por efectos que el usuario apenas nota.
- **Umbral explícito del histograma.** Los SDK declaran `0.3` como límite de
  cubo. Si el umbral del SLO cayera entre dos cubos, el indicador sería una
  interpolación, no una medición.

## Relación con el canary

El análisis del canary usa umbrales **más tolerantes** (1 % de error, p95 de
500 ms) que los del SLO, a propósito: mide una ventana de un minuto sobre el
20 % del tráfico, con pocas muestras, donde un solo pico pesa mucho. Su
función es detener regresiones evidentes antes de que lleguen a todos; el SLO
mide lo que los usuarios vivieron en 30 días.

## Alertas

Detalle en [prometheusrules.yaml](../charts/sa-platform/templates/prometheusrules.yaml)
y pruebas en [alertas.test.yaml](../tests/slo/alertas.test.yaml).

| Alerta | Condición | Severidad | Tiempo hasta agotar el presupuesto |
|---|---|---|---|
| `SLODisponibilidadConsumoRapido` | burn rate > 14.4 en 1 h **y** en 5 min | critical | ~2 días |
| `SLODisponibilidadConsumoSostenido` | burn rate > 6 en 6 h **y** en 30 min | warning | ~5 días |
| `SLOLatenciaConsumoRapido` | burn rate > 14.4 en 1 h **y** en 5 min | critical | ~2 días |
| `SLOLatenciaConsumoSostenido` | burn rate > 6 en 6 h **y** en 30 min | warning | ~5 días |

**Alertas eliminadas** y por qué:

| Eliminada | Motivo |
|---|---|
| ~150 reglas por defecto de kube-prometheus-stack (CPU, memoria, reinicios, cuotas, objetivos caídos) | Son umbrales instantáneos sobre la infraestructura. Si un pod reinicia y el usuario no lo nota, no hay nada que hacer; si lo nota, la alerta de SLO lo recoge. |
| Alertas de *ticket* (burn rate 1 a 3 en 1 a 3 días) | Nadie las atendería antes de que el presupuesto mensual se recupere solo; el tablero muestra el presupuesto restante para la revisión semanal. |
| Error del gateway > 1 % en 5 minutos | Umbral instantáneo: se dispara con un pico de un minuto (un pod que reinicia) y se apaga solo. Es exactamente el ruido que la consigna pide eliminar. |
