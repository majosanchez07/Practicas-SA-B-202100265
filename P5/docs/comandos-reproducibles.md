# Comandos reproducibles — de un clúster vacío a la aplicación funcionando

**Práctica 5 — Software Avanzado, Sección B**
**Maria Jose Tebalan Sanchez — Carné 202100265**

Todos los comandos están verificados sobre el despliegue real. Se asume Windows
con Git Bash o PowerShell; en Linux o macOS son idénticos salvo la instalación
de herramientas del paso 0.

---

## 0. Requisitos previos

### Herramientas

| Herramienta | Versión usada |
|---|---|
| Docker | 29.1.3 |
| kubectl | 1.34.1 |
| **Helm** | **3.16.4** |
| minikube | 1.38.1 |
| k6 | 2.2.0 |

```powershell
# Windows (PowerShell como Administrador)
winget install --id Kubernetes.minikube -e
winget install --id GrafanaLabs.k6 -e
```

Helm **3** se instala desde el binario oficial. `winget install Helm.Helm`
entrega actualmente Helm 4, cuyo `helm lint` es más estricto y puede comportarse
de forma distinta:

```powershell
$dir = "$env:LOCALAPPDATA\helm3"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest -Uri "https://get.helm.sh/helm-v3.16.4-windows-amd64.zip" -OutFile "$env:TEMP\helm3.zip"
Expand-Archive -Path "$env:TEMP\helm3.zip" -DestinationPath "$env:TEMP\helm3x" -Force
Copy-Item "$env:TEMP\helm3x\windows-amd64\helm.exe" -Destination "$dir\helm.exe" -Force
[System.Environment]::SetEnvironmentVariable("Path", "$dir;" + [System.Environment]::GetEnvironmentVariable("Path","User"), "User")
```

Verificación:

```bash
docker --version && kubectl version --client && helm version --short && minikube version && k6 version
```

### Docker Desktop

Debe estar corriendo, con al menos **6 GB de memoria** asignados
(Settings → Resources).

---

## 1. Crear el clúster

**El CNI debe ser Calico.** El CNI por defecto de minikube (bridge) no
implementa NetworkPolicy: acepta los objetos y los ignora en silencio, de modo
que el aislamiento de red no se aplicaría.

```bash
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=6144 \
  --kubernetes-version=v1.31.0 \
  --cni=calico \
  --profile=sa-p5
```

Habilitar los addons requeridos:

```bash
minikube addons enable ingress --profile=sa-p5
minikube addons enable metrics-server --profile=sa-p5
```

Verificar que el clúster está listo:

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep calico          # calico-node debe estar Running
kubectl get pods -n ingress-nginx                      # el controller debe estar Running
kubectl get storageclass                               # 'standard' debe ser la default
```

---

## 2. Construir las imágenes

Desde la carpeta `P5/`:

```bash
cd P5

# Microservicios
docker build -t sa-p5/api-gateway:v1           services/api-gateway
docker build -t sa-p5/auth-service:v1          services/auth-service
docker build -t sa-p5/books-service:v1         services/books-service
docker build -t sa-p5/loans-service:v2         services/loans-service
docker build -t sa-p5/notifications-service:v2 services/notifications-service

# CronJobs
docker build -t sa-p5/cronjob-insert:v1  cronjobs/cronjob-insert
docker build -t sa-p5/cronjob-summary:v1 cronjobs/cronjob-summary
```

Cargarlas en el clúster (minikube no ve el demonio Docker local):

```bash
for img in api-gateway:v1 auth-service:v1 books-service:v1 \
           loans-service:v2 notifications-service:v2 \
           cronjob-insert:v1 cronjob-summary:v1; do
  minikube image load "sa-p5/$img" --profile=sa-p5
done
```

Verificar:

```bash
minikube image ls --profile=sa-p5 | grep sa-p5
```

> **Importante para las actualizaciones.** `minikube image load` no reemplaza
> una imagen que ya existe en el nodo con el mismo tag, y con
> `imagePullPolicy: IfNotPresent` los pods seguirían usando la versión anterior.
> Cada cambio debe llevar un tag nuevo (`v1`, `v2`, …). Eso es además lo que
> permite que `helm rollback` devuelva exactamente el binario anterior.

---

## 3. Preparar el chart

### Resolver las dependencias

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

cd charts/sa-platform
helm dependency update .
```

Deben descargarse `postgresql-15.5.38.tgz` y `rabbitmq-16.0.14.tgz` en
`charts/`, y generarse `Chart.lock`.

### Generar las credenciales

El repositorio no contiene ninguna credencial real. Se crea un archivo local a
partir de la plantilla de ejemplo; `values.secret.yaml` está excluido por
`.gitignore`:

```bash
cp values.example.yaml values.secret.yaml
```

Editar `values.secret.yaml` con credenciales propias. Para generarlas:

```bash
openssl rand -hex 16   # contraseñas y AES_SECRET_KEY (32 caracteres)
openssl rand -hex 32   # JWT_SECRET_KEY y erlangCookie
```

Alternativa sin archivo intermedio:

```bash
helm install sa-platform . --namespace sa-p5 --create-namespace \
  -f values-dev.yaml \
  --set postgresql.auth.username=biblioteca \
  --set postgresql.auth.password="$PGPASS" \
  --set postgresql.auth.postgresPassword="$PGADMIN" \
  --set rabbitmq.auth.username=biblioteca \
  --set rabbitmq.auth.password="$RMQPASS" \
  --set rabbitmq.auth.erlangCookie="$COOKIE" \
  --set secrets.jwtSecretKey="$JWT" \
  --set secrets.aesSecretKey="$AES"
```

### Validar el chart

```bash
helm lint . -f values.example.yaml -f values-dev.yaml
helm lint . -f values.example.yaml -f values-prod.yaml
```

Ambos deben terminar sin errores ni advertencias:

```
==> Linting .
1 chart(s) linted, 0 chart(s) failed
```

Revisar los manifiestos generados antes de aplicarlos:

```bash
helm template sa-platform . -f values.example.yaml -f values-dev.yaml --namespace sa-p5
```

---

## 4. Instalar la plataforma

**Un solo comando** levanta los 5 microservicios, PostgreSQL, RabbitMQ, los dos
cronjobs, el Ingress, las 13 NetworkPolicies, los HPA, los PDB y el RBAC:

```bash
helm install sa-platform . \
  --namespace sa-p5 \
  --create-namespace \
  -f values-dev.yaml \
  -f values.secret.yaml \
  --timeout 10m
```

```
NAME: sa-platform
NAMESPACE: sa-p5
STATUS: deployed
REVISION: 1
```

> `--create-namespace` es necesario aunque el chart declare el namespace. Helm
> guarda el estado del release en un Secret alojado dentro del namespace y lo
> escribe antes de aplicar las plantillas, de modo que el namespace debe existir
> de antemano. La explicación completa está en `templates/namespace.yaml`.

### Esperar a que converja

```bash
kubectl get pods -n sa-p5 -w
```

Estado esperado (~2 minutos):

```
NAME                                       READY   STATUS      RESTARTS
sa-platform-api-gateway-xxxxx              1/1     Running     0
sa-platform-api-gateway-xxxxx              1/1     Running     0
sa-platform-auth-service-xxxxx             1/1     Running     1
sa-platform-books-service-xxxxx            1/1     Running     1
sa-platform-loans-service-xxxxx            1/1     Running     2
sa-platform-notifications-service-xxxxx    1/1     Running     2
sa-platform-postgresql-0                   1/1     Running     0
sa-platform-rabbitmq-0                     1/1     Running     0
sa-platform-cronjob-insert-xxxxx           0/1     Completed   0
```

Los reinicios iniciales de los microservicios son esperados: arrancan antes que
PostgreSQL y RabbitMQ, no los encuentran y se reinician hasta que las
dependencias están listas.

### Verificar los objetos creados

```bash
kubectl get all,ingress,networkpolicy,hpa,pdb,resourcequota,limitrange -n sa-p5
kubectl get sa,role,rolebinding -n sa-p5
kubectl get pvc -n sa-p5
```

---

## 5. Acceder a la aplicación

En Windows y macOS con el driver Docker, la IP del clúster no es alcanzable
directamente; hace falta abrir el túnel **en una terminal aparte que debe
permanecer abierta**:

```bash
minikube tunnel --profile=sa-p5
```

Probar el acceso (el `Host` debe coincidir con `ingress.host` de los values):

```bash
curl -H "Host: sa-p5.local" http://127.0.0.1/
curl -H "Host: sa-p5.local" http://127.0.0.1/health/ready
```

```json
{"mensaje":"API Gateway - Biblioteca","version":"1.0.0","servicios":{...}}
{"status":"ready","service":"api-gateway","dependencias":{"auth":"up","books":"up","loans":"up","notifications":"up"}}
```

Para acceder por el nombre en el navegador, agregar al archivo de hosts
(`C:\Windows\System32\drivers\etc\hosts` o `/etc/hosts`):

```
127.0.0.1  sa-p5.local
```

### Probar el flujo asíncrono

```bash
# Crear un préstamo: el productor publica el evento y retorna de inmediato
curl -H "Host: sa-p5.local" -H "Content-Type: application/json" \
  -X POST http://127.0.0.1/loans/graphql \
  -d '{"query":"mutation { createLoan(userId: 202100265, bookId: 42) { id status } }"}'

# La notificación la genera el consumidor por su cuenta
curl -H "Host: sa-p5.local" http://127.0.0.1/notifications/notifications
```

---

## 6. Ciclo de vida: upgrade y rollback

### Publicar una segunda versión

Incrementar `version` y `appVersion` en `Chart.yaml`, construir la nueva imagen
con un **tag distinto** y cargarla:

```bash
docker build -t sa-p5/api-gateway:v2 services/api-gateway
minikube image load sa-p5/api-gateway:v2 --profile=sa-p5
```

### Upgrade

```bash

```

### Rollback a la revisión anterior

```bash
helm rollback sa-platform 1 --namespace sa-p5 --timeout 8m --wait
```

### Historial

```bash
helm history sa-platform -n sa-p5
```

```
REVISION  STATUS      CHART              APP VERSION  DESCRIPTION
1         superseded  sa-platform-0.1.0  1.0.0        Install complete
2         superseded  sa-platform-0.2.0  1.1.0        Upgrade complete
3         deployed    sa-platform-0.1.0  1.0.0        Rollback to 1
```

---

## 7. Reproducir las evidencias

### Persistencia tras el borrado del pod de base de datos

```bash
PGPASS=$(kubectl get secret sa-platform-secret -n sa-p5 -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)

# Contar registros antes
kubectl exec -n sa-p5 sa-platform-postgresql-0 -- env PGPASSWORD="$PGPASS" \
  psql -U biblioteca -d biblioteca -c "SELECT COUNT(*) FROM cronjobs.ejecuciones;"

# Anotar el volumen y borrar el pod
kubectl get pvc data-sa-platform-postgresql-0 -n sa-p5 -o jsonpath='{.spec.volumeName}{"\n"}'
kubectl delete pod sa-platform-postgresql-0 -n sa-p5

# Tras la recreación, el volumen es el mismo y los datos siguen ahí
kubectl get pvc data-sa-platform-postgresql-0 -n sa-p5 -o jsonpath='{.spec.volumeName}{"\n"}'
kubectl exec -n sa-p5 sa-platform-postgresql-0 -- env PGPASSWORD="$PGPASS" \
  psql -U biblioteca -d biblioteca -c "SELECT COUNT(*) FROM cronjobs.ejecuciones;"
```

### Bloqueo por NetworkPolicy

```bash
# Pod SIN autorización: todo bloqueado
kubectl run pod-intruso --rm -i --restart=Never \
  --image=curlimages/curl:latest -n sa-p5 -- sh -c '
    timeout 8 nc -zv sa-platform-postgresql 5432 || echo "BLOQUEADO"
    timeout 8 nc -zv sa-platform-rabbitmq 5672 || echo "BLOQUEADO"
  '

# Pod CON autorización: permitido
kubectl run pod-autorizado --rm -i --restart=Never \
  --image=curlimages/curl:latest -n sa-p5 \
  --labels="sa-p5/db-client=true,sa-p5/broker-client=true" -- sh -c '
    timeout 8 nc -zv sa-platform-postgresql 5432 && echo "PERMITIDO"
    timeout 8 nc -zv sa-platform-rabbitmq 5672 && echo "PERMITIDO"
  '
```

### Mensajes acumulados con el consumidor caído

```bash
# Detener el consumidor
kubectl scale deployment sa-platform-notifications-service -n sa-p5 --replicas=0

# Crear préstamos: el productor sigue respondiendo
for i in 1 2 3 4 5 6; do
  curl -s -H "Host: sa-p5.local" -H "Content-Type: application/json" \
    -X POST http://127.0.0.1/loans/graphql \
    -d "{\"query\":\"mutation { createLoan(userId: 90$i, bookId: 30$i) { id } }\"}" \
    -o /dev/null -w "prestamo $i -> HTTP %{http_code}\n"
done

# Los mensajes quedan en la cola durable
kubectl exec -n sa-p5 sa-platform-rabbitmq-0 -- \
  rabbitmqctl list_queues name messages durable

# Restaurar: se procesan sin pérdida
kubectl scale deployment sa-platform-notifications-service -n sa-p5 --replicas=1
kubectl logs -n sa-p5 -l app.kubernetes.io/component=notifications-service --tail=20
```

### Prueba de carga y escalado del HPA

En una terminal, observar el escalado:

```bash
kubectl get hpa -n sa-p5 -w
kubectl get pods -n sa-p5 -l app.kubernetes.io/component=api-gateway -w
```

En otra, lanzar la carga:

```bash
cd P5/loadtest
k6 run carga.js
```

### Actualización sin caída de servicio

En una terminal, tráfico continuo:

```bash
while true; do
  curl -s -o /dev/null -w "%{http_code} " -H "Host: sa-p5.local" http://127.0.0.1/
  sleep 0.25
done
```

En otra, el upgrade. No debe aparecer ningún código distinto de 200:

```bash
helm upgrade sa-platform . --namespace sa-p5 \
  -f values-dev.yaml -f values.secret.yaml \
  --set services.api-gateway.image.tag=v2 --wait
```

### CronJobs

```bash
# Ver las ejecuciones programadas
kubectl get cronjobs -n sa-p5
kubectl get jobs -n sa-p5

# Logs del Cronjob 1 (inserta fecha GMT-6 + carné)
kubectl logs -n sa-p5 -l app.kubernetes.io/component=cronjob-insert --tail=5

# Logs del Cronjob 2 (agrega y publica en el broker)
kubectl logs -n sa-p5 -l app.kubernetes.io/component=cronjob-summary --tail=5

# El consumidor almacena el resumen
kubectl logs -n sa-p5 -l app.kubernetes.io/component=notifications-service | grep resumen

# Forzar una ejecución sin esperar al schedule
kubectl create job --from=cronjob/sa-platform-cronjob-insert prueba-insert -n sa-p5
```

---

## 8. Despliegue en el ambiente de producción

El mismo chart con otro archivo de values: más réplicas, autoescalado en todos
los servicios, límites mayores, tag inmutable y nivel de log reducido.

```bash
helm upgrade --install sa-platform . \
  --namespace sa-p5 --create-namespace \
  -f values-prod.yaml \
  -f values.secret.yaml \
  --timeout 10m
```

| Parámetro | dev | prod |
|---|---|---|
| Réplicas del gateway | 1 | 3 |
| HPA | solo gateway | los 5 servicios |
| Nivel de log | `debug` | `warn` |
| Tag de imagen | `v1` / `v2` | `1.0.0` |
| Límite de CPU | 200m | 500m |
| Persistencia BD | 1Gi | 8Gi |

---

## 9. Desinstalar

```bash
helm uninstall sa-platform --namespace sa-p5
```

El namespace lleva `helm.sh/resource-policy: keep`, de modo que desinstalar el
release no lo borra con todo su contenido. Para eliminarlo por completo:

```bash
kubectl delete namespace sa-p5
```

Destruir el clúster:

```bash
minikube delete --profile=sa-p5
```

---

## Resumen: de cero a funcionando

```bash
# 1. Clúster
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

# 4. Instalar
helm install sa-platform . --namespace sa-p5 --create-namespace \
  -f values-dev.yaml -f values.secret.yaml --timeout 10m

# 5. Acceder (terminal aparte)
minikube tunnel --profile=sa-p5
curl -H "Host: sa-p5.local" http://127.0.0.1/
```
