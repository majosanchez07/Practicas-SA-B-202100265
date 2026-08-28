# Arquitectura de la plataforma

**Práctica 5 — Software Avanzado, Sección B**
**Maria Jose Tebalan Sanchez — Carné 202100265**

---

## 1. Diagrama general

Distingue los elementos externos al clúster de los internos, los flujos
síncronos de los asíncronos, y los límites que imponen las NetworkPolicies.

```mermaid
graph TB
    subgraph EXTERNO["FUERA DEL CLÚSTER"]
        CLIENTE["Cliente HTTP<br/>navegador · curl · k6"]
    end

    subgraph CLUSTER["CLÚSTER KUBERNETES — minikube + Calico"]
        subgraph NSING["namespace: ingress-nginx"]
            IC["Ingress Controller<br/>NGINX"]
        end

        subgraph NSP5["namespace: sa-p5 — creado por el chart"]
            ING["Ingress<br/>host: sa-p5.local<br/>única puerta de entrada"]

            GW["API Gateway<br/>Node.js · :8080<br/>HPA 2-5 réplicas"]

            AUTH["auth-service<br/>Python/FastAPI · :8000<br/>schema: auth"]
            BOOKS["books-service<br/>Python/GraphQL · :8001<br/>schema: books"]
            LOANS["loans-service<br/>Node/GraphQL · :8002<br/>schema: loans<br/>PRODUCTOR"]
            NOTIF["notifications-service<br/>Node.js · :8003<br/>schema: notifications<br/>CONSUMIDOR"]

            RMQ["RabbitMQ<br/>StatefulSet · :5672<br/>cola durable + DLQ"]
            PG[("PostgreSQL<br/>StatefulSet + PVC · :5432<br/>headless service<br/>4 schemas aislados")]

            CJ1["CronJob 1 — insert<br/>cada 2 min<br/>fecha GMT-6 + carné"]
            CJ2["CronJob 2 — summary<br/>cada 10 min<br/>agrega y publica"]
        end
    end

    CLIENTE -->|"HTTP :80"| IC
    IC -->|síncrono| ING
    ING -->|síncrono| GW

    GW -->|"síncrono /auth"| AUTH
    GW -->|"síncrono /books"| BOOKS
    GW -->|"síncrono /loans"| LOANS
    GW -->|"síncrono /notifications"| NOTIF

    AUTH -.->|"TCP 5432"| PG
    BOOKS -.->|"TCP 5432"| PG
    LOANS -.->|"TCP 5432"| PG
    NOTIF -.->|"TCP 5432"| PG

    LOANS ==>|"ASÍNCRONO<br/>publica loan.created"| RMQ
    RMQ ==>|"ASÍNCRONO<br/>consume · ack manual"| NOTIF

    CJ1 -.->|inserta| PG
    CJ2 -.->|consulta| PG
    CJ2 ==>|"ASÍNCRONO<br/>publica resumen.generado"| RMQ

    classDef externo fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef entrada fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef servicio fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef datos fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    classDef cron fill:#fce4ec,stroke:#ad1457,stroke-width:2px

    class CLIENTE externo
    class IC,ING,GW entrada
    class AUTH,BOOKS,LOANS,NOTIF servicio
    class PG,RMQ datos
    class CJ1,CJ2 cron
```

**Leyenda de los flujos**

| Trazo | Significado |
|---|---|
| `──▶` línea continua | Flujo **síncrono**: el llamador espera la respuesta |
| `- - ▶` línea punteada | Acceso a la base de datos (síncrono, sobre TCP 5432) |
| `══▶` línea gruesa | Flujo **asíncrono** a través del broker: el productor publica y retorna de inmediato |

---

## 2. Elementos internos y externos

| Elemento | Ubicación | Expuesto |
|---|---|---|
| Cliente HTTP | **Externo** al clúster | — |
| Ingress Controller NGINX | Interno, namespace `ingress-nginx` | Recibe el tráfico externo |
| Ingress `sa-platform` | Interno, namespace `sa-p5` | **Única puerta de entrada** |
| API Gateway | Interno, `sa-p5` | Solo vía Ingress (Service ClusterIP) |
| auth / books / loans / notifications | Interno, `sa-p5` | **No expuestos** — ClusterIP, solo alcanzables desde el gateway |
| PostgreSQL | Interno, `sa-p5` | **No expuesto** — ClusterIP + headless service |
| RabbitMQ | Interno, `sa-p5` | **No expuesto** — ClusterIP + headless service |
| CronJobs | Interno, `sa-p5` | Sin puertos; solo salida hacia BD y broker |

Ningún componente usa `NodePort` ni `LoadBalancer`:

```
$ kubectl get svc -n sa-p5
sa-platform-api-gateway             ClusterIP   8080/TCP
sa-platform-auth-service            ClusterIP   8000/TCP
sa-platform-books-service           ClusterIP   8001/TCP
sa-platform-loans-service           ClusterIP   8002/TCP
sa-platform-notifications-service   ClusterIP   8003/TCP
sa-platform-postgresql              ClusterIP   5432/TCP
sa-platform-postgresql-hl           ClusterIP   5432/TCP     <- headless
sa-platform-rabbitmq                ClusterIP   5672/TCP ...
sa-platform-rabbitmq-headless       ClusterIP   5672/TCP ...  <- headless
```

---

## 3. Límites impuestos por las NetworkPolicies

El namespace parte de una política **default-deny** que selecciona a todos los
pods y no autoriza nada. A partir de ahí solo se abren los caminos necesarios.

```mermaid
graph LR
    subgraph BLOQUEADO["BLOQUEADO por default-deny"]
        X1["Pod cualquiera<br/>sin etiquetas"]
    end

    subgraph PERMITIDO["Caminos autorizados explícitamente"]
        IC2["ingress-nginx"] -->|":8080"| GW2["api-gateway"]
        GW2 -->|":8000-8003"| MS["microservicios"]
        DBC["pods con<br/>sa-p5/db-client"] -->|":5432"| PG2[("PostgreSQL")]
        BRC["pods con<br/>sa-p5/broker-client"] -->|":5672"| RMQ2["RabbitMQ"]
        TODOS["todos los pods"] -->|":53"| DNS["kube-dns"]
    end

    X1 -.->|"✗ descartado"| PG2
    X1 -.->|"✗ descartado"| RMQ2
    X1 -.->|"✗ descartado"| MS
    MS -.->|"✗ tráfico lateral<br/>descartado"| MS

    classDef bloq fill:#ffebee,stroke:#c62828,stroke-width:2px
    classDef perm fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    class X1 bloq
    class IC2,GW2,MS,DBC,BRC,PG2,RMQ2,TODOS,DNS perm
```

### Las 13 políticas desplegadas

| Política | Selecciona | Autoriza |
|---|---|---|
| `default-deny` | Todos los pods | **Nada** — cierra el namespace |
| `allow-dns` | Todos los pods | Salida a kube-dns (UDP/TCP 53) |
| `api-gateway-allow-ingress` | api-gateway | Entrada solo desde `ingress-nginx` |
| `api-gateway-allow-egress` | api-gateway | Salida hacia los 4 microservicios |
| `auth-service-allow-from-gateway` | auth-service | Entrada **solo** desde el gateway |
| `books-service-allow-from-gateway` | books-service | Entrada **solo** desde el gateway |
| `loans-service-allow-from-gateway` | loans-service | Entrada **solo** desde el gateway |
| `notifications-service-allow-from-gateway` | notifications-service | Entrada **solo** desde el gateway |
| `allow-db-clients-egress` | Pods con `sa-p5/db-client` | Salida hacia PostgreSQL :5432 |
| `postgresql-allow-clients` | PostgreSQL | Entrada solo de pods con `sa-p5/db-client` |
| `allow-broker-clients-egress` | Pods con `sa-p5/broker-client` | Salida hacia RabbitMQ :5672 |
| `rabbitmq-allow-clients` | RabbitMQ | Entrada solo de pods con `sa-p5/broker-client` |
| `dependencies-internal` | PostgreSQL y RabbitMQ | Tráfico interno y probes del kubelet |

### Qué queda bloqueado

- Un microservicio **no puede** alcanzar a otro microservicio directamente
  (todo pasa por el gateway).
- Un pod sin las etiquetas correspondientes **no puede** alcanzar la base de
  datos ni el broker.
- Nada externo entra al namespace salvo por el Ingress Controller.

Comprobado con evidencia en `evidencias/04-networkpolicies-bloqueo.md`.

### Nota sobre el CNI

Las NetworkPolicies **requieren un CNI que las implemente**. El CNI por defecto
de minikube (bridge) las acepta y las ignora en silencio: los objetos aparecen
en `kubectl get networkpolicy` y el tráfico sigue pasando. El clúster se levanta
con **Calico** por ese motivo:

```bash
minikube start --cni=calico ...
```

---

## 4. Asignación de las etiquetas de autorización

Las etiquetas que gobiernan el acceso a la base de datos y al broker **se
derivan de la configuración**, no de una lista escrita a mano:

```yaml
# values.yaml
services:
  loans-service:
    dbSchema: loans        # -> el Deployment añade sa-p5/db-client: "true"
    usesBroker: true       # -> el Deployment añade sa-p5/broker-client: "true"
```

```gotemplate
{{- if $cfg.usesBroker }}
sa-p5/broker-client: "true"
{{- end }}
{{- if $cfg.dbSchema }}
sa-p5/db-client: "true"
{{- end }}
```

Agregar un microservicio al mapa de `values.yaml` genera su Deployment, su
Service, su HPA, su PDB, su ServiceAccount con RBAC y sus autorizaciones de red,
sin escribir una sola plantilla nueva.

---

## 5. Persistencia y aislamiento de datos

En la Práctica 4 cada microservicio tenía su propia instancia de PostgreSQL. En
la Práctica 5 hay **una sola instancia desplegada como StatefulSet**, y cada
servicio queda aislado en su propio schema:

| Servicio | Schema | Tablas |
|---|---|---|
| auth-service | `auth` | usuarios |
| books-service | `books` | books |
| loans-service | `loans` | loans |
| notifications-service | `notifications` | notifications, resumenes |
| CronJobs | `cronjobs` | ejecuciones |

El aislamiento se logra fijando el `search_path` de cada conexión al schema del
servicio. Se conserva la separación lógica entre microservicios con un único PVC
y un único headless service, que es lo que el enunciado pide para la
persistencia.

```
StatefulSet: sa-platform-postgresql
PVC:         data-sa-platform-postgresql-0  (Bound, 1Gi)
Headless:    sa-platform-postgresql-hl      (ClusterIP: None)
```

---

## 6. Flujo asíncrono en detalle

### Flujo de negocio desacoplado: creación de un préstamo

```mermaid
sequenceDiagram
    participant C as Cliente
    participant G as API Gateway
    participant L as loans-service
    participant DB as PostgreSQL
    participant R as RabbitMQ
    participant N as notifications-service

    C->>G: POST /loans/graphql (createLoan)
    G->>L: proxy
    L->>DB: INSERT en loans.loans
    DB-->>L: id del préstamo
    L->>R: publica loan.created (persistent)
    L-->>G: respuesta
    G-->>C: 200 en 169 ms

    Note over R,N: A partir de aquí el cliente ya fue atendido

    R->>N: entrega el mensaje
    N->>DB: INSERT en notifications.notifications
    DB-->>N: ok
    N->>R: ack (solo tras persistir)
```

El cliente recibe su respuesta en **169 ms** sin esperar a que la notificación
se genere. Si `notifications-service` estuviera caído, el préstamo se crearía
igual y el mensaje quedaría en la cola durable hasta que el consumidor volviera.

### Cadena de los CronJobs

```mermaid
graph LR
    CJ1["CronJob 1<br/>cada 2 min"] -->|"INSERT fecha GMT-6<br/>+ carné 202100265"| DB[("cronjobs.ejecuciones")]
    DB -->|"SELECT agrupado<br/>por hora"| CJ2["CronJob 2<br/>cada 10 min"]
    CJ2 ==>|"publica<br/>resumen.generado"| RMQ["RabbitMQ"]
    RMQ ==>|"consume"| N["notifications-service"]
    N -->|"INSERT"| DB2[("notifications.resumenes")]

    classDef cron fill:#fce4ec,stroke:#ad1457
    classDef datos fill:#f3e5f5,stroke:#6a1b9a
    class CJ1,CJ2 cron
    class DB,DB2,RMQ datos
```

---

## 7. Salud, escalado y resiliencia

### Probes diferenciadas

Cada Deployment define las tres probes apuntando a endpoints **distintos**,
porque cumplen funciones distintas:

| Probe | Endpoint | Consulta la BD | Qué responde |
|---|---|---|---|
| `startupProbe` | `/health/live` | No | ¿Terminó de arrancar? Mientras no tenga éxito, las otras dos quedan suspendidas |
| `livenessProbe` | `/health/live` | **No** | ¿Hay que reiniciar este pod? |
| `readinessProbe` | `/health/ready` | **Sí** | ¿Puede recibir tráfico? |

**Por qué liveness no consulta la base de datos.** Si lo hiciera, una caída
temporal de PostgreSQL reiniciaría todos los pods de todos los microservicios.
Reiniciar no arregla una base de datos caída: solo añade un CrashLoopBackOff al
incidente. La readiness sí la consulta, de modo que un pod que no puede atender
sale del balanceo pero sigue vivo y vuelve solo cuando la dependencia se
restablece.

**Por qué los servicios en Python tienen más margen en la startup probe**
(`failureThreshold: 24` frente a 18 de los Node): cargan más dependencias al
iniciar y además crean su schema en el arranque. Con un margen escaso, la
liveness empezaría a contar antes de tiempo y reiniciaría un pod que solo estaba
arrancando.

### Escalado y disponibilidad

| Mecanismo | Configuración | Propósito |
|---|---|---|
| HPA | min 2, max 5, 70 % CPU | Escalado automático bajo carga |
| PodDisruptionBudget | `minAvailable` acotado a réplicas−1 | Limita interrupciones voluntarias |
| RollingUpdate | `maxUnavailable: 0`, `maxSurge: 1` | Actualización sin caída de servicio |
| ResourceQuota | Dimensionada para el pico del HPA | Techo del namespace |
| LimitRange | Defaults y máximo por contenedor | Evita pods sin recursos declarados |

---

## 8. Seguridad

### RBAC de mínimo privilegio

Cada microservicio y cada cronjob tiene su **ServiceAccount dedicado**; el
ServiceAccount `default` no se usa en ninguna carga de trabajo.

Estas aplicaciones no consultan la API de Kubernetes: obtienen su configuración
por variables de entorno. Los Roles conceden únicamente lectura del ConfigMap y
del Secret que cada carga consume, **y solo de esos objetos por nombre**
mediante `resourceNames`, de modo que ni siquiera pueden enumerar los demás
secretos del namespace. Los tokens no se montan en los pods
(`automountServiceAccountToken: false`).

### securityContext restrictivo

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

Las siete imágenes se construyen con multi-stage build y usuario sin
privilegios; se verificó que arrancan con `--read-only --user 1000:1000` contra
una base de datos real. Como el sistema de archivos es de solo lectura, se monta
un `emptyDir` en `/tmp` para los temporales que las librerías puedan necesitar.

### Gestión de credenciales

Ninguna credencial está versionada en el repositorio. Los campos sensibles
quedan vacíos en `values.yaml` y el chart los valida con `required`, de modo que
una instalación sin credenciales se detiene con un mensaje explícito en lugar de
desplegar pods que entrarían en CrashLoopBackOff:

```
Error: execution error at (sa-platform/templates/secret.yaml:20:5):
postgresql.auth.password es obligatorio (usar --set o un values propio, nunca versionarlo)
```

Se entrega `values.example.yaml` con valores ficticios; el archivo real
(`values.secret.yaml`) está excluido por `.gitignore`.
