# Evidencia preliminar — Cronjobs encadenados validados en local

> Prueba del código de ambos cronjobs antes del despliegue en Kubernetes.
> La evidencia sobre el clúster, con los `schedule` reales, se documenta después.

Las imágenes se ejecutaron con `--read-only --user 1000:1000`, es decir, en las
mismas condiciones que impone el `securityContext` del chart.

## 1. Cronjob 1 — fecha GMT-6 y carné

```
[cronjob-insert] registro #1 | carne 202100265 | 2026-08-27 09:22:43 GMT-6
[cronjob-insert] registro #2 | carne 202100265 | 2026-08-27 09:22:45 GMT-6
[cronjob-insert] registro #3 | carne 202100265 | 2026-08-27 09:22:46 GMT-6
[cronjob-insert] registro #4 | carne 202100265 | 2026-08-27 09:22:47 GMT-6
[cronjob-insert] registro #5 | carne 202100265 | 2026-08-27 09:22:49 GMT-6
  -> exit code: 0
```

Contenido de la tabla:

```
 id |   carne   |        fecha_texto        |     origen
----+-----------+---------------------------+----------------
  1 | 202100265 | 2026-08-27 09:22:43 GMT-6 | cronjob-insert
  ...
```

## 2. Cronjob 2 — agregación por hora y publicación en el broker

```
[cronjob-summary] resumen publicado en 'resumen.generado' | carne 202100265 | total 5 | 2026-08-27 09:00=5
  -> exit code: 0
```

### Corrección de un error de zona horaria

La primera versión agrupaba en la hora `21:00` para registros de las `09:22`
GMT-6. La causa era la expresión `AT TIME ZONE 'UTC-6'`: en la sintaxis POSIX
que acepta PostgreSQL, `UTC-6` significa UTC**+**6, de modo que el
desplazamiento se aplicaba en sentido contrario. Comprobación:

```
 ejecutado_en (UTC)  : 2026-08-27 15:22:43+00
 AT TIME ZONE UTC-6  : 2026-08-27 21:22:43     <- incorrecto
 AT TIME ZONE UTC+6  : 2026-08-27 09:22:43
 America/Guatemala   : 2026-08-27 09:22:43     <- correcto
```

Se adoptó `America/Guatemala`, que es GMT-6 permanente y además expresa la
intención de forma legible. Tras la corrección el resumen agrupa en `09:00`.

## 3. Cadena completa

`Cronjob 1 -> BD -> Cronjob 2 -> broker -> notifications-service -> BD`

```
[consumer] resumen almacenado (5 ejecuciones)

 id |   carne   | totalEjecuciones |                    detalle
----+-----------+------------------+-----------------------------------------------
  2 | 202100265 |                5 | [{"hora": "2026-08-27 09:00", "cantidad": 5}]
```

## 4. Resiliencia con el consumidor caído

Se detuvo notifications-service y se ejecutaron ambos cronjobs:

```
[cronjob-insert] registro #6 | carne 202100265 | 2026-08-27 09:23:57 GMT-6
[cronjob-insert] registro #7 | carne 202100265 | 2026-08-27 09:23:58 GMT-6
[cronjob-insert] registro #8 | carne 202100265 | 2026-08-27 09:24:00 GMT-6
[cronjob-summary] resumen publicado ... | total 8 | 2026-08-27 09:00=8
  -> exit code: 0
```

El Cronjob 2 terminó correctamente pese a que el consumidor estaba caído, y el
resumen quedó retenido en la cola durable:

```
name                      messages  durable
notifications.queue       1         true
```

Al restaurar notifications-service el mensaje se procesó:

```
[consumer] resumen almacenado (8 ejecuciones)

 id | totalEjecuciones |                    detalle
----+------------------+-----------------------------------------------
  3 |                8 | [{"hora": "2026-08-27 09:00", "cantidad": 8}]
```

No se perdió ningún resumen.
