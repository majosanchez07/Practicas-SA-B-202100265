# Práctica 5 — Orquestación avanzada de microservicios en Kubernetes con Helm

**Curso:** Software Avanzado — Sección B
**Estudiante:** Maria Jose Tebalan Sanchez
**Carné:** 202100265
**Namespace de trabajo:** `sa-p5`

---

## Contenido

| Documento | Descripción |
|---|---|
| [docs/arquitectura.md](docs/arquitectura.md) | Diagrama de arquitectura, flujos síncronos y asíncronos, límites de las NetworkPolicies |
| [docs/comandos-reproducibles.md](docs/comandos-reproducibles.md) | Todos los comandos desde el clúster vacío hasta la aplicación funcionando |
| [docs/tabla-imagenes.md](docs/tabla-imagenes.md) | Comparativa del tamaño de las imágenes antes y después de la optimización |
| [docs/preguntas-teoricas.md](docs/preguntas-teoricas.md) | Las ocho preguntas teóricas |
| [docs/decisiones-tecnicas.md](docs/decisiones-tecnicas.md) | Problemas encontrados durante el desarrollo y cómo se resolvieron |
| [docs/evidencias/](docs/evidencias/) | Evidencias de cada requisito |

### Evidencias

| Archivo | Requisito |
|---|---|
| [02-ciclo-vida-helm.md](docs/evidencias/02-ciclo-vida-helm.md) | Dos versiones del chart, upgrade y rollback con `helm history` |
| [03-persistencia-statefulset.md](docs/evidencias/03-persistencia-statefulset.md) | Los datos sobreviven al borrado del pod de base de datos |
| [04-networkpolicies-bloqueo.md](docs/evidencias/04-networkpolicies-bloqueo.md) | Bloqueo del tráfico lateral desde un pod no autorizado |
| [05-actualizacion-sin-downtime.md](docs/evidencias/05-actualizacion-sin-downtime.md) | 400 peticiones durante el upgrade, sin una sola respuesta de error |
| [06-carga-y-escalado-hpa.md](docs/evidencias/06-carga-y-escalado-hpa.md) | Prueba de carga con k6 y escalado automático del HPA |
| [07-flujo-asincrono-cluster.md](docs/evidencias/07-flujo-asincrono-cluster.md) | Flujo asíncrono completo y comportamiento con el consumidor caído |
| [00](docs/evidencias/00-prueba-local-flujo-asincrono.md) y [01](docs/evidencias/01-prueba-local-cronjobs.md) | Validaciones preliminares del código antes del despliegue |

---

## Estructura del repositorio

```
P5/
├── services/                        Código fuente de los microservicios
│   ├── api-gateway/                 Node.js — única puerta de entrada
│   ├── auth-service/                Python/FastAPI — autenticación JWT
│   ├── books-service/               Python/FastAPI + GraphQL — catálogo
│   ├── loans-service/               Node.js + GraphQL — préstamos (productor)
│   └── notifications-service/       Node.js — notificaciones (consumidor)
│
├── cronjobs/                        Trabajos programados
│   ├── cronjob-insert/              Cada 2 min: fecha GMT-6 + carné
│   └── cronjob-summary/             Cada 10 min: agrega y publica al broker
│
├── charts/sa-platform/              Chart de Helm
│   ├── Chart.yaml                   Versión y dependencias declaradas
│   ├── Chart.lock                   Dependencias resueltas
│   ├── values.yaml                  Valores base
│   ├── values-dev.yaml              Ambiente de desarrollo
│   ├── values-prod.yaml             Ambiente de producción
│   ├── values.example.yaml          Plantilla de credenciales (valores ficticios)
│   ├── charts/                      postgresql-15.5.38.tgz, rabbitmq-16.0.14.tgz
│   └── templates/
│       ├── _helpers.tpl             16 named templates
│       ├── namespace.yaml           Namespace sa-p5
│       ├── configmap.yaml           Configuración no sensible
│       ├── secret.yaml              Credenciales (validadas con required)
│       ├── deployments.yaml         Los 5 microservicios, vía range
│       ├── services.yaml            Services ClusterIP
│       ├── hpa.yaml                 Autoescalado 2-5 réplicas al 70 % CPU
│       ├── pdb.yaml                 PodDisruptionBudgets
│       ├── rbac.yaml                ServiceAccounts, Roles y RoleBindings
│       ├── ingress.yaml             Única puerta de entrada
│       ├── networkpolicies.yaml     13 políticas de aislamiento
│       ├── cronjobs.yaml            Los dos trabajos programados
│       └── quotas.yaml              ResourceQuota y LimitRange
│
├── loadtest/carga.js                Prueba de carga con k6
└── docs/                            Documentación y evidencias
```

---

## Arranque rápido

```bash
# 1. Clúster (Calico es necesario para que las NetworkPolicies se apliquen)
minikube start --driver=docker --cpus=4 --memory=6144 \
  --kubernetes-version=v1.31.0 --cni=calico --profile=sa-p5
minikube addons enable ingress --profile=sa-p5
minikube addons enable metrics-server --profile=sa-p5

# 2. Imágenes
cd P5
docker build -t sa-p5/api-gateway:v1           services/api-gateway
docker build -t sa-p5/auth-service:v1          services/auth-service
docker build -t sa-p5/books-service:v1         services/books-service
docker build -t sa-p5/loans-service:v2         services/loans-service
docker build -t sa-p5/notifications-service:v2 services/notifications-service
docker build -t sa-p5/cronjob-insert:v1        cronjobs/cronjob-insert
docker build -t sa-p5/cronjob-summary:v1       cronjobs/cronjob-summary

for img in api-gateway:v1 auth-service:v1 books-service:v1 loans-service:v2 \
           notifications-service:v2 cronjob-insert:v1 cronjob-summary:v1; do
  minikube image load "sa-p5/$img" --profile=sa-p5
done

# 3. Chart
cd charts/sa-platform
helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
helm dependency update .
cp values.example.yaml values.secret.yaml    # editar con credenciales propias

# 4. Instalar — un solo comando
helm install sa-platform . --namespace sa-p5 --create-namespace \
  -f values-dev.yaml -f values.secret.yaml --timeout 10m

# 5. Acceder (terminal aparte)
minikube tunnel --profile=sa-p5
curl -H "Host: sa-p5.local" http://127.0.0.1/
```

El detalle completo, incluida la instalación de herramientas, está en
[docs/comandos-reproducibles.md](docs/comandos-reproducibles.md).

---

## Resumen de lo implementado

### A. Empaquetado con Helm

- Chart padre `sa-platform` con los microservicios y el API Gateway.
- PostgreSQL y RabbitMQ declarados como **dependencias** en `Chart.yaml`,
  resueltas con `helm dependency update`.
- `values.yaml` base más `values-dev.yaml` y `values-prod.yaml`, que modifican
  réplicas, límites de recursos, tag de imagen y nivel de log.
- `_helpers.tpl` con **16 named templates**; uso real de `range`, `if/else`,
  `required`, `default` y `quote`.
- `helm lint` sin errores ni advertencias en ambos ambientes.
- Dos versiones publicadas (0.1.0 y 0.2.0), con upgrade y rollback verificados.

### B. Configuración y secretos

- Toda variable no sensible proviene de un ConfigMap generado por el chart.
- Credenciales en un Secret, inyectado con `envFrom`.
- **Ninguna credencial versionada**: los campos sensibles están vacíos y
  validados con `required`; se entrega `values.example.yaml` con valores
  ficticios.
- Anotación `checksum/config` que reinicia los pods al cambiar el ConfigMap.

### C. Persistencia

- PostgreSQL como **StatefulSet** con PVC y headless service.
- Verificado que los datos sobreviven al borrado del pod.
- Cuatro schemas aislados en una sola instancia.

### D. Comunicación asíncrona

- RabbitMQ desplegado como dependencia del chart.
- `createLoan` publica el evento y retorna en **169 ms** sin esperar al consumidor.
- Cola durable con ack manual: el mensaje se confirma solo tras persistir.
- Verificado que los mensajes se acumulan con el consumidor caído y se procesan
  al restaurarlo, sin pérdida.

### E. Exposición y aislamiento

- Ingress NGINX como única puerta de entrada; todos los Services son ClusterIP.
- **13 NetworkPolicies** partiendo de una política default-deny.
- Bloqueo verificado desde un pod no autorizado.

### F. Salud, escalado y resiliencia

- Las tres probes diferenciadas, apuntando a endpoints distintos.
- HPA de 2 a 5 réplicas al 70 % de CPU, con escalado y descenso comprobados.
- ResourceQuota y LimitRange dimensionados para el pico del HPA.
- PodDisruptionBudget por microservicio.
- `RollingUpdate` con `maxUnavailable: 0`: **400 peticiones sin un solo error**
  durante el upgrade.

### G. Seguridad

- ServiceAccount dedicado por microservicio y por cronjob, con Role y RoleBinding
  de mínimo privilegio. El ServiceAccount `default` no se usa.
- `runAsNonRoot`, `readOnlyRootFilesystem` y `allowPrivilegeEscalation: false`.
- Imágenes multi-stage con base mínima: **40 % de reducción** de tamaño.

### H. Trabajos programados

- Cronjob 1 cada 2 minutos: inserta fecha GMT-6 y carné 202100265.
- Cronjob 2 cada 10 minutos: agrega por hora y publica al broker, donde es
  consumido y almacenado.
- Ambos con `concurrencyPolicy: Forbid`, `backoffLimit` y límites de historial.

### I. Pruebas de carga

| Métrica | Resultado |
|---|---|
| Peticiones por segundo | **457.73 RPS** |
| Latencia p95 | **67.88 ms** |
| Tasa de error | **0.00 %** |
| Escalado del HPA | 2 → 4 → 5 réplicas |
| Descenso al cesar la carga | 5 → 4 → 3 → 2 réplicas |

---

## Notas de entorno

**El CNI debe ser Calico.** El CNI por defecto de minikube no implementa
NetworkPolicy: acepta los objetos y los ignora en silencio, de modo que el
aislamiento no se aplicaría y `kubectl get networkpolicy` seguiría mostrándolas.

**Helm 3.** El chart se desarrolló y validó con Helm 3.16.4.

**Imágenes de Bitnami.** Bitnami trasladó sus imágenes con tag a un catálogo de
pago; los charts apuntan por defecto a referencias que ya no se pueden descargar.
El chart redirige el registro a `bitnamilegacy`, que conserva las imágenes
publicadas antes del cambio. Ver
[docs/decisiones-tecnicas.md](docs/decisiones-tecnicas.md).
