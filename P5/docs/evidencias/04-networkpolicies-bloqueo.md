# Evidencia — NetworkPolicies: bloqueo del tráfico lateral

## Requisito previo del entorno: un CNI que aplique las políticas

Durante la primera prueba las 13 NetworkPolicies estaban creadas y correctas,
pero **no bloqueaban nada**: un pod sin autorización alcanzaba la base de datos,
el broker y los microservicios.

La causa es que el CNI por defecto de Minikube (bridge) **no implementa
NetworkPolicy**. El API server acepta los objetos, `kubectl get networkpolicy`
los muestra, y el tráfico sigue pasando sin ninguna advertencia. Es un fallo
silencioso: las políticas parecen aplicadas y no lo están.

```
$ kubectl get networkpolicy -n sa-p5 --no-headers | wc -l
13
$ kubectl get pods -n kube-system | grep -iE "calico|cilium|weave"
  (ninguno)
```

El clúster se recreó con Calico, que sí las aplica:

```bash
minikube delete --profile=sa-p5
minikube start --driver=docker --cpus=4 --memory=6144 \
  --kubernetes-version=v1.31.0 --cni=calico --profile=sa-p5
```

```
$ kubectl get pods -n kube-system | grep calico
calico-node-g52wd   1/1   Running
```

## 1. Pod NO autorizado — todo bloqueado

Pod sin las etiquetas `sa-p5/db-client` ni `sa-p5/broker-client`:

```bash
kubectl run pod-intruso --rm -i --restart=Never \
  --image=curlimages/curl:latest -n sa-p5 -- sh -c '...'
```

```
--- 1) Hacia PostgreSQL (5432) ---
punt!
Terminated
  BLOQUEADO
--- 2) Hacia RabbitMQ (5672) ---
punt!
Terminated
  BLOQUEADO
--- 3) Hacia auth-service (8000) ---
  codigo=000
  BLOQUEADO
```

El código `000` de curl indica que la conexión nunca se estableció. Las
conexiones no son rechazadas sino descartadas, que es el comportamiento propio
de una NetworkPolicy: el paquete se descarta sin enviar respuesta, de ahí que
agoten el tiempo de espera en lugar de devolver `connection refused`.

## 2. Pod autorizado — permitido

El mismo comando, la misma imagen y los mismos destinos; lo único que cambia son
las etiquetas del pod:

```bash
kubectl run pod-autorizado --rm -i --restart=Never \
  --image=curlimages/curl:latest -n sa-p5 \
  --labels="sa-p5/db-client=true,sa-p5/broker-client=true" -- sh -c '...'
```

```
--- Hacia PostgreSQL (5432) ---
sa-platform-postgresql (10.99.164.9:5432) open
  PERMITIDO
--- Hacia RabbitMQ (5672) ---
sa-platform-rabbitmq (10.100.34.162:5672) open
  PERMITIDO
```

La comparación entre ambas pruebas es lo que demuestra que quien bloquea es la
política y no un problema de red: idéntico entorno, resultado opuesto según las
etiquetas.

## 3. Tráfico lateral entre microservicios — bloqueado

`auth-service` intentando alcanzar directamente a otros microservicios, sin
pasar por el gateway:

```
  sa-platform-books-service:8001 -> BLOQUEADO (TimeoutError, 6.00s)
  sa-platform-loans-service:8002 -> BLOQUEADO (TimeoutError, 6.00s)
```

Esto es exactamente lo que pide el enunciado: un microservicio no puede alcanzar
a otro microservicio.

## 4. El API Gateway sí alcanza a los microservicios

```
  sa-platform-auth-service:8000          -> PERMITIDO (200, 100ms)
  sa-platform-books-service:8001         -> PERMITIDO (200,  98ms)
  sa-platform-loans-service:8002         -> PERMITIDO (200,  96ms)
  sa-platform-notifications-service:8003 -> PERMITIDO (200,  97ms)
```

## Resumen del aislamiento verificado

| Origen | Destino | Resultado |
|---|---|---|
| Pod sin etiquetas | PostgreSQL 5432 | Bloqueado |
| Pod sin etiquetas | RabbitMQ 5672 | Bloqueado |
| Pod sin etiquetas | auth-service 8000 | Bloqueado |
| Pod con `db-client` | PostgreSQL 5432 | Permitido |
| Pod con `broker-client` | RabbitMQ 5672 | Permitido |
| auth-service | books-service 8001 | Bloqueado (lateral) |
| auth-service | loans-service 8002 | Bloqueado (lateral) |
| api-gateway | los 4 microservicios | Permitido |

La autorización se deriva de la configuración y no de una lista escrita a mano:
el Deployment coloca la etiqueta `sa-p5/db-client` cuando el servicio declara
`dbSchema` en values, y `sa-p5/broker-client` cuando declara `usesBroker`.
