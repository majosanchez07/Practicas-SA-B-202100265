# Práctica 7 — Integración y despliegue continuo (CI/CD)

**María José Tebalán Sánchez — 202100265**
Software Avanzado, Segundo Semestre 2026

Pipeline de CI/CD que toma la plataforma de microservicios de las Prácticas 5 y
6 y automatiza su ciclo completo: de un `git push` a un despliegue verificado en
Kubernetes, sin intervención manual.

```
commit → versión → build → test → docker + push a GHCR → despliegue k8s → verificación
```

**Estado: pipeline verde de punta a punta.** Ejecución #3 (commit `d65fdf3`):
las seis etapas correctas en 4m 31s, con las 7 imágenes publicadas en GHCR y el
despliegue en Kubernetes verificado en 2m 40s. Evidencia en
[`docs/evidencias/`](docs/evidencias/).

---

## Contenido

| Ruta | Descripción |
|---|---|
| [`.github/workflows/p7-cicd.yml`](../.github/workflows/p7-cicd.yml) | **El pipeline** — archivo central de la práctica |
| [`docs/flujo-cicd.md`](docs/flujo-cicd.md) | Documentación técnica del flujo |
| [`docs/diagrama-pipeline.md`](docs/diagrama-pipeline.md) | Diagramas del pipeline y sus fases |
| [`docs/pruebas.md`](docs/pruebas.md) | Qué cubren las 105 pruebas unitarias |
| [`docs/preguntas-teoricas.md`](docs/preguntas-teoricas.md) | Respuestas a las 5 preguntas del enunciado |
| [`docs/evidencias/`](docs/evidencias/) | Evidencias de ejecución y despliegue |
| [`services/`](services/) | Los 5 microservicios, ahora **con pruebas unitarias** |
| [`cronjobs/`](cronjobs/) | Los 2 cronjobs heredados de la P5 |
| [`charts/sa-platform/`](charts/sa-platform/) | Chart de Helm |
| [`charts/sa-platform/values-ci.yaml`](charts/sa-platform/values-ci.yaml) | Valores del ambiente del pipeline |
| [`scripts/`](scripts/) | Reproducir el pipeline localmente |

---

## Las cuatro fases

| Fase | Job | Qué hace |
|---|---|---|
| **Build** | `build-node`, `build-python` | `npm ci` + `node --check`; `pip install` + `compileall` |
| **Test** | `test-node`, `test-python` | 105 pruebas unitarias, con cobertura en Python |
| **Dockerización** | `docker` | 7 imágenes multietapa, etiquetadas y publicadas en GHCR |
| **Despliegue** | `desplegar` | Clúster kind + `helm upgrade --install` + verificación |

Precedidas por una etapa 0 que calcula la versión común a toda la ejecución, y
cerradas por un resumen del resultado.

Las dependencias entre jobs (`needs:`) no son decorativas: **si una prueba falla,
ninguna imagen se publica y el clúster no se toca**.

---

## Qué se agregó respecto a la Práctica 6

| | P6 | P7 |
|---|---|---|
| Construcción de imágenes | Script manual contra ECR | Automática en cada push, a GHCR |
| Pruebas | Ninguna | 105 pruebas unitarias, obligatorias antes de publicar |
| Despliegue | `helm install` a mano | Automático, con verificación y evidencia |
| Versionado | Tag manual | Calculado del commit o del tag de git |
| Evidencia | Capturas tomadas a mano | Artefacto generado en cada ejecución |

El chart de Helm es **el mismo**. Solo cambió el archivo de valores
(`values-ci.yaml`), que es justamente la demostración de que estaba bien
parametrizado.

---

## Pruebas unitarias

| Servicio | Pruebas | Qué cubre principalmente |
|---|---|---|
| `api-gateway` | 19 | Reenvío de peticiones, cuerpo de los POST, manejo de servicios caídos |
| `auth-service` | 38 | Cifrado AES, JWT y período de gracia |
| `books-service` | 17 | Esquema y resolvers GraphQL contra SQLite en memoria |
| `loans-service` | 20 | Publicación de eventos, durabilidad, probes de salud |
| `notifications-service` | 15 | Procesamiento de eventos, `ack` manual y DLQ |
| **Total** | **105** | |

Ninguna necesita PostgreSQL ni RabbitMQ: las dependencias externas se sustituyen
por dobles. Detalle completo en [`docs/pruebas.md`](docs/pruebas.md).

---

## Uso

### Disparar el pipeline

```bash
# Cualquier cambio dentro de P7/ sobre main lanza el pipeline completo
git add P7/ && git commit -m "..." && git push

# Publicar una versión semántica
git tag -a v1.0.0 -m "Primera version estable de la P7"
git push origin v1.0.0
```

También puede lanzarse manualmente desde la pestaña **Actions** → **P7 - CI/CD**
→ **Run workflow**.

### Reproducirlo localmente

```bash
# Las mismas pruebas que la etapa 2, antes de hacer commit
./P7/scripts/pruebas-locales.sh

# La etapa 4 completa en un kind local
./P7/scripts/desplegar-local.sh

# Consultar el gateway desplegado
kubectl port-forward -n sa-p7 svc/sa-platform-api-gateway 8080:8080

# Eliminar el clúster
./P7/scripts/desplegar-local.sh --eliminar
```

Requisitos para el despliegue local: `docker`, `kind`, `kubectl` y `helm`.

---

## Nota sobre el despliegue

El enunciado pide desplegar en Kubernetes. Siguiendo la indicación del auxiliar
de que el despliegue puede ser local y que lo importante es el flujo de git, la
etapa 4 crea un **clúster kind efímero dentro del propio runner** en lugar de
usar un clúster en la nube.

La elección conserva lo que la práctica evalúa —que el pipeline aplique los
cambios en Kubernetes sin intervención manual— y lo verifica de extremo a
extremo en cada ejecución, incluida la descarga real de las imágenes desde GHCR,
sin depender de una cuenta de nube encendida ni de que una máquina local esté
disponible al momento de calificar. El chart, los manifiestos y las imágenes son
exactamente los mismos que se usarían contra un clúster permanente.

Adicionalmente, [`scripts/desplegar-local.sh`](scripts/desplegar-local.sh)
reproduce esa misma etapa en una máquina propia para demostrarla en vivo.
