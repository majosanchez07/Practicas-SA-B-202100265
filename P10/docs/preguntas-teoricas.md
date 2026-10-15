# Preguntas teóricas

Práctica 10 · María José Tebalán Sánchez · 202100265

Respuestas sobre el comportamiento de esta instrumentación concreta, incluidos
sus límites.

### 1. ¿Por qué el análisis del canary filtra por `rollout_hash` y no consulta el Service canary?

Sin mesh ni ingress con pesos, Argo Rollouts reparte el tráfico por número de
réplicas, y el Service ordinario envía peticiones a ambas versiones. Una
métrica sin filtro promediaría estable y candidata: con 20 % de peso, un 15 %
de error en la candidata se vería como 3 % en total. El hash del ReplicaSet
llega al pod por la *downward API*, el SDK lo publica como atributo de recurso
y el Collector lo convierte en etiqueta: así el análisis mide solo la versión
nueva.

**Límite:** el peso real depende del redondeo de réplicas. Con 3 réplicas,
"20 %" puede ser 1 de 4 pods (25 %). El análisis no se ve afectado porque mide
la tasa de la candidata, no su volumen.

### 2. ¿Qué pasa si no hay tráfico durante el canary?

Las consultas devuelven un vector vacío o NaN, la condición
`len(result) > 0 && !isNaN(result[0])` es falsa y la medición cuenta como
**fallo**: la versión se revierte. Es deliberado: sin evidencia no se aprueba.
El generador de tráfico existe para que eso no ocurra en este entorno.

**Límite:** el generador es un usuario sintético. Si las rutas que ejercita no
incluyen la que rompe una versión (por ejemplo `/auth`), el canary no lo
detecta. En producción el tráfico real cubriría todas las rutas.

### 3. ¿Por qué alertas por consumo del presupuesto y no por umbral?

Un umbral (error > 1 % en 5 min) dispara con un pico de un minuto y se apaga
solo: entrena a ignorar alertas. El burn rate pregunta "¿a este ritmo, cuándo
incumplo lo que prometí?". Exigir dos ventanas filtra los picos (la larga) y
apaga la alerta en cuanto se corrige (la corta).

**Límite:** la ventana de 1 hora retrasa la detección de fallos que empiezan
de golpe (unos 10 minutos en el fallo B). Es el precio de no alertar por
ruido, y se discute en el informe de operación.

### 4. ¿Cómo se llega de una traza a sus registros y al revés?

Los registros llevan `trace_id` tomado del span activo en el momento de
escribir. En Grafana, Tempo tiene configurado `tracesToLogsV2` (busca en Loki
la cadena del `trace_id`) y Loki tiene un *derived field* que convierte el
campo en enlace a Tempo.

**Límite:** un registro escrito fuera de un span (al arrancar, en el
reintento de conexión al broker) no tiene `trace_id`. Y si el muestreo
descartara una traza, su registro apuntaría a una traza inexistente; por eso
se usa muestreo del 100 %, aceptable con este volumen pero no en producción.

### 5. ¿Qué no ve esta instrumentación?

- **auth-service y notifications-service** no están instrumentados (la
  consigna pide tres). Un fallo en el inicio de sesión se ve en el gateway
  (`/auth` con 5xx), pero no hay traza dentro del servicio.
- **Errores GraphQL con HTTP 200**: un préstamo rechazado porque el catálogo
  falla cuenta como éxito para el SLO. Solo lo muestra la métrica de negocio.
- **El consumo asíncrono**: loans-service inyecta el contexto en el mensaje de
  RabbitMQ, pero notifications-service no lo extrae; la traza termina al
  publicar.
- **Lo que pasa antes del gateway**: un fallo en el balanceador de Azure no
  genera ninguna petición, y por lo tanto ningún error. Una caída total se ve
  como *tráfico cero*, no como error; el panel de tráfico lo muestra, pero
  ninguna alerta lo cubre.

### 6. ¿Por qué el Collector y no exportar directo a cada backend?

Los servicios solo conocen un destino (OTLP). Cambiar Tempo por Jaeger, o
añadir un segundo backend, es un cambio de configuración del Collector, sin
reconstruir imágenes. Además, el Collector elimina los atributos de proceso y
host que agregan los SDK antes de exponer métricas, evitando series nuevas en
cada reinicio.

**Límite:** es un punto único de fallo para trazas y métricas (una réplica).
Por eso los registros no pasan por él.

### 7. ¿Qué indica cada fila del tablero sobre las cuatro señales de oro?

| Señal | Fila | Pregunta que responde |
|---|---|---|
| Latencia | Latencia | ¿Cuánto esperan los usuarios y qué servicio los hace esperar? |
| Tráfico | Tráfico | ¿Cuánto se usa y qué logra el negocio (préstamos)? |
| Errores | Errores | ¿Qué funcionalidad falla, en qué servicio y con qué registro? |
| Saturación | Saturación | ¿Cuánto falta para quedarse sin CPU, memoria o réplicas? |

Arriba de todo está el estado de los SLO, que resume las cuatro en lo que le
importa a quien no es ingeniero: si se está cumpliendo lo prometido y cuánto
margen queda.
