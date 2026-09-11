# Evidencias de ejecución — Práctica 7

**María José Tebalán Sánchez — 202100265**

Este documento reúne las evidencias de que el pipeline funciona. Se organizan en
dos bloques: la ejecución del pipeline en GitHub Actions y la verificación del
despliegue en Kubernetes.

---

## 1. Ejecución del pipeline en GitHub Actions

Las capturas de la pestaña **Actions** se agregan en
[`capturas/`](capturas/) conforme se ejecuta el pipeline. Lo que debe mostrar
cada una:

| Captura | Qué evidencia |
|---|---|
| `01-grafo-pipeline.png` | El grafo completo con las etapas encadenadas en verde |
| `02-etapa-test.png` | El detalle de la etapa de pruebas, con los casos ejecutados |
| `03-etapa-docker.png` | La construcción y publicación de las 7 imágenes |
| `04-paquetes-ghcr.png` | Las imágenes publicadas en GHCR con sus etiquetas |
| `05-etapa-despliegue.png` | El despliegue en Kubernetes y su verificación |
| `06-resumen.png` | El resumen del pipeline con el estado de cada etapa |

Cada ejecución del pipeline publica además un artefacto
`evidencia-despliegue-<sha>` con el estado completo del clúster, recolectado por
[`recolectar-evidencia.sh`](../../scripts/recolectar-evidencia.sh). Ese artefacto
es descargable desde la página de la ejecución y contiene lo mismo que el bloque
siguiente.

---

## 2. Despliegue verificado en Kubernetes

La carpeta [`despliegue-local/`](despliegue-local/) contiene la evidencia de una
ejecución real del despliegue, capturada con el mismo script que corre el
pipeline.

### Estado de los pods

Los cinco microservicios, PostgreSQL y RabbitMQ, todos listos:

```
NAME                                                READY   STATUS    RESTARTS
sa-platform-api-gateway-5dfdd8fb9-wvsx5             1/1     Running   0
sa-platform-auth-service-5cf475865b-nktr5           1/1     Running   2
sa-platform-books-service-74cb6f59d4-jbfg8          1/1     Running   2
sa-platform-loans-service-67d5d9c8f5-n7wcj          1/1     Running   2
sa-platform-notifications-service-76466f6f6b-ld7wz  1/1     Running   2
sa-platform-postgresql-0                            1/1     Running   0
sa-platform-rabbitmq-0                              1/1     Running   0
```

Los dos reinicios de los microservicios son esperados y no indican un problema:
la `startupProbe` de cada servicio falla mientras PostgreSQL termina de
inicializarse, y Kubernetes reinicia el contenedor hasta que la dependencia está
lista. Es el comportamiento correcto —el orden de arranque no se coordina a mano,
sino que cada servicio reintenta— y por eso el script de verificación tolera
hasta dos reinicios antes de considerarlo un fallo.

### Imágenes efectivamente desplegadas

```
TIPO         NOMBRE                              IMAGEN
Deployment   sa-platform-api-gateway             p7-api-gateway:local
Deployment   sa-platform-auth-service            p7-auth-service:local
Deployment   sa-platform-books-service           p7-books-service:local
Deployment   sa-platform-loans-service           p7-loans-service:local
Deployment   sa-platform-notifications-service   p7-notifications-service:local
CronJob      sa-platform-cronjob-insert          p7-cronjob-insert:local
CronJob      sa-platform-cronjob-summary         p7-cronjob-summary:local
```

En el pipeline, esta misma salida muestra las imágenes de GHCR con el tag de la
ejecución (`ghcr.io/<usuario>/<repo>/p7-auth-service:main-<sha>`), que es lo que
demuestra que el clúster está corriendo exactamente lo que se acaba de construir.

### Prueba de humo contra el API Gateway

```
OK   GET /            -> 200
{"mensaje":"API Gateway - Biblioteca","version":"1.1.0",
 "servicios":{"auth":"/auth","books":"/books","loans":"/loans","notifications":"/notifications"}}

OK   GET /health/live -> 200
{"status":"alive","service":"api-gateway"}

OK   GET /health/ready -> 200
{"status":"ready","service":"api-gateway",
 "dependencias":{"auth":"up","books":"up","loans":"up","notifications":"up"}}
```

La tercera respuesta es la más significativa: `/health/ready` del gateway
consulta a los cuatro microservicios aguas abajo, así que los cuatro `up`
confirman que la cadena completa quedó operativa, no solo que el gateway arrancó.

### CronJobs programados

```
NAME                          SCHEDULE       TIMEZONE            SUSPEND   ACTIVE
sa-platform-cronjob-insert    */2 * * * *    America/Guatemala   False     0
sa-platform-cronjob-summary   */10 * * * *   America/Guatemala   False     0
```

### Resultado

```
RESULTADO: despliegue verificado correctamente.
```

---

## 3. Archivos de evidencia

| Archivo | Contenido |
|---|---|
| [`00-resumen.md`](despliegue-local/00-resumen.md) | Resumen con pods e imágenes |
| [`01-objetos.txt`](despliegue-local/01-objetos.txt) | Todos los objetos del namespace |
| [`02-imagenes-desplegadas.txt`](despliegue-local/02-imagenes-desplegadas.txt) | Imagen de cada carga de trabajo |
| [`03-pods.txt`](despliegue-local/03-pods.txt) | Estado de los pods |
| [`04-pods-detalle.txt`](despliegue-local/04-pods-detalle.txt) | `describe` completo, con probes y eventos |
| [`05-eventos.txt`](despliegue-local/05-eventos.txt) | Eventos del namespace en orden cronológico |
| [`06-objetos-kubernetes.txt`](despliegue-local/06-objetos-kubernetes.txt) | ConfigMap, Secrets, HPA, NetworkPolicies, cuotas, PVC |
| [`07-release-helm.txt`](despliegue-local/07-release-helm.txt) | Release de Helm instalado |
| [`logs/`](despliegue-local/logs/) | Logs de arranque de cada pod |

El archivo de objetos de Kubernetes registra **solo los nombres** de los
`Secret`, nunca su contenido: la evidencia no debe filtrar credenciales.

---

## 4. Pruebas unitarias

Las 105 pruebas ejecutándose localmente, que es exactamente lo que corre la
etapa 2 del pipeline:

```
$ ./P7/scripts/pruebas-locales.sh

>> api-gateway (Node)            # tests 19  # pass 19  # fail 0
>> loans-service (Node)          # tests 20  # pass 20  # fail 0
>> notifications-service (Node)  # tests 15  # pass 15  # fail 0
>> auth-service (Python)         38 passed
>> books-service (Python)        17 passed

Todas las pruebas pasan. El pipeline deberia quedar en verde.
```
