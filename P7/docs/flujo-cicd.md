# Documentación técnica del flujo CI/CD

**María José Tebalán Sánchez — 202100265**
Software Avanzado, Segundo Semestre 2026

Este documento explica el pipeline de integración y despliegue continuo
implementado en [`.github/workflows/p7-cicd.yml`](../../.github/workflows/p7-cicd.yml):
qué hace cada etapa, por qué está construida así y qué garantiza el resultado.

---

## 1. Qué problema resuelve

Hasta la Práctica 6, llevar un cambio de código al clúster exigía una secuencia
manual de diez pasos: construir siete imágenes, etiquetarlas, autenticarse
contra el registro, publicarlas, actualizar el `values`, instalar el chart y
verificar los pods. Cada paso podía olvidarse o ejecutarse con una versión
distinta de las demás, y nada obligaba a ejecutar las pruebas antes de publicar.

El pipeline convierte esa secuencia en una consecuencia automática de hacer
`git push`. Un commit en `main` dispara el flujo completo, y si las pruebas
fallan, la imagen no se publica y el clúster no se toca.

---

## 2. El flujo en una línea

```
commit → versión → build → test → docker + push → despliegue k8s → verificación
```

Cada flecha es una dependencia real declarada con `needs:` en el workflow. Esto
no es decorativo: es lo que hace que una prueba en rojo detenga la publicación
de la imagen. Sin esa dependencia, los jobs correrían en paralelo y se podría
publicar una imagen con pruebas fallando.

El diagrama visual completo está en
[`diagrama-pipeline.md`](diagrama-pipeline.md).

---

## 3. Disparadores (`on:`)

| Disparador | Cuándo ocurre | Qué hace |
|---|---|---|
| `push` a `main` | Se integra un cambio | Pipeline completo, incluido el despliegue |
| `push` a `develop` | Trabajo en curso | Build, test, docker (sin despliegue) |
| `push` de tag `v*.*.*` | Se publica una versión | Pipeline completo, con versión semántica |
| `pull_request` a `main` | Se propone un cambio | Build, test y construcción de imagen **sin publicar** |
| `workflow_dispatch` | Manual | Pipeline completo, para demostrar la ejecución |

Dos filtros acotan cuándo corre:

**`paths:`** — el pipeline solo se activa si cambió algo dentro de `P7/` o el
propio workflow. Sin esto, editar el README de la Práctica 3 lanzaría una
ejecución completa de quince minutos sin ninguna razón.

**`concurrency:`** — un push nuevo sobre la misma rama cancela la ejecución
anterior. Si se hacen tres commits seguidos, solo el último llega al clúster; los
dos anteriores ya quedaron obsoletos y desplegarlos sería gastar minutos de
runner para instalar código que nadie va a usar.

---

## 4. Las etapas

### Etapa 0 — Versión

Calcula **una sola vez** la versión que usará todo el pipeline, y la expone a
los demás jobs mediante `outputs`.

El esquema depende del disparador:

| Referencia | Versión resultante |
|---|---|
| tag `v1.2.0` | `1.2.0` |
| rama `main` | `main-a1b2c3d` |
| rama `develop` | `develop-a1b2c3d` |

La razón de centralizarlo es concreta: si cada job calculara su propia versión,
dos jobs que empiezan en segundos distintos podrían generar etiquetas diferentes,
y el despliegue terminaría combinando el `auth-service` de una ejecución con el
`books-service` de otra. Calculándolo una vez, las siete imágenes de una misma
ejecución comparten exactamente el mismo tag.

También convierte el nombre del repositorio a minúsculas, porque GHCR rechaza
mayúsculas en el nombre de una imagen y el usuario de GitHub puede tenerlas.

### Etapa 1 — Build

Se divide en dos jobs paralelos según el lenguaje, cada uno con una matriz:

- **`build-node`** — `api-gateway`, `loans-service`, `notifications-service`
- **`build-python`** — `auth-service`, `books-service`, `cronjob-insert`, `cronjob-summary`

En Node se instala con `npm ci` (reproducible: respeta el `package-lock.json` en
lugar de resolver versiones nuevas) y se verifica cada módulo con `node --check`.
En Python se instala `requirements.txt` y se ejecuta `python -m compileall`.

En ambos casos se trata del equivalente a compilar en un lenguaje interpretado:
un error de sintaxis se detecta aquí, en segundos, en lugar de cinco minutos
después al construir la imagen Docker, o —peor— al arrancar el pod en el clúster.

`fail-fast: false` es deliberado: si dos servicios tienen problemas, interesa ver
ambos en la misma ejecución y no solo el primero que falló.

La auditoría de vulnerabilidades (`npm audit`) corre con `continue-on-error`:
informa sin bloquear. Una vulnerabilidad en una dependencia transitiva es
información valiosa, pero no una razón para impedir la entrega.

### Etapa 2 — Test

Ejecuta las pruebas unitarias de los cinco microservicios. El detalle de qué
prueba cada suite está en [`pruebas.md`](pruebas.md).

Una decisión de diseño importante: **ninguna prueba necesita PostgreSQL ni
RabbitMQ**. Las dependencias externas se sustituyen por dobles y la base de
`books-service` es un SQLite en memoria. La alternativa habitual —levantar
contenedores de servicio en el runner— haría la etapa varias veces más lenta y
la volvería intermitente: un fallo esporádico al arrancar Postgres aparecería
como una prueba en rojo que en realidad no lo está, y ese tipo de ruido acaba
enseñando a ignorar los fallos del pipeline.

Los servicios Python generan además un reporte de cobertura que se publica como
artefacto de la ejecución.

### Etapa 3 — Dockerización y publicación

Construye y publica las siete imágenes en **GitHub Container Registry**
(`ghcr.io`), en paralelo mediante una matriz.

Puntos a destacar:

**Depende de `test-node` y `test-python`.** Esa dependencia es la que materializa
la promesa de la integración continua: si una prueba falla, ninguna imagen se
publica.

**En un pull request se construye pero no se publica** (`push: github.event_name != 'pull_request'`).
Interesa verificar que el `Dockerfile` sigue siendo válido, pero sin llenar el
registro de imágenes de ramas que quizá nunca se fusionen.

**No requiere ningún secreto configurado a mano.** La autenticación usa
`GITHUB_TOKEN`, un token efímero que Actions genera para cada ejecución y que
expira al terminar. Por eso el workflow funciona al clonarse el repositorio sin
ningún paso previo de configuración. Es también la razón de elegir GHCR sobre
Docker Hub, que habría exigido crear y rotar un token personal.

**Se usa `Dockerfile.prod` con `--target prod`**: la construcción multietapa
heredada de la Práctica 6, donde la imagen final no contiene ni el compilador ni
las dependencias de desarrollo, y corre como usuario sin privilegios.

**Cada imagen recibe varias etiquetas** mediante `docker/metadata-action`: la
versión de la ejecución, el SHA corto, y `latest` solo en la rama por defecto. Un
tag semántico genera además `1.2.0` y `1.2`, de modo que un consumidor puede
fijar el nivel de precisión que prefiera.

**La caché de capas** (`type=gha`) se guarda en el almacenamiento de Actions con
un ámbito por componente. Cuando solo cambia el código, las capas de
dependencias se reutilizan y la construcción baja de minutos a segundos.

### Etapa 4 — Despliegue automático en Kubernetes

Crea un clúster **kind efímero dentro del propio runner**, instala el chart de
Helm con las imágenes recién publicadas y verifica el resultado.

**Por qué un clúster efímero.** El objetivo de la práctica es demostrar que el
pipeline aplica los cambios en Kubernetes sin intervención manual. Un clúster
creado y destruido en cada ejecución permite verificar eso de extremo a extremo
—incluida la descarga real de las imágenes desde GHCR— sin depender de una
cuenta de nube encendida ni de que una máquina local esté disponible en el
momento de calificar. Lo que se ejercita es exactamente lo mismo que contra un
clúster permanente: el mismo chart, los mismos manifiestos y las mismas
imágenes. La única diferencia es cuánto vive el clúster.

Además, [`scripts/desplegar-local.sh`](../scripts/desplegar-local.sh) reproduce
esta misma etapa en una máquina propia, para poder demostrarla en vivo.

**Secuencia del job:**

1. `helm/kind-action` crea el clúster.
2. Se crea el namespace `sa-p7` y un `Secret` de tipo `docker-registry` con el
   mismo `GITHUB_TOKEN`. Hace falta porque las imágenes publicadas desde un
   repositorio privado nacen privadas: sin credenciales, los pods quedarían en
   `ImagePullBackOff`.
3. `helm upgrade --install` con `values-ci.yaml`, pasando el registro y el tag
   calculados en la etapa 0. Las credenciales se generan al vuelo con `openssl`:
   el clúster se destruye al terminar, así que no hay nada que rotar ni que
   guardar en la configuración del repositorio.
4. `--wait --timeout 12m` bloquea hasta que todos los pods estén listos.
5. [`verificar-despliegue.sh`](../scripts/verificar-despliegue.sh) comprueba el
   resultado (sección 6).
6. [`recolectar-evidencia.sh`](../scripts/recolectar-evidencia.sh) guarda el
   estado del clúster y lo publica como artefacto.

**Si algo falla**, un paso con `if: failure()` vuelca los eventos del namespace,
la descripción de los pods y los logs de todos los contenedores. Sin esto,
depurar un despliegue fallido significaría relanzar el pipeline a ciegas: el
clúster ya no existe para inspeccionarlo.

---

## 5. `values-ci.yaml`: adaptar el chart al runner

El chart es el mismo de la Práctica 6. Solo cambia el archivo de valores, y esa
es justamente la prueba de que estaba bien parametrizado. Las diferencias
frente a `values-dev.yaml`:

| Aspecto | `values-dev.yaml` | `values-ci.yaml` | Motivo |
|---|---|---|---|
| Réplicas | 1–2 con HPA | 1, sin autoescalado | El runner tiene 2 vCPU: con dos réplicas de cinco servicios los pods no alcanzan a programarse |
| `requests` | Moderados | Mínimos | En Kubernetes lo que decide si un pod cabe son los *requests*, no el consumo real |
| `pullPolicy` | `IfNotPresent` | `Always` | Se quiere que el clúster descargue de verdad la imagen recién publicada |
| `imagePullSecrets` | — | `ghcr-credenciales` | Las imágenes de GHCR son privadas |
| PDB | Activo | Desactivado | Con una réplica, `minAvailable: 1` impide cualquier desalojo |
| Ingress | nginx | Desactivado | kind no trae controlador; se verifica por `port-forward` |

### Un detalle que costó encontrar

El chart expone un valor propio `imageRegistry`, **distinto** de
`global.imageRegistry`. La diferencia importa: los valores bajo `global:` los
heredan también los subcharts de Bitnami. Al apuntar `global.imageRegistry` a
GHCR, PostgreSQL y RabbitMQ empezaban a buscarse como
`ghcr.io/<usuario>/<repo>/bitnamilegacy/postgresql`, donde obviamente no
existen, y quedaban en `ImagePullBackOff` hasta que el despliegue expiraba —sin
ningún mensaje que señalara la causa.

La solución fue agregar un valor local al chart, que el helper `sa-platform.image`
consulta antes que el global y que los subcharts no heredan. Así el pipeline
redirige únicamente los siete componentes propios, y las dependencias siguen
viniendo de Docker Hub.

---

## 6. Qué verifica el despliegue

`helm --wait` solo garantiza que las probes respondieron. Eso no es lo mismo que
una plataforma funcionando, así que
[`verificar-despliegue.sh`](../scripts/verificar-despliegue.sh) comprueba cinco
cosas más:

1. **Réplicas disponibles** — cada Deployment tiene tantas listas como declara.
2. **Reinicios** — ningún pod supera dos reinicios. Un pod puede figurar como
   `Running` y estar en un ciclo de reinicios que las probes aún no marcaron; el
   contador lo delata.
3. **Imágenes desplegadas** — se listan las imágenes efectivamente en uso. Es la
   comprobación que cierra el círculo: sin ella, el clúster podría estar
   sirviendo una versión anterior y el pipeline lo reportaría como exitoso.
4. **Prueba de humo** — se consulta al gateway por `port-forward`. Como su
   `/health/ready` consulta a los cuatro microservicios aguas abajo, una
   respuesta correcta confirma la cadena completa.
5. **CronJobs** — quedaron programados.

---

## 7. Versionamiento

Tres esquemas coexisten, cada uno para un propósito:

**Por rama y commit** (`main-a1b2c3d`) — cada integración en `main` produce una
versión única y trazable. El SHA permite volver del tag de la imagen al commit
exacto que la originó.

**Semántico por tag** (`v1.2.0` → `1.2.0`, `1.2`, `latest`) — para publicar una
versión estable:

```bash
git tag -a v1.0.0 -m "Primera version estable de la P7"
git push origin v1.0.0
```

**Por SHA** (`sha-a1b2c3d`) — etiqueta adicional que agrega
`docker/metadata-action` a toda imagen.

El tag `latest` se aplica **solo** desde la rama por defecto
(`enable={{is_default_branch}}`). Si cualquier rama pudiera moverlo, un push a
`develop` cambiaría lo que reciben quienes piden `latest`, que es exactamente el
descontrol de versiones que el versionamiento debe evitar.

---

## 8. Seguridad

- **Permisos mínimos** — el workflow declara `contents: read` y `packages: write`,
  y nada más. Por defecto `GITHUB_TOKEN` recibe permisos más amplios.
- **Sin secretos versionados** — no hay ninguna credencial en el repositorio. El
  token de registro lo genera Actions por ejecución; las contraseñas del clúster
  efímero se generan con `openssl` y mueren con él.
- **Imágenes sin privilegios** — heredado de la P6: usuario no root, sistema de
  archivos de solo lectura y `capabilities` eliminadas.
- **La evidencia no expone secretos** — `recolectar-evidencia.sh` registra los
  *nombres* de los `Secret`, nunca su contenido.

---

## 9. Cómo reproducirlo

```bash
# Ejecutar las mismas pruebas que la etapa 2, antes de hacer commit
./P7/scripts/pruebas-locales.sh

# Reproducir la etapa 4 completa en un kind local
./P7/scripts/desplegar-local.sh

# Consultar el gateway desplegado
kubectl port-forward -n sa-p7 svc/sa-platform-api-gateway 8080:8080

# Eliminar el clúster
./P7/scripts/desplegar-local.sh --eliminar
```

Para disparar el pipeline en GitHub basta con hacer push de cualquier cambio
dentro de `P7/`, o lanzarlo manualmente desde la pestaña **Actions** con
**Run workflow**.
