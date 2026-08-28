# Tabla comparativa del tamaño de las imágenes

Medición realizada con `docker image inspect --format '{{.Size}}'`, que reporta
el tamaño real de cada imagen. Se prefiere sobre la columna de `docker images`
porque esta última contabiliza capas compartidas dentro de cada fila.

- **Antes:** Dockerfiles heredados de la Práctica 4 (conservados en cada servicio
  como `Dockerfile.p4-original` para poder reproducir la medición).
- **Después:** Dockerfiles multi-stage con base mínima y usuario sin privilegios.

| Servicio | Lenguaje | Antes | Después | Ahorro | Reducción |
|---|---|---:|---:|---:|---:|
| `api-gateway` | Node.js | 52 MB | 50 MB | 1 MB | 3% |
| `auth-service` | Python | 163 MB | 73 MB | 89 MB | 54% |
| `books-service` | Python | 151 MB | 63 MB | 87 MB | 57% |
| `loans-service` | Node.js | 71 MB | 55 MB | 15 MB | 21% |
| `notifications-service` | Node.js | 56 MB | 52 MB | 4 MB | 7% |
| **TOTAL** | | **494 MB** | **296 MB** | **197 MB** | **40%** |

## Qué produjo la reducción

**Servicios en Python (54% y 57% menos).** Es donde estaba el problema grande.
El Dockerfile de la Práctica 4 instalaba `gcc`, `libpq-dev` y `python3-dev` para
poder compilar las ruedas de `psycopg` y de las librerías de criptografía, pero
esas herramientas se quedaban dentro de la imagen final aunque solo hacían falta
durante la instalación. Con multi-stage la compilación ocurre en la etapa
`builder` y a la imagen final solo se copia el prefijo `/install` ya resuelto,
junto con `libpq5`, que es la única biblioteca que se necesita en ejecución.

En `auth-service` se eliminó además una dependencia duplicada: el
`requirements.txt` declaraba `psycopg[binary]` (v3) y `psycopg2` (v2) a la vez,
de modo que se instalaban dos drivers de Postgres y el segundo se compilaba
desde el código fuente.

**Servicios en Node.js (3% a 21%).** La base `node:alpine` ya era pequeña, así
que el margen era menor. La mejora viene de instalar solo dependencias de
producción (`npm ci --omit=dev`) en una etapa aparte y copiar el `node_modules`
resuelto, dejando fuera el caché de npm y los archivos intermedios. En
`loans-service` la diferencia es mayor porque era el que arrastraba más
dependencias de desarrollo.

## Endurecimiento aplicado además del tamaño

Las imágenes se construyeron para poder cumplir el `securityContext` que exige
el enunciado, y se verificó que efectivamente lo soportan:

| Servicio | Usuario | UID | Arranca con `--read-only` |
|---|---|---:|---|
| `api-gateway` | `node` | 1000 | Sí |
| `auth-service` | `appuser` | 1000 | Sí |
| `books-service` | `appuser` | 1000 | Sí |
| `loans-service` | `node` | 1000 | Sí |
| `notifications-service` | `node` | 1000 | Sí |

La comprobación se hizo levantando cada contenedor con `--read-only --user 1000:1000`
contra una instancia real de PostgreSQL. Los servicios en Python arrancaron
correctamente y crearon su schema:

```
=== auth-service contra Postgres real, rootfs RO, uid 1000 ===
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000

=== Probes desde dentro del contenedor read-only ===
/health/live     -> 200 {"status":"alive"}
/health/ready    -> 200 {"status":"ready","database":"up"}

=== Schemas creados ===
 auth   | t
 books  | t
```

Los servicios en Node.js incorporan `dumb-init` como punto de entrada. Sin él,
`node` corre como PID 1 y no recibe `SIGTERM`, por lo que Kubernetes tendría que
terminar el pod por la fuerza al agotarse el `terminationGracePeriod` en cada
rolling update — justo la caída de servicio que el enunciado pide evitar.
